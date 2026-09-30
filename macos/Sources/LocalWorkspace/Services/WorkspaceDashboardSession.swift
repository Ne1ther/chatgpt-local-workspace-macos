import AppKit
import WebKit

/// One ephemeral browser session belongs to one backend connection, not one SwiftUI tab.
@MainActor
final class WorkspaceDashboardSession: NSObject, WKNavigationDelegate {
    private var retainedView: WKWebView?
    private(set) var loadedURL: URL?
    private var loadedRevision: UUID?
    private var pendingThread: String?

    func view(for url: URL, revision: UUID) -> WKWebView {
        if retainedView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = self
            view.allowsBackForwardNavigationGestures = false
            retainedView = view
        }
        update(url: url, revision: revision)
        return retainedView!
    }

    func update(url: URL, revision: UUID) {
        guard WorkspaceLocalURL.isSafe(url) else { return }
        guard loadedURL != url || loadedRevision != revision else { return }
        loadedURL = url
        loadedRevision = revision
        retainedView?.load(URLRequest(url: url))
    }

    func showActivity(_ entry: ActivityEntry) {
        pendingThread = entry.threadId
        if retainedView?.isLoading == false { applyPendingThread() }
    }

    private func applyPendingThread() {
        guard let view = retainedView, let thread = pendingThread,
              let json = try? JSONSerialization.data(withJSONObject: [thread]),
              let encoded = String(data: json, encoding: .utf8) else { return }
        pendingThread = nil
        view.evaluateJavaScript("location.hash = 'thread=' + encodeURIComponent(\(encoded)[0])")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyPendingThread()
    }

    func reset() {
        retainedView?.stopLoading()
        retainedView?.navigationDelegate = nil
        retainedView?.removeFromSuperview()
        retainedView = nil
        loadedURL = nil
        loadedRevision = nil
        pendingThread = nil
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
