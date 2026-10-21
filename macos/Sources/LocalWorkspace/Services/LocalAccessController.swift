import AppKit
import Foundation
import Observation

private final class LocalAccessSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor @Observable
final class LocalAccessController {
    private(set) var path = UserDefaults.standard.string(forKey: "accessCheckDirectory") ?? ""
    private(set) var report: LocalAccessReport?
    private(set) var busy = false
    private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func select(_ path: String) {
        cancel()
        self.path = path
        report = nil
        message = nil
        UserDefaults.standard.set(path, forKey: "accessCheckDirectory")
    }
    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择要检查的本地项目"
        panel.message = "这里只选择检查位置。实际访问是否可用，由后端检查和 macOS 权限共同决定。"
        panel.prompt = "选择目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path) }
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let url = panel.url { self?.select(url.path) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func check(base: URL?, write: Bool) {
        guard !busy else { return }
        guard let base, WorkspaceLocalURL.isSafe(base), !path.isEmpty else {
            message = "请先选择目录，并连接本机服务或运行本地检查。"
            return
        }
        cancel()
        let expected = generation, selected = path
        busy = true; message = nil; report = nil
        task = Task {
            let session = URLSession(configuration: .ephemeral, delegate: LocalAccessSessionDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            do {
                var tokenRequest = URLRequest(url: base.appendingPathComponent("api/local-actions"))
                tokenRequest.timeoutInterval = 5
                let (tokenData, tokenResponse) = try await session.data(for: tokenRequest)
                guard (tokenResponse as? HTTPURLResponse)?.statusCode == 200, tokenData.count < 16384,
                      let token = (try JSONSerialization.jsonObject(with: tokenData) as? [String: Any])?["token"] as? String else {
                    throw WorkspaceError(message: "无法验证本机检查入口，请检查连接。")
                }
                var components = URLComponents(url: base.appendingPathComponent("api/check-access"), resolvingAgainstBaseURL: false)!
                components.queryItems = [.init(name: "path", value: selected), .init(name: "write", value: write ? "1" : "0")]
                var request = URLRequest(url: components.url!)
                request.httpMethod = "POST"; request.timeoutInterval = 15
                request.setValue(base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
                request.setValue(token, forHTTPHeaderField: "X-Workspace-Token")
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576 else {
                    throw WorkspaceError(message: (response as? HTTPURLResponse)?.statusCode == 404 ? "当前后端尚不支持目录检查，请运行新版应用。" : "目录检查未能返回，请检查连接。")
                }
                let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                let result = try decoder.decode(LocalAccessReport.self, from: data)
                guard !Task.isCancelled, generation == expected else { return }
                report = result; busy = false; task = nil
            } catch {
                guard !Task.isCancelled, generation == expected else { return }
                message = (error as? URLError)?.code == .timedOut
                    ? "检查尚未返回，可能正在等待 macOS 权限提示。请先处理系统提示，避免反复检查。"
                    : error.localizedDescription
                busy = false; task = nil
            }
        }
    }
    func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
        busy = false
    }
    func invalidate() {
        cancel()
        report = nil
        message = path.isEmpty ? nil : "连接已变化，请重新检查所选目录。"
    }
    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"), NSWorkspace.shared.open(url) else {
            message = "请打开系统设置 → 隐私与安全性 → 文件与文件夹。"
            return
        }
    }
    var testPrompt: String {
        "请使用 Local Workspace Mac 调用 get_workspace_status，报告实际版本、工具数量和默认 Shell。" + (path.isEmpty ? "" : "然后列出目录 \(String(reflecting: path)) 的前 20 项，不修改文件。")
    }
}
