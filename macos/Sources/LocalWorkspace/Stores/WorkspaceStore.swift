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
    @ObservationIgnored let dashboardSession = WorkspaceDashboardSession()
    var coreVersion = WorkspaceCore.version
    var logs: [LogEntry] = []
    var activity: [ActivityEntry] = []
    var conversations: [Conversation] = []
    var diagnostics: String?
    var diagnosticsBusy = false
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
    private var diagnosticTask: Task<Void, Never>?
    private var doctor: TunnelDoctorRunner?
    private var diagnosticGeneration = UUID()
    private var healthFile: URL?
    private var sessionDirectory: URL?
    private var testDirectory: URL?
    private var buffers: [String: Data] = [:]
    private var generation = UUID()
    private var requestID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var hiddenActivityIDs: Set<String> = []
    private var latestBackendActivityIDs: Set<String> = []

    var running: Bool { process?.isRunning == true }
    var canConnect: Bool { tunnelID.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^tunnel_[A-Za-z0-9]+$", options: .regularExpression) != nil && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 }
    var supportURL: URL { URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")! }
    var resourceURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Backend") }
    var tunnelStatusURL: URL? { healthURL()?.appendingPathComponent("ui") }

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

    private func redacted(_ value: String) -> String {
        var text = value
        if !apiKey.isEmpty { text = text.replacingOccurrences(of: apiKey, with: "[密钥已隐藏]") }
        // Redact keys and signed query strings before they reach native UI or copying.
        text = text.replacingOccurrences(of: "sk-[A-Za-z0-9_-]+", with: "[密钥已隐藏]", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(https?://[^\s?"\\]+)\?[^\s"\\]+"#, with: "$1?[query hidden]", options: .regularExpression)
        return text
    }

    func log(_ value: String, recordActivity: Bool = true) {
        let text = redacted(value)
        logs.append(LogEntry(text: String(text.prefix(16000))))
        if logs.count > 2000 { logs.removeFirst(logs.count - 2000) }
        if recordActivity {
            let timestamp = ISO8601DateFormatter()
            timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            mergeActivity([ActivityEntry(id: "native-" + UUID().uuidString, threadId: "unassigned", tool: "连接状态",
                                        target: String(text.prefix(2000)), status: "status", startedAt: timestamp.string(from: Date()), elapsedMs: 0, errorCode: nil)])
        }
    }

    private func mergeActivity(_ incoming: [ActivityEntry]) {
        var merged = Dictionary(activity.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for row in incoming where !hiddenActivityIDs.contains(row.id) {
            merged[row.id] = ActivityEntry(id: row.id, threadId: row.threadId, tool: row.tool, target: redacted(row.target),
                                           status: row.status, startedAt: row.startedAt, elapsedMs: row.elapsedMs,
                                           errorCode: row.errorCode.map(redacted))
        }
        activity = Array(merged.values.sorted {
            if $0.startedAt == $1.startedAt { return $0.id > $1.id }
            return $0.startedAt > $1.startedAt
        }.prefix(WorkspaceCore.activityLimit))
    }

    func clearActivity() {
        hiddenActivityIDs.formUnion(latestBackendActivityIDs)
        activity.removeAll()
    }

    func reviewActivity(_ entry: ActivityEntry?) {
        guard let entry, !entry.isConnectionEvent, dashboardURL != nil else { return }
        destination = .workbench
        if let url = dashboardURL { _ = dashboardSession.view(for: url, revision: dashboardRevision) }
        dashboardSession.showActivity(entry)
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
                if let url = URL(string: urlText), WorkspaceLocalURL.isSafe(url) { dashboardURL = url }
            }
            if message.contains("[Workspace]") && message.contains(" | RETURNED") && state != .local {
                actualCallObserved = true
            }
            // The backend snapshot supplies tool rows with stable IDs; do not duplicate them from logs.
            let isToolReceipt = message.contains("[Workspace]") &&
                !["initialize", "tools/list", "server/discover", "runtime failed"].contains(where: message.contains)
            log(line, recordActivity: !isToolReceipt && (!line.hasPrefix("{") || message.localizedCaseInsensitiveContains("error") || message.localizedCaseInsensitiveContains("warn")))
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
        state = .starting; busy = true; issue = nil
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
        stop(); state = .local; busy = true; issue = nil; localCheckPassed = false
        let expected = generation
        startup = Task {
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("local-workspace-check-" + UUID().uuidString).resolvingSymlinksInPath()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                testDirectory = directory
                try launch(executable: resourceURL.appendingPathComponent("workspace-server"), arguments: ["--mcp"],
                           environment: ["WORKSPACE_STATE_DIR": directory.appendingPathComponent("state").path])
                _ = try await rpc("initialize", params: ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "mac-local-check", "version": "1.0"]])
                let discovery = try await rpc("tools/list")
                let count = (discovery["tools"] as? [Any])?.count ?? 0
                guard count == WorkspaceCore.toolCount else {
                    throw WorkspaceError(message: "工具发现数量不符：收到 \(count) 个，核心 \(WorkspaceCore.version) 应提供 \(WorkspaceCore.toolCount) 个。请重新构建完整应用；连接 ChatGPT 后也需刷新插件工具元数据。")
                }
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
                log("本地检查通过：MCP 握手、\(WorkspaceCore.toolCount) 个工具、中文文件读写和 zsh 命令。尚未连接 ChatGPT。")
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
        guard let file = healthFile, let data = try? Data(contentsOf: file), data.count <= 16_384 else { return nil }
        return WorkspaceLocalURL.healthURL(from: data)
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
                        latestBackendActivityIDs = Set(snapshot.activity.map(\.id))
                        hiddenActivityIDs.formIntersection(latestBackendActivityIDs)
                        mergeActivity(snapshot.activity)
                        var known = Dictionary(conversations.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                        for conversation in snapshot.conversations { known[conversation.id] = conversation }
                        conversations = known.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                        if let version = snapshot.version, !version.isEmpty { coreVersion = String(version.prefix(32)) }
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
        closeDiagnostics()
        diagnostics = "正在检查连接配置…\n诊断不会停止当前连接。"
        diagnosticsBusy = true
        let expected = diagnosticGeneration
        let base = dashboardURL
        let runner = TunnelDoctorRunner()
        doctor = runner
        let resources = resourceURL, tunnel = tunnelID, key = apiKey
        diagnosticTask = Task {
            var report: String?
            if let base {
                do {
                    var request = URLRequest(url: base.appendingPathComponent("api/diagnostics")); request.timeoutInterval = 12
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576,
                          let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let checks = value["checks"] as? [[String: Any]], !checks.isEmpty else {
                        throw WorkspaceError(message: "诊断暂不可用")
                    }
                    report = checks.prefix(100).map {
                        let status = $0["status"] as? String ?? "unavailable"
                        let label = status == "pass" ? "通过" : status == "fail" ? "未通过" : status == "pending" ? "待验证" : "未检查"
                        return "\($0["label"] as? String ?? "检查")：\(label)\n\($0["detail"] as? String ?? "")"
                    }.joined(separator: "\n\n")
                } catch is CancellationError { return }
                catch { /* A failed/stale backend must not block standalone configuration diagnosis. */ }
            }
            if report == nil {
                report = await runner.run(resources: resources, tunnelID: tunnel, apiKey: key)
                report! += "\n\n本地程序：\(FileManager.default.isExecutableFile(atPath: resources.appendingPathComponent("workspace-server").path) ? "可用" : "缺失")\n实际 ChatGPT 调用：\(actualCallObserved ? "已观察到" : "待验证")"
            }
            guard !Task.isCancelled, diagnosticGeneration == expected else { return }
            diagnostics = redacted(report ?? "未收到诊断结果。") + "\n\n核心 \(coreVersion) · \(WorkspaceCore.toolCount) 个工具\n计划、对话与近期活动在本地加密保存。历史恢复仅覆盖工具直接修改的文件；命令进程、Shell 副作用与图片预览不会跨重启恢复。"
            diagnosticsBusy = false
            doctor = nil
            diagnosticTask = nil
        }
    }

    func closeDiagnostics() {
        diagnosticGeneration = UUID()
        diagnosticTask?.cancel()
        diagnosticTask = nil
        doctor?.cancel()
        doctor = nil
        diagnosticsBusy = false
        diagnostics = nil
    }

    func stop() {
        closeDiagnostics()
        let wasActive = running || busy
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
        dashboardSession.reset()
        dashboardURL = nil; buffers = [:]; state = .stopped; busy = false
        actualCallObserved = false
        if wasActive { log("连接已停止，保留上次操作记录。计划、对话与近期活动已本地保存；命令进程不跨重启恢复。") }
        snapshotStale = !activity.isEmpty
    }
    private func fail(_ message: String) { stop(); issue = redacted(message); state = .failed; log(message) }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(redacted(text), forType: .string) }
    func openBrowser() { if let url = dashboardURL { NSWorkspace.shared.open(url) } }
    func openTunnelStatus() { if let url = tunnelStatusURL { NSWorkspace.shared.open(url) } }
    func refreshDashboard() { dashboardRevision = UUID() }
}
