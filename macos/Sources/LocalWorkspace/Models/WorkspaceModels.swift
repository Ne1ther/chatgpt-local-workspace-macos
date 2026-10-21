import Foundation

enum Destination: String, CaseIterable, Identifiable {
    case overview = "概览", workbench = "工作台", activity = "操作记录", access = "本地能力", logs = "诊断日志"
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

struct ActivityEntry: Decodable, Identifiable, Equatable {
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

struct Conversation: Decodable, Identifiable, Equatable {
    let threadId: String
    let title: String
    let path: String?
    var id: String { threadId }
}

struct DashboardSnapshot: Decodable {
    let version: String?
    let activity: [ActivityEntry]
    let conversations: [Conversation]
    let commands: [CommandStatus]?
}

struct CommandStatus: Decodable {
    let running: Bool
}

struct WorkspaceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
