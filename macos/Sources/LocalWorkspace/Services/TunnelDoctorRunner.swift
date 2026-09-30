import Foundation

/// Runs only the official configuration checker, in its own process group.
/// Never returns raw output: it can contain credentials or signed URLs.
final class TunnelDoctorRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var childPID: Int32 = 0

    func cancel() {
        lock.lock()
        cancelled = true
        let pid = childPID
        lock.unlock()
        // A user can quit the whole app immediately after dismissing diagnosis;
        // no asynchronous cleanup should be required to reap this read-only check.
        if pid > 0 { kill(-pid, SIGKILL) }
    }

    func run(resources: URL, tunnelID: String, apiKey: String) async -> String {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: self.check(resources: resources, tunnelID: tunnelID, apiKey: apiKey))
                }
            }
        } onCancel: { self.cancel() }
    }

    private func check(resources: URL, tunnelID: String, apiKey: String) -> String {
        let launcher = resources.appendingPathComponent("workspace-launcher")
        let client = resources.appendingPathComponent("tunnel-client")
        let backend = resources.appendingPathComponent("workspace-server")
        guard FileManager.default.isExecutableFile(atPath: launcher.path),
              FileManager.default.isExecutableFile(atPath: client.path) else {
            return "配置自检：不可用\n未找到完整的官方 Tunnel Client，请重新构建或安装应用。"
        }
        let process = Process()
        process.executableURL = launcher
        process.arguments = [client.path, "doctor", "--json", "--explain"]
        var environment = ProcessInfo.processInfo.environment
        for name in ["MCP_COMMAND", "MCP_SERVER_URL", "TUNNEL_CLIENT_CONFIG", "TUNNEL_CLIENT_PROFILE",
                     "TUNNEL_CLIENT_PROFILE_FILE", "CONTROL_PLANE_API_KEY", "CONTROL_PLANE_TUNNEL_ID",
                     "WORKSPACE_TUNNEL_ID", "WORKSPACE_TUNNEL_HEALTH_FILE", "HEALTH_UNIX_SOCKET",
                     "CLOUDFLARED_MANAGED", "CLOUDFLARED_TUNNEL_TOKEN"] {
            environment.removeValue(forKey: name)
        }
        environment["PATH"] = (environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["CONTROL_PLANE_TUNNEL_ID"] = tunnelID.trimmingCharacters(in: .whitespacesAndNewlines)
        environment["CONTROL_PLANE_API_KEY"] = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        environment["CONTROL_PLANE_BASE_URL"] = "https://api.openai.com"
        // doctor briefly binds the configured health listener. Use a separate ephemeral
        // loopback port so it cannot conflict with the live daemon or another local app.
        environment["HEALTH_LISTEN_ADDR"] = "127.0.0.1:0"
        environment["MCP_COMMAND"] = "'" + backend.path.replacingOccurrences(of: "'", with: "'\\''") + "' --mcp"
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            guard !isCancelled else { return "配置自检：已取消" }
            try process.run()
            lock.lock()
            childPID = process.processIdentifier
            let wasCancelled = cancelled
            lock.unlock()
            if wasCancelled { kill(-process.processIdentifier, SIGKILL) }
        } catch {
            // Process errors may include supplied configuration; use a fixed message.
            return "配置自检：失败\n无法启动官方检查器，请确认应用文件完整性。"
        }

        let output = DoctorOutputBuffer()
        let reads = DispatchGroup()
        for (pipe, capture) in [(stdout, true), (stderr, false)] {
            reads.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { reads.leave() }
                while let data = try? pipe.fileHandleForReading.read(upToCount: 16_384), !data.isEmpty {
                    if capture { output.append(data) }
                }
            }
        }
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline && !isCancelled { Thread.sleep(forTimeInterval: 0.025) }
        let timedOut = process.isRunning && !isCancelled
        if process.isRunning {
            kill(-process.processIdentifier, SIGTERM)
            let grace = Date().addingTimeInterval(0.2)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.025) }
            if process.isRunning { kill(-process.processIdentifier, SIGKILL) }
        }
        // Reap/clean only this diagnostic's group, never the active tunnel's group.
        let reapDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < reapDeadline { Thread.sleep(forTimeInterval: 0.025) }
        kill(-process.processIdentifier, SIGKILL)
        _ = reads.wait(timeout: .now() + 1)
        try? stdout.fileHandleForReading.close()
        try? stderr.fileHandleForReading.close()
        lock.lock()
        childPID = 0
        lock.unlock()
        if isCancelled { return "配置自检：已取消" }
        if timedOut { return "配置自检：超时\n官方检查器在 8 秒内未完成，诊断进程已结束。当前连接不受影响。" }
        return Self.safeReport(from: output.data)
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    static func safeReport(from data: Data) -> String {
        guard let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "配置自检：失败\n未收到有效的官方诊断结果，请确认 Tunnel Client 版本及文件完整性。"
        }
        let passed = ["pass", "ok"].contains((report["result"] as? String ?? "").lowercased())
        var lines = ["配置自检：\(passed ? "通过" : "未通过")\n由官方 Tunnel Client 检查；不代表 ChatGPT 已成功调用工具。"]
        let labels = ["config_source": "配置来源", "profile_load": "配置读取", "tunnel_id": "Tunnel ID",
                      "control_plane_api_key": "运行密钥", "api_key": "运行密钥", "mcp_transport": "MCP 传输",
                      "mcp_target": "MCP 目标", "mcp_command_executable": "本地程序", "mcp_command": "本地程序"]
        for row in (report["checks"] as? [[String: Any]] ?? []).prefix(100) {
            guard let id = row["id"] as? String, let label = labels[id] else { continue }
            let status = (row["status"] as? String ?? "").uppercased()
            let description = status == "PASS" ? "通过，配置检查通过。" : status == "FAIL" ? "未通过，请检查对应配置。" : "未检查，当前配置未检查该项目。"
            lines.append("\(label)：\(description)")
        }
        return lines.joined(separator: "\n\n")
    }
}

private final class DoctorOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        // Continue draining after this bound so a noisy checker cannot deadlock or grow memory.
        let room = 1_048_576 - storage.count
        if room > 0 { storage.append(data.prefix(room)) }
    }
    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
