import Foundation

enum Destination: String, CaseIterable, Identifiable {
    case overview = "概览", workbench = "实时工作台", activity = "操作记录", logs = "原始日志"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .workbench: "rectangle.3.group"
        case .activity: "clock.arrow.circlepath"
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

struct ActivityEntry: Decodable, Identifiable {
    let id: String
    let threadId: String
    let tool: String
    let target: String
    let status: String
    let startedAt: String
    let elapsedMs: Int
    let errorCode: String?
    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    var localTime: String {
        guard let date = Self.timestamp.date(from: startedAt) else { return startedAt }
        return date.formatted(date: .omitted, time: .standard)
    }
    var statusLabel: String { status == "failed" ? "失败" : status == "running" ? "运行中" : "已返回" }
}

struct Conversation: Decodable, Identifiable {
    let threadId: String
    let title: String
    var id: String { threadId }
}

struct DashboardSnapshot: Decodable {
    let activity: [ActivityEntry]
    let conversations: [Conversation]
}

struct WorkspaceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
