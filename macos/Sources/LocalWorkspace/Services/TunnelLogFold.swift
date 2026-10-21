import Foundation

/// Exact INFO-event allowlist from upstream 2.4.1. Warning/error and unknown
/// informational messages remain visible. No timer or regular-expression loop.
struct TunnelLogFold {
    private static let noisy: Set<String> = [
        "provided", "replaced", "decorated", "supplied", "invoking", "run",
        "OnStart hook executing", "OnStart hook executed", "OnStop hook executing",
        "OnStop hook executed", "initialized custom fxevent.Logger", "started"
    ]
    private var count = 0
    private var last = Date()
    mutating func ingest(_ line: String, object: [String: Any]?) -> (folded: Bool, summary: String?) {
        let folded = !line.contains("[Workspace]") && (object?["level"] as? String)?.uppercased() == "INFO" && Self.noisy.contains(object?["msg"] as? String ?? "")
        if folded { count += 1 }
        if count > 0 && (!folded || Date().timeIntervalSince(last) >= 10) {
            let summary = "[Tunnel] 已折叠 \(count) 条重复信息日志。"
            count = 0; last = Date()
            return (folded, summary)
        }
        return (folded, nil)
    }
}
