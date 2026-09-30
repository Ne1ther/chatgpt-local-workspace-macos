import SwiftUI
import WebKit

struct DashboardView: NSViewRepresentable {
    let session: WorkspaceDashboardSession
    let url: URL
    let revision: UUID
    func makeNSView(context: Context) -> WKWebView {
        session.view(for: url, revision: revision)
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        session.update(url: url, revision: revision)
    }

    // Removing a tab must not discard the store-owned ephemeral browser session.
    static func dismantleNSView(_ view: WKWebView, coordinator: ()) { }
}
