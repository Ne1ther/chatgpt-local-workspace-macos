import AppKit
import WebKit

/// One ephemeral browser session belongs to one backend connection, not one SwiftUI tab.
@MainActor
final class WorkspaceDashboardSession: NSObject, WKNavigationDelegate {
    private var retainedView: WKWebView?
    private(set) var loadedURL: URL?
    private var loadedRevision: UUID?
    private var pendingThread: String?
    private var currentThread = ""
    private var pendingSetup = false
    private var visible = false
    private var appliedTheme: String?
    var onThreadChange: ((String) -> Void)?

    func view(for url: URL, revision: UUID) -> WKWebView {
        if retainedView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.add(WorkspaceNavigationHandler(session: self), name: "workspaceNavigation")
            configuration.userContentController.addUserScript(WKUserScript(source: Self.themeScript(for: NSApp.effectiveAppearance), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            let view = NativeWorkspaceWebView(frame: .zero, configuration: configuration)
            view.appearanceDidChange = { [weak self] in self?.applySystemColors() }
            view.navigationDelegate = self
            view.allowsBackForwardNavigationGestures = false
            retainedView = view
        }
        update(url: url, revision: revision)
        return retainedView!
    }

    func update(url: URL, revision: UUID) {
        applySystemColors()
        guard WorkspaceLocalURL.isSafe(url) else { return }
        guard loadedURL != url || loadedRevision != revision else { return }
        loadedURL = url
        loadedRevision = revision
        appliedTheme = nil
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "native", value: "1")]
        if !currentThread.isEmpty {
            var filter = URLComponents()
            filter.queryItems = [URLQueryItem(name: "thread", value: currentThread)]
            components.percentEncodedFragment = filter.percentEncodedQuery
        }
        pendingThread = nil
        retainedView?.load(URLRequest(url: components.url!))
    }

    func showActivity(_ entry: ActivityEntry) {
        selectThread(entry.threadId)
    }

    func selectThread(_ thread: String) {
        currentThread = thread
        pendingThread = thread
        if retainedView?.isLoading == false { applyPendingThread() }
    }

    func showSetup() {
        pendingSetup = true
        if retainedView?.isLoading == false { applyPendingSetup() }
    }

    func setVisible(_ value: Bool) {
        visible = value
        retainedView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('workspace-visibility', {detail: \(value)}))")
    }

    func sendCommand(_ action: String) {
        retainedView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('workspace-command', {detail: {action: '\(action)'}}))")
    }

    private func applyPendingSetup() {
        guard pendingSetup, let view = retainedView else { return }
        pendingSetup = false
        view.evaluateJavaScript("window.dispatchEvent(new Event('workspace-setup'))")
    }

    private func applyPendingThread() {
        guard let view = retainedView, let thread = pendingThread,
              let json = try? JSONSerialization.data(withJSONObject: [thread]),
              let encoded = String(data: json, encoding: .utf8) else { return }
        pendingThread = nil
        view.evaluateJavaScript("location.hash = 'thread=' + encodeURIComponent(\(encoded)[0])")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        appliedTheme = nil
        applySystemColors()
        setVisible(visible)
        applyPendingThread()
        applyPendingSetup()
    }

    func reset() {
        retainedView?.stopLoading()
        retainedView?.navigationDelegate = nil
        retainedView?.configuration.userContentController.removeScriptMessageHandler(forName: "workspaceNavigation")
        retainedView?.removeFromSuperview()
        retainedView = nil
        loadedURL = nil
        loadedRevision = nil
        pendingThread = nil
        currentThread = ""
        pendingSetup = false
        appliedTheme = nil
    }

    private func applySystemColors() {
        guard let view = retainedView else { return }
        let script = Self.themeScript(for: view.effectiveAppearance)
        guard script != appliedTheme else { return }
        appliedTheme = script
        view.evaluateJavaScript(script)
    }

    private static func themeScript(for appearance: NSAppearance) -> String {
        var tokens: [String: String] = [:]
        appearance.performAsCurrentDrawingAppearance {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let palette = WorkspacePalette.nsColor
            let srgb = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in
                NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
            }
            let frameColor = isDark ? srgb(20, 22, 26, 1) : srgb(238, 240, 244, 1)
            let headerColor = isDark ? srgb(33, 36, 43, 1) : srgb(246, 247, 249, 1)
            let surfaceColor = isDark ? srgb(27, 29, 34, 1) : srgb(255, 255, 255, 1)
            let subtleColor = isDark ? srgb(36, 40, 48, 1) : srgb(243, 244, 247, 1)
            let blockColor = isDark ? srgb(23, 25, 30, 1) : srgb(247, 248, 250, 1)
            let textPrimary = isDark ? srgb(242, 244, 248, 1) : srgb(20, 23, 31, 1)
            let textSecondary = isDark ? srgb(201, 208, 220, 1) : srgb(51, 57, 71, 1)
            let textTertiary = isDark ? srgb(157, 167, 184, 1) : srgb(82, 91, 110, 1)
            let textQuaternary = isDark ? srgb(127, 138, 156, 1) : srgb(104, 114, 133, 1)
            let placeholderColor = isDark ? srgb(109, 119, 136, 1) : srgb(123, 132, 150, 1)
            let chipColor = isDark ? srgb(42, 47, 58, 1) : srgb(235, 237, 242, 1)
            let diffAdd = isDark ? srgb(24, 50, 37, 1) : srgb(230, 246, 236, 1)
            let diffDel = isDark ? srgb(56, 30, 33, 1) : srgb(252, 235, 233, 1)
            let diffAddNo = isDark ? srgb(31, 68, 49, 1) : srgb(201, 235, 214, 1)
            let diffDelNo = isDark ? srgb(76, 38, 42, 1) : srgb(247, 211, 208, 1)
            let lineSoft = isDark ? srgb(45, 50, 60, 1) : srgb(226, 229, 236, 1)
            let lineColor = isDark ? srgb(56, 62, 74, 1) : srgb(213, 218, 227, 1)
            let lineStrong = isDark ? srgb(74, 82, 98, 1) : srgb(191, 198, 210, 1)

            let themed: [String: NSColor] = [
                "--frame": frameColor, "--header": headerColor, "--surface": surfaceColor,
                "--subtle": subtleColor, "--block": blockColor, "--popover": subtleColor,
                "--text": textPrimary, "--text-body": textPrimary,
                "--text-2": textSecondary, "--text-3": textTertiary,
                "--text-4": textQuaternary, "--placeholder": placeholderColor,
                "--hover": subtleColor, "--selected": palette("selection"),
                "--rail-hover": subtleColor, "--rail-selected": palette("selection"),
                "--line": lineColor, "--line-soft": lineSoft, "--line-strong": lineStrong,
                "--ok": palette("teal"), "--warn": palette("orange"), "--danger": palette("danger"), "--info": palette("blue"),
                "--primary": palette("button"), "--primary-hover": palette("button"), "--primary-foreground": .white,
                "--background": surfaceColor, "--foreground": textPrimary,
                "--card": subtleColor, "--card-foreground": textPrimary,
                "--muted": subtleColor, "--muted-foreground": textSecondary,
                "--secondary": subtleColor, "--secondary-foreground": textPrimary,
                "--accent": palette("selection"), "--accent-foreground": textPrimary,
                "--border": lineColor, "--input": lineColor, "--ring": palette("blue"),
                "--success": palette("teal"), "--warning": palette("orange"), "--destructive": palette("danger"),
                "--violet": palette("violet"), "--teal": palette("teal"), "--orange": palette("orange"),
                "--chip": chipColor,
                "--diff-add": diffAdd, "--diff-del": diffDel,
                "--diff-add-no": diffAddNo, "--diff-del-no": diffDelNo,
            ]
            for (key, color) in themed {
                guard let rgb = color.usingColorSpace(.sRGB) else { continue }
                let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent].map { max(0, min(255, Int(($0 * 255).rounded()))) }
                tokens[key] = String(format: "#%02x%02x%02x%02x", components[0], components[1], components[2], components[3])
            }
        }
        let data = try! JSONSerialization.data(withJSONObject: tokens, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        return "{ const colors = \(json); for (const el of [document.documentElement, document.getElementById('shell')]) { if (el) for (const [key, value] of Object.entries(colors)) el.style.setProperty(key, value); } }"
    }

    fileprivate func receiveNavigation(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, WorkspaceLocalURL.isSafe(url), url.port == loadedURL?.port,
              let thread = message.body as? String, thread.count <= 128 else { return }
        currentThread = thread
        onThreadChange?(thread)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = navigationAction.request.url else { decisionHandler(.cancel); return }
        if WorkspaceLocalURL.isSafe(target), target.port == loadedURL?.port {
            decisionHandler(.allow)
        } else {
            if navigationAction.navigationType == .linkActivated,
               ["https", "http"].contains(target.scheme ?? ""), target.user == nil, target.password == nil {
                NSWorkspace.shared.open(target)
            }
            decisionHandler(.cancel)
        }
    }
}

@MainActor private final class NativeWorkspaceWebView: WKWebView {
    var appearanceDidChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

@MainActor private final class WorkspaceNavigationHandler: NSObject, WKScriptMessageHandler {
    weak var session: WorkspaceDashboardSession?
    init(session: WorkspaceDashboardSession) { self.session = session }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        session?.receiveNavigation(message)
    }
}

enum WorkspaceLocalURL {
    static func isSafe(_ url: URL) -> Bool {
        guard let port = url.port else { return false }
        return url.scheme == "http" && url.host == "127.0.0.1" && (1...65_535).contains(port) && url.user == nil && url.password == nil
    }

    static func healthURL(from data: Data) -> URL? {
        let value: String?
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            value = (object["healthUrl"] ?? object["health_url"] ?? object["url"]) as? String
        } else {
            value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let value, let url = URL(string: value), isSafe(url), url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}
