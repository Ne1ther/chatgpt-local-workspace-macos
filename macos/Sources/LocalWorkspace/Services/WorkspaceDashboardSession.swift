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
            let palette = WorkspacePalette.nsColor
            let colors: [String: NSColor] = [
                "--frame": .windowBackgroundColor, "--surface": .controlBackgroundColor,
                "--subtle": .underPageBackgroundColor, "--block": .textBackgroundColor, "--popover": .controlBackgroundColor,
                "--text": .labelColor, "--text-body": .labelColor, "--text-2": .secondaryLabelColor,
                "--text-3": .secondaryLabelColor, "--text-4": .tertiaryLabelColor, "--placeholder": .placeholderTextColor,
                "--hover": .unemphasizedSelectedContentBackgroundColor, "--selected": .unemphasizedSelectedContentBackgroundColor,
                "--rail-hover": .unemphasizedSelectedContentBackgroundColor, "--rail-selected": .selectedContentBackgroundColor,
                "--line": .separatorColor, "--line-soft": .separatorColor, "--line-strong": .separatorColor,
                "--ok": .systemGreen, "--warn": .systemOrange, "--danger": .systemRed, "--info": .systemBlue,
                "--background": .windowBackgroundColor, "--foreground": .labelColor,
                "--card": .controlBackgroundColor, "--card-foreground": .labelColor,
                "--muted": .controlBackgroundColor, "--muted-foreground": .secondaryLabelColor,
                "--secondary": .controlColor, "--secondary-foreground": .labelColor,
                "--accent": .unemphasizedSelectedContentBackgroundColor, "--accent-foreground": .labelColor,
                "--primary": .controlAccentColor, "--primary-foreground": .white,
                "--border": .separatorColor, "--input": .separatorColor, "--ring": .controlAccentColor,
                "--success": .systemGreen, "--warning": .systemOrange, "--destructive": .systemRed,
            ]
            let themed: [String: NSColor] = [
                "--frame": palette("sidebar"), "--surface": palette("surface"), "--subtle": palette("raised"),
                "--block": palette("page"), "--popover": palette("raised"), "--text": palette("text"),
                "--text-body": palette("text"), "--text-2": palette("secondary"), "--text-3": palette("secondary"),
                "--text-4": palette("secondary"), "--placeholder": palette("secondary"), "--hover": palette("raised"),
                "--selected": palette("selection"), "--rail-hover": palette("raised"), "--rail-selected": palette("selection"),
                "--line": palette("border"), "--line-soft": palette("border"), "--line-strong": palette("border"),
                "--ok": palette("teal"), "--warn": palette("orange"), "--danger": palette("danger"), "--info": palette("blue"),
                "--primary": palette("button"), "--primary-hover": palette("button"), "--background": palette("surface"),
                "--foreground": palette("text"), "--card": palette("raised"), "--card-foreground": palette("text"),
                "--muted": palette("raised"), "--muted-foreground": palette("secondary"), "--secondary": palette("raised"),
                "--secondary-foreground": palette("text"), "--accent": palette("selection"), "--accent-foreground": palette("text"),
                "--border": palette("border"), "--input": palette("border"), "--ring": palette("blue"),
                "--success": palette("teal"), "--warning": palette("orange"), "--destructive": palette("danger"),
                "--violet": palette("violet"), "--teal": palette("teal"), "--orange": palette("orange"), "--header": palette("raised"),
            ]
            for (key, color) in colors.merging(themed, uniquingKeysWith: { _, custom in custom }) {
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
