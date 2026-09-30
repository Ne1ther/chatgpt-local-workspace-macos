import AppKit
import Foundation
import Observation

@MainActor @Observable
final class WorkspaceStore {
    var destination: Destination? = .overview
    var state: ConnectionState = .stopped
    var showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        }
    }
    var showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            AppPresenceController.applyDockPreference()
            NotificationCenter.default.post(name: AppPresenceController.dockPreferenceDidChange, object: nil)
        }
    }
    var tunnelID = UserDefaults.standard.string(forKey: "tunnelID") ?? ""
    var apiKey = ""
    var settingsMessage = ""
    var issue: String?
    var dashboardURL: URL?
    var dashboardRevision = UUID()
    var logs: [LogEntry] = []
    var activity: [ActivityEntry] = []
    var conversations: [Conversation] = []
    var diagnostics: String?
    var localCheckPassed = false
    var actualCallObserved = false
    var snapshotStale = false
    var busy = false
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var errors: Pipe?
    private var monitor: Task<Void, Never>?
    private var startup: Task<Void, Never>?
    private var healthFile: URL?
    private var sessionDirectory: URL?
    private var testDirectory: URL?
    private var buffers: [String: Data] = [:]
    private var generation = UUID()
    private var requestID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]

    var running: Bool { process?.isRunning == true }
    var canConnect: Bool { tunnelID.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^tunnel_[A-Za-z0-9]+$", options: .regularExpression) != nil && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 }
    var supportURL: URL { URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")! }
    var resourceURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Backend") }

    init() {
        do { apiKey = try KeychainStore.read() }
        catch { settingsMessage = error.localizedDescription }
    }

    func saveSettings() {
        do {
            guard canConnect else { throw WorkspaceError(message: "请填写有效的 Tunnel ID 和运行密钥。") }
            apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try KeychainStore.save(apiKey)
            tunnelID = tunnelID.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(tunnelID, forKey: "tunnelID")
            settingsMessage = "已保存。运行密钥保存在 macOS 钥匙串。"
        } catch { settingsMessage = error.localizedDescription }
    }

    func log(_ value: String) {
        var text = value
        if !apiKey.isEmpty { text = text.replacingOccurrences(of: apiKey, with: "[密钥已隐藏]") }
        // Redact keys and signed query strings before they reach native UI or copying.
        text = text.replacingOccurrences(of: "sk-[A-Za-z0-9_-]+", with: "[密钥已隐藏]", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(https?://[^\s?"\\]+)\?[^\s"\\]+"#, with: "$1?[query hidden]", options: .regularExpression)
        logs.append(LogEntry(text: String(text.prefix(16000))))
        if logs.count > 2000 { logs.removeFirst(logs.count - 2000) }
    }

    private func receive(_ data: Data, channel: String, generation expected: UUID) {
        guard generation == expected else { return }
        buffers[channel, default: Data()].append(data)
        while let boundary = buffers[channel]?.firstIndex(of: 10) {
            let line = String(decoding: buffers[channel]![..<boundary], as: UTF8.self)
            buffers[channel] = Data(buffers[channel]![buffers[channel]!.index(after: boundary)...])
            if channel == "stdout", state == .local,
               let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                timeouts.removeValue(forKey: id)?.cancel()
                if let error = object["error"] as? [String: Any] {
                    continuation.resume(throwing: WorkspaceError(message: error["message"] as? String ?? "MCP 请求失败"))
                } else { continuation.resume(returning: object["result"] as? [String: Any] ?? [:]) }
                continue
            }
            if line.isEmpty { continue }
            var message = line
            if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let value = object["msg"] as? String { message = value + " " + line }
            if let range = message.range(of: #"\[Dashboard\] (http://127\.0\.0\.1:\d+/)"#, options: .regularExpression) {
                let urlText = String(message[range]).replacingOccurrences(of: "[Dashboard] ", with: "")
                if let url = URL(string: urlText) { dashboardURL = url }
            }
            if message.contains("[Workspace]") && message.contains(" | RETURNED") && state != .local {
                actualCallObserved = true
            }
            log(line)
        }
        if (buffers[channel]?.count ?? 0) > 512_000 { buffers[channel] = Data(); log("一条超长日志已截断。") }
    }

    private func launch(executable: URL, arguments: [String], environment additions: [String: String] = [:]) throws {
        let launch = resourceURL.appendingPathComponent("workspace-launcher")
        guard FileManager.default.isExecutableFile(atPath: executable.path), FileManager.default.isExecutableFile(atPath: launch.path) else {
            throw WorkspaceError(message: "应用组件缺失，请重新构建或安装完整的 ChatGPT Codex Workspace.app。")
        }
        let child = Process()
        child.executableURL = launch
        child.arguments = [executable.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        for name in ["MCP_COMMAND", "MCP_SERVER_URL", "TUNNEL_CLIENT_CONFIG", "TUNNEL_CLIENT_PROFILE", "TUNNEL_CLIENT_PROFILE_FILE", "CONTROL_PLANE_API_KEY", "WORKSPACE_TUNNEL_ID", "WORKSPACE_TUNNEL_HEALTH_FILE", "CLOUDFLARED_MANAGED", "CLOUDFLARED_TUNNEL_TOKEN"] { environment.removeValue(forKey: name) }
        environment["PATH"] = (environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment.merge(additions) { _, new in new }
        child.environment = environment
        child.currentDirectoryURL = sessionDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        let expected = generation
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(data, channel: "stdout", generation: expected) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(data, channel: "stderr", generation: expected) }
        }
        child.terminationHandler = { [weak self] child in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                self.fail("后台进程已退出（\(child.terminationStatus)）。请查看原始日志。")
            }
        }
        try child.run()
        process = child; input = stdin; output = stdout; errors = stderr
        startMonitor()
    }

    func connect() {
        guard canConnect, !busy else { issue = "请先在连接设置中填写 Tunnel ID 和运行密钥。"; return }
        stop()
        saveSettings()
        state = .starting; busy = true; issue = nil; activity = []; conversations = []
        let expected = generation
        startup = Task {
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("local-workspace-session-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                sessionDirectory = directory
                let health = directory.appendingPathComponent("health.url")
                healthFile = health
                let backend = resourceURL.appendingPathComponent("workspace-server")
                let command = "'" + backend.path.replacingOccurrences(of: "'", with: "'\\''") + "' --mcp"
                try launch(executable: resourceURL.appendingPathComponent("tunnel-client"), arguments: [
                    "run", "--control-plane.tunnel-id", tunnelID,
                    "--control-plane.base-url", "https://api.openai.com",
                    "--health.listen-addr", "127.0.0.1:0", "--health.url-file", health.path,
                    "--log.format", "json", "--log.level", "info"
                ], environment: ["CONTROL_PLANE_API_KEY": apiKey, "MCP_COMMAND": command,
                                 "WORKSPACE_TUNNEL_ID": tunnelID, "WORKSPACE_TUNNEL_HEALTH_FILE": health.path])
                log("正在启动官方 Tunnel，等待就绪。")
                for _ in 0..<60 {
                    try Task.checkCancellation()
                    guard generation == expected, running else { return }
                    if let url = healthURL(), await probe(url.appendingPathComponent("readyz")) {
                        guard generation == expected else { return }
                        state = .connected; busy = false
                        log("隧道已就绪。请在 ChatGPT 刷新插件并调用 get_workspace_status 验证实际连接。")
                        destination = .workbench
                        return
                    }
                    try await Task.sleep(for: .milliseconds(750))
                }
                throw WorkspaceError(message: "连接超时。请检查 Tunnel ID、密钥、网络和隧道权限。")
            } catch is CancellationError { }
            catch { if generation == expected { fail(error.localizedDescription) } }
        }
    }

    func runLocalCheck() {
        guard !busy else { return }
        stop(); state = .local; busy = true; issue = nil; activity = []; conversations = []; localCheckPassed = false
        let expected = generation
        startup = Task {
            do {
                try launch(executable: resourceURL.appendingPathComponent("workspace-server"), arguments: ["--mcp"])
                _ = try await rpc("initialize", params: ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "mac-local-check", "version": "1.0"]])
                let discovery = try await rpc("tools/list")
                guard (discovery["tools"] as? [Any])?.count == 26 else { throw WorkspaceError(message: "工具发现数量不符。") }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("local-workspace-check-" + UUID().uuidString).resolvingSymlinksInPath()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                testDirectory = directory
                let thread = try await call("register_conversation", ["title": "本地自检 · 非 ChatGPT 对话", "path": directory.path])
                let tid = thread["thread_id"] as? String ?? ""
                let path = directory.appendingPathComponent("检查.txt").path
                _ = try await call("write_file", ["path": path, "content": "macOS 本地工作区检查通过\n", "thread_id": tid])
                _ = try await call("read_file", ["path": path, "thread_id": tid])
                let shell = try await call("exec_command", ["cwd": directory.path, "cmd": "printf 'macOS-shell-ok'", "yield_time_ms": 1000, "thread_id": tid])
                guard (shell["output"] as? String)?.contains("macOS-shell-ok") == true else { throw WorkspaceError(message: "Shell 检查未通过。") }
                _ = try await call("get_workspace_status", ["thread_id": tid])
                guard generation == expected else { return }
                localCheckPassed = true; busy = false
                log("本地检查通过：MCP 握手、26 个工具、中文文件读写和 zsh 命令。尚未连接 ChatGPT。")
                destination = .workbench
            } catch is CancellationError { }
            catch { if generation == expected { fail(error.localizedDescription) } }
        }
    }

    private func rpc(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        requestID += 1
        let id = requestID
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params]) + Data([10])
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                pending.removeValue(forKey: id)?.resume(throwing: WorkspaceError(message: "本地检查超时。"))
                timeouts.removeValue(forKey: id)
            }
            do { try input?.fileHandleForWriting.write(contentsOf: data) }
            catch {
                timeouts.removeValue(forKey: id)?.cancel()
                pending.removeValue(forKey: id)?.resume(throwing: error)
            }
        }
    }

    private func call(_ tool: String, _ arguments: [String: Any]) async throws -> [String: Any] {
        let response = try await rpc("tools/call", params: ["name": tool, "arguments": arguments])
        if response["isError"] as? Bool == true { throw WorkspaceError(message: "本地检查失败：\(tool)") }
        return (response["structuredContent"] as? [String: Any])?["result"] as? [String: Any] ?? [:]
    }

    private func healthURL() -> URL? {
        guard let file = healthFile, let text = try? String(contentsOf: file, encoding: .utf8),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http", url.host == "127.0.0.1" else { return nil }
        return url
    }
    private func probe(_ url: URL) async -> Bool {
        var request = URLRequest(url: url); request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
    private func startMonitor() {
        monitor?.cancel()
        let expected = generation
        monitor = Task {
            var tick = 0
            while !Task.isCancelled && generation == expected {
                if let url = dashboardURL {
                    var request = URLRequest(url: url.appendingPathComponent("api/snapshot")); request.timeoutInterval = 2
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard generation == expected else { return }
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WorkspaceError(message: "状态读取失败") }
                        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                        let snapshot = try decoder.decode(DashboardSnapshot.self, from: data)
                        activity = snapshot.activity.reversed(); conversations = snapshot.conversations
                        snapshotStale = false
                    } catch { if generation == expected { snapshotStale = true } }
                }
                tick += 1
                if tick % 4 == 0, state == .connected || state == .reconnecting, let url = healthURL() {
                    let healthy = await probe(url.appendingPathComponent("readyz"))
                    guard generation == expected else { return }
                    let warning = "隧道暂未就绪，正在等待网络恢复。本地任务继续运行。"
                    if !healthy { state = .reconnecting; issue = warning }
                    else { state = .connected; if issue == warning { issue = nil } }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func showDiagnostics() {
        guard let base = dashboardURL else {
            diagnostics = "本地程序：\(FileManager.default.isExecutableFile(atPath: resourceURL.appendingPathComponent("workspace-server").path) ? "可用" : "缺失")\n官方 Tunnel：\(FileManager.default.isExecutableFile(atPath: resourceURL.appendingPathComponent("tunnel-client").path) ? "可用" : "缺失")\n连接配置：\(canConnect ? "已填写" : "尚未填写完整")\n实际 ChatGPT 调用：待验证"
            return
        }
        Task {
            do {
                var request = URLRequest(url: base.appendingPathComponent("api/diagnostics")); request.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: request)
                let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let checks = value?["checks"] as? [[String: Any]] ?? []
                diagnostics = checks.map { "\($0["label"] ?? "")：\($0["status"] ?? "")\n\($0["detail"] ?? "")" }.joined(separator: "\n\n")
            } catch { diagnostics = "诊断读取失败：\(error.localizedDescription)" }
        }
    }

    func stop() {
        generation = UUID()
        startup?.cancel(); startup = nil
        monitor?.cancel(); monitor = nil
        for task in timeouts.values { task.cancel() }; timeouts.removeAll()
        for continuation in pending.values { continuation.resume(throwing: CancellationError()) }; pending.removeAll()
        if let child = process {
            child.terminationHandler = nil
            try? input?.fileHandleForWriting.close()
            if child.isRunning {
                let group = child.processIdentifier
                kill(-group, SIGTERM)
                // Give the MCP worker time to clean up its owned command sessions.
                let deadline = Date().addingTimeInterval(0.8)
                while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                if child.isRunning { kill(-group, SIGKILL) }
            }
        }
        output?.fileHandleForReading.readabilityHandler = nil
        errors?.fileHandleForReading.readabilityHandler = nil
        process = nil; input = nil; output = nil; errors = nil
        if let directory = sessionDirectory { try? FileManager.default.removeItem(at: directory) }
        if let directory = testDirectory { try? FileManager.default.removeItem(at: directory) }
        sessionDirectory = nil; testDirectory = nil; healthFile = nil
        dashboardURL = nil; buffers = [:]; state = .stopped; busy = false
        actualCallObserved = false; snapshotStale = false
    }
    private func fail(_ message: String) { stop(); issue = message; state = .failed; log(message) }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func openBrowser() { if let url = dashboardURL { NSWorkspace.shared.open(url) } }
    func refreshDashboard() { dashboardRevision = UUID() }
}
