import SwiftUI
import WebKit

struct DashboardView: NSViewRepresentable {
    let url: URL
    let revision: UUID
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url || context.coordinator.revision != revision {
            context.coordinator.loadedURL = url; context.coordinator.revision = revision
            view.load(URLRequest(url: url))
        }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var revision: UUID?
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else { decisionHandler(.cancel); return }
            if target.scheme == "http", target.host == "127.0.0.1", target.port == loadedURL?.port {
                decisionHandler(.allow)
            } else {
                if navigationAction.navigationType == .linkActivated && ["https", "http"].contains(target.scheme ?? "") { NSWorkspace.shared.open(target) }
                decisionHandler(.cancel)
            }
        }
    }
}
