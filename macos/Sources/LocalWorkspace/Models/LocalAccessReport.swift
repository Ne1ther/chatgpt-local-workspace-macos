import Foundation

struct LocalAccessReport: Decodable {
    struct Check: Decodable {
        let status: String
        let message: String
        let errorCode: String?
        var passed: Bool { status == "available" }
        var label: String {
            switch status {
            case "available": "可用"
            case "denied": "访问被拒绝"
            case "missing": "路径不存在"
            case "cleanup_required": "需要清理临时文件"
            case "not_checked": "尚未检查"
            default: "检查未通过"
            }
        }
    }
    let path: String
    let canonicalPath: String?
    let checkedAt: String
    let read: Check
    let write: Check
    let probeFile: String?
    let scope: String
    var checkedTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: checkedAt)?.formatted(date: .abbreviated, time: .standard) ?? checkedAt
    }
    var copyText: String {
        "目录：\(path)\n解析位置：\(canonicalPath ?? path)\n读取：\(read.label) · \(read.message)\n写入：\(write.label) · \(write.message)\n检查时间：\(checkedAt)\n\(scope)" + (probeFile.map { "\n待清理：\($0)" } ?? "")
    }
}

struct WorkspaceAdvice: Identifiable, Equatable {
    enum Action: Equatable { case settings, diagnostics, access, workbench }
    let id: String
    let title: String
    let detail: String
    let action: Action
    let actionLabel: String
}

enum WorkspaceHealthAdvisor {
    // Derived from existing observations only: no new polling, model request,
    // automatic permission change, log deletion, or command retry.
    static func recommendations(state: ConnectionState, stale: Bool, observed: Bool,
                                activity: [ActivityEntry], access: LocalAccessReport?) -> [WorkspaceAdvice] {
        var result: [WorkspaceAdvice] = []
        if access?.probeFile != nil {
            result.append(.init(id: "probe-cleanup", title: "权限检查的临时文件需要清理", detail: access!.probeFile!, action: .access, actionLabel: "查看位置"))
        }
        if stale && state != .stopped && state != .local {
            result.append(.init(id: "stale", title: "当前显示的是上次状态", detail: "等待本机状态恢复后，再判断任务是否仍在运行。", action: .diagnostics, actionLabel: "检查连接"))
        } else if state == .failed || state == .reconnecting {
            result.append(.init(id: "connection", title: "连接需要检查", detail: "诊断会检查当前连接，不会重新执行已有命令。", action: .diagnostics, actionLabel: "诊断连接"))
        } else if state == .connected && !observed {
            result.append(.init(id: "host", title: "隧道已就绪，网页调用尚未确认", detail: "在网页选择原有 MCP 插件，调用一次状态检查。", action: .access, actionLabel: "复制测试指令"))
        }
        // A newer successful call for the same target/tool supersedes that
        // failure. A check of another directory does not prove it recovered.
        let rows = activity.filter { !$0.isConnectionEvent }
        if let index = rows.firstIndex(where: { $0.status == "failed" }),
           !rows.prefix(index).contains(where: { $0.target == rows[index].target && $0.tool == rows[index].tool && $0.status == "returned" }) {
            let failure = rows[index]
            if failure.errorCode == "ACCESS_DENIED" {
                result.append(.init(id: "permission", title: "最近有本地访问被拒绝", detail: failure.target, action: .access, actionLabel: "检查目录权限"))
            } else if failure.errorCode == "COMMAND_TIMEOUT" {
                result.append(.init(id: "timeout", title: "最近有命令超时", detail: "先查看原命令的输出与退出状态，避免重复启动。", action: .workbench, actionLabel: "查看工作台"))
            }
        }
        return Array(result.prefix(3))
    }
}
