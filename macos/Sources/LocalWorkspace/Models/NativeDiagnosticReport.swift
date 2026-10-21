import Foundation

struct NativeDiagnosticReport: Decodable {
    struct Check: Decodable {
        let label: String
        let status: String
        let detail: String
        var statusLabel: String { status == "pass" ? "通过" : status == "fail" ? "需处理" : status == "pending" ? "待验证" : "未检查" }
    }
    struct Version: Decodable {
        let id: String
        let label: String
        let running: String?
        let installed: String?
        let restartRequired: Bool
    }
    let checks: [Check]
    let versions: [Version]?
}
