import Foundation

enum Destination: String, CaseIterable, Identifiable {
    case workbench = "工作台", consult = "科研咨询", overview = "概览", activity = "操作记录", access = "本地能力", logs = "诊断日志"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .workbench: "rectangle.3.group"
        case .consult: "sparkles.rectangle.stack"
        case .activity: "clock.arrow.circlepath"
        case .access: "folder.badge.gearshape"
        case .logs: "terminal"
        }
    }
}

enum ConnectionState: Equatable {
    case stopped, starting, local, connected, reconnecting, failed
    var label: String {
        switch self {
        case .stopped: "未连接"
        case .starting: "正在连接"
        case .local: "本地检查"
        case .connected: "隧道已就绪"
        case .reconnecting: "等待重连"
        case .failed: "连接中断"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String
    var isError: Bool { text.localizedCaseInsensitiveContains("error") || text.contains("失败") }
    var isTool: Bool { text.contains("[Workspace]") }
}

struct ActivityEntry: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let threadId: String
    let tool: String
    let target: String
    let status: String
    let startedAt: String
    let elapsedMs: Int
    let errorCode: String?
    var isConnectionEvent: Bool { id.hasPrefix("native-") }
    var copyText: String {
        "\(startedAt)  \(threadId)  \(tool)  \(target)  \(statusLabel)  \(elapsedMs) ms" + (errorCode.map { "  \($0)" } ?? "")
    }
    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    var localTime: String {
        guard let date = Self.timestamp.date(from: startedAt) else { return startedAt }
        return date.formatted(date: .omitted, time: .standard)
    }
    var statusLabel: String { status == "failed" ? "失败" : status == "running" ? "运行中" : status == "status" ? "状态" : "已返回" }
    var displayTool: String {
        ["read_research_bundle": "读取研究资料", "submit_pro_report": "提交 Pro 报告",
         "get_workspace_status": "状态检查", "exec_command": "执行命令", "read_file": "读取文件",
         "write_file": "写入文件", "edit_file": "编辑文件", "apply_patch": "修改文件",
         "read_command": "读取输出", "poll_command": "读取输出", "list_directory": "浏览目录",
         "search_text": "搜索内容", "search_files": "搜索文件", "update_plan": "更新计划",
         "open_workspace": "打开工作区", "git_status": "Git 状态", "git_diff": "Git 差异",
         "check_task_completion": "检查任务", "read_image": "查看图片", "import_file": "接收附件",
         "restore_change": "恢复修改", "workspace_history": "修改历史"][tool] ?? "本地操作"
    }
}

struct Conversation: Decodable, Identifiable, Equatable, Sendable {
    let threadId: String
    let title: String
    let path: String?
    var source: String? = nil
    var createdAt: String? = nil
    var stats: ConversationStatistics? = nil
    var id: String { threadId }
    var sourceLabel: String { source == "codex" ? "Codex" : source == "chatgpt" ? "ChatGPT" : "本地会话" }
    var shortCode: String { String(threadId.replacingOccurrences(of: "thread-", with: "").suffix(6)).uppercased() }
    var recency: String { stats?.lastAt ?? createdAt ?? "" }
    private static let timestamp = ISO8601DateFormatter()
    private static let fractionalTimestamp: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    private static let displayDate: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "zh_CN"); value.dateFormat = "MM/dd HH:mm"; return value
    }()
    var createdLabel: String? {
        guard let createdAt, let date = Self.fractionalTimestamp.date(from: createdAt) ?? Self.timestamp.date(from: createdAt) else { return nil }
        return Self.displayDate.string(from: date)
    }
    func displayTitle(among peers: [Conversation]) -> String {
        let directory = path.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.lastPathComponent }
        let ambiguous = title == directory || title == "ChatGPT 对话" || title.isEmpty || peers.filter { $0.title == title }.count > 1
        return ambiguous ? sourceLabel + " · " + (createdLabel ?? "#" + shortCode) : title
    }
    var identityLine: String { "#" + shortCode + " · " + sourceLabel + (createdLabel.map { " · " + $0 } ?? "") }
    var sidebarSummary: String { "#" + shortCode + " · " + (stats?.calls.map { "\($0) 次操作" } ?? sourceLabel) }
}

struct ConversationStatistics: Decodable, Equatable, Sendable {
    let calls: Int?
    let running: Int?
    let failed: Int?
    let lastAt: String?
}

/// A directory can host several conversations. Grouping is presentation-only:
/// selecting a conversation still uses its original thread ID and never moves files.
struct WorkspaceDirectory: Identifiable {
    let id: String
    let path: String?
    let conversations: [Conversation]
    let latestActivity: [String: ActivityEntry]
    var title: String { path.map { URL(fileURLWithPath: $0).lastPathComponent.isEmpty ? $0 : URL(fileURLWithPath: $0).lastPathComponent } ?? "未设置目录" }
    var displayPath: String { path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "登记对话时可关联本地文件夹" }
    var lastActivity: String { (latestActivity.values.map(\.startedAt) + conversations.map(\.recency)).max() ?? "" }
    func visibleConversations(expanded: Bool, selected: String) -> [Conversation] {
        if expanded { return conversations }
        var rows = Array(conversations.prefix(3))
        if !rows.contains(where: { $0.id == selected }), let chosen = conversations.first(where: { $0.id == selected }) { rows.append(chosen) }
        return rows
    }

    static func grouped(_ conversations: [Conversation], activity: [ActivityEntry]) -> [WorkspaceDirectory] {
        var latest: [String: ActivityEntry] = [:]
        for entry in activity where !entry.isConnectionEvent {
            if latest[entry.threadId].map({ $0.startedAt < entry.startedAt }) ?? true { latest[entry.threadId] = entry }
        }
        let buckets = Dictionary(grouping: conversations) { conversation in
            conversation.path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path } ?? ""
        }
        return buckets.map { key, values in
            let rows = values.sorted {
                let left = latest[$0.id]?.startedAt ?? $0.recency, right = latest[$1.id]?.startedAt ?? $1.recency
                if left != right { return left > right }
                return $0.title == $1.title ? $0.id < $1.id : $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return WorkspaceDirectory(id: key, path: key.isEmpty ? nil : key, conversations: rows,
                                      latestActivity: latest.filter { item in values.contains { $0.id == item.key } })
        }.sorted {
            if $0.path == nil || $1.path == nil { return $0.path != nil && $1.path == nil }
            if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
            return ($0.path ?? "").localizedStandardCompare($1.path ?? "") == .orderedAscending
        }
    }
}

struct ConsultReceiptSummary: Codable, Identifiable, Equatable, Sendable {
    let reportPath: String
    let sha256: String
    let summary: String?
    let byteLength: Int?
    let lineCount: Int?
    let createdAt: String?
    var id: String { reportPath + ":" + sha256 }
    var shortSha: String { String(sha256.prefix(12)) }
    var displayReportPath: String { (reportPath as NSString).abbreviatingWithTildeInPath }

    init(reportPath: String, sha256: String, summary: String? = nil, byteLength: Int? = nil, lineCount: Int? = nil, createdAt: String? = nil) {
        self.reportPath = reportPath
        self.sha256 = sha256
        self.summary = summary
        self.byteLength = byteLength
        self.lineCount = lineCount
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case reportPath, report_path
        case sha256
        case summary
        case byteLength, byte_length
        case lineCount, line_count
        case createdAt, created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.reportPath = try container.decodeIfPresent(String.self, forKey: .reportPath)
            ?? container.decodeIfPresent(String.self, forKey: .report_path) ?? ""
        self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256) ?? ""
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.byteLength = try container.decodeIfPresent(Int.self, forKey: .byteLength)
            ?? container.decodeIfPresent(Int.self, forKey: .byte_length)
        self.lineCount = try container.decodeIfPresent(Int.self, forKey: .lineCount)
            ?? container.decodeIfPresent(Int.self, forKey: .line_count)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? container.decodeIfPresent(String.self, forKey: .created_at)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reportPath, forKey: .reportPath)
        try container.encode(sha256, forKey: .sha256)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(byteLength, forKey: .byteLength)
        try container.encodeIfPresent(lineCount, forKey: .lineCount)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

struct ConsultSessionSummary: Codable, Identifiable, Equatable, Sendable {
    let consultId: String
    let title: String
    let inboxDir: String
    let fileCount: Int
    let bundleSha256: String
    let status: String
    let stagedAt: String?
    let lastReadAt: String?
    let threadId: String?
    let webProPrompt: String?
    let receipt: ConsultReceiptSummary?
    var id: String { consultId }

    var shortSha: String { String(bundleSha256.prefix(12)) }
    var displayInboxDir: String { (inboxDir as NSString).abbreviatingWithTildeInPath }
    var stageIndex: Int { status == "completed" ? 3 : status == "reading" ? 2 : 1 }
    var statusLabel: String {
        switch status {
        case "completed": "报告已归档"
        case "reading": "Web Pro 读取中"
        default: "已打包待读取"
        }
    }
    private static let timestamp = ISO8601DateFormatter()
    private static let fractionalTimestamp: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    private static let displayDate: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "zh_CN"); value.dateFormat = "MM/dd HH:mm"; return value
    }()
    var updatedLabel: String? {
        let raw = receipt?.createdAt ?? lastReadAt ?? stagedAt
        guard let raw, let date = Self.fractionalTimestamp.date(from: raw) ?? Self.timestamp.date(from: raw) else { return nil }
        return Self.displayDate.string(from: date)
    }
    var t3ReceiptText: String {
        guard let receipt else { return "[Web Pro Consult]\nconsult_id: \(consultId)\ntitle: \(title)\nstatus: \(status)" }
        var lines = [
            "[Web Pro Consult Completed]",
            "consult_id: \(consultId)",
            "title: \(title)",
            "report_path: \(receipt.reportPath)",
            "sha256: \(receipt.sha256)"
        ]
        if let lineCount = receipt.lineCount, let byteLength = receipt.byteLength {
            lines.append("metrics: \(lineCount) lines · \(byteLength) bytes")
        }
        if let summary = receipt.summary, !summary.isEmpty {
            lines.append("summary: \(summary)")
        }
        return lines.joined(separator: "\n")
    }

    init(consultId: String, title: String, inboxDir: String, fileCount: Int, bundleSha256: String,
         status: String = "staged", stagedAt: String? = nil, lastReadAt: String? = nil,
         threadId: String? = nil, webProPrompt: String? = nil, receipt: ConsultReceiptSummary? = nil) {
        self.consultId = consultId
        self.title = title
        self.inboxDir = inboxDir
        self.fileCount = fileCount
        self.bundleSha256 = bundleSha256
        self.status = status
        self.stagedAt = stagedAt
        self.lastReadAt = lastReadAt
        self.threadId = threadId
        self.webProPrompt = webProPrompt
        self.receipt = receipt
    }

    private enum CodingKeys: String, CodingKey {
        case consultId, consult_id
        case title
        case inboxDir, inbox_dir
        case fileCount, file_count
        case bundleSha256, bundle_sha256
        case status
        case stagedAt, staged_at
        case lastReadAt, last_read_at
        case threadId, thread_id
        case webProPrompt, web_pro_prompt
        case receipt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.consultId = try container.decodeIfPresent(String.self, forKey: .consultId)
            ?? container.decodeIfPresent(String.self, forKey: .consult_id) ?? ""
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.inboxDir = try container.decodeIfPresent(String.self, forKey: .inboxDir)
            ?? container.decodeIfPresent(String.self, forKey: .inbox_dir) ?? ""
        self.fileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount)
            ?? container.decodeIfPresent(Int.self, forKey: .file_count) ?? 0
        self.bundleSha256 = try container.decodeIfPresent(String.self, forKey: .bundleSha256)
            ?? container.decodeIfPresent(String.self, forKey: .bundle_sha256) ?? ""
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "staged"
        self.stagedAt = try container.decodeIfPresent(String.self, forKey: .stagedAt)
            ?? container.decodeIfPresent(String.self, forKey: .staged_at)
        self.lastReadAt = try container.decodeIfPresent(String.self, forKey: .lastReadAt)
            ?? container.decodeIfPresent(String.self, forKey: .last_read_at)
        self.threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
            ?? container.decodeIfPresent(String.self, forKey: .thread_id)
        self.webProPrompt = try container.decodeIfPresent(String.self, forKey: .webProPrompt)
            ?? container.decodeIfPresent(String.self, forKey: .web_pro_prompt)
        self.receipt = try container.decodeIfPresent(ConsultReceiptSummary.self, forKey: .receipt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(consultId, forKey: .consultId)
        try container.encode(title, forKey: .title)
        try container.encode(inboxDir, forKey: .inboxDir)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(bundleSha256, forKey: .bundleSha256)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(stagedAt, forKey: .stagedAt)
        try container.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
        try container.encodeIfPresent(threadId, forKey: .threadId)
        try container.encodeIfPresent(webProPrompt, forKey: .webProPrompt)
        try container.encodeIfPresent(receipt, forKey: .receipt)
    }
}

struct DashboardSnapshot: Decodable, Sendable {
    let version: String?
    let activity: [ActivityEntry]
    let conversations: [Conversation]
    let commands: [CommandStatus]?
    let consults: [ConsultSessionSummary]?
}

struct CommandStatus: Decodable, Sendable {
    let running: Bool
}

struct WorkspaceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
