import Foundation

enum Destination: String, CaseIterable, Identifiable {
    case workbench = "工作台", overview = "概览", activity = "操作记录", access = "本地能力", logs = "诊断日志"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .workbench: "rectangle.3.group"
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
        ["get_workspace_status": "状态检查", "exec_command": "执行命令", "read_file": "读取文件",
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

struct DashboardSnapshot: Decodable, Sendable {
    let version: String?
    let activity: [ActivityEntry]
    let conversations: [Conversation]
    let commands: [CommandStatus]?
}

struct CommandStatus: Decodable, Sendable {
    let running: Bool
}

struct WorkspaceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
