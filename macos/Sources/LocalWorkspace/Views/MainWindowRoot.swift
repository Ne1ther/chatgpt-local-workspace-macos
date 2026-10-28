import SwiftUI

struct MainWindowRoot: View {
    let store: WorkspaceStore
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(store: store)
            .frame(minWidth: 1000, minHeight: 660)
            .background(WindowChromeBridge())
            .onAppear {
                delegate.store = store
                delegate.reopenMainWindow = { openWindow(id: "main") }
                delegate.presenceController.reconcileAfterSceneChange()
            }
    }
}

private struct WindowChromeBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowChromeView() }
    func updateNSView(_ view: NSView, context: Context) {
        view.window?.titlebarSeparatorStyle = .none
        view.window?.backgroundColor = WorkspacePalette.nsColor("page")
    }
}

private final class WindowChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.titlebarSeparatorStyle = .none
        window?.backgroundColor = WorkspacePalette.nsColor("page")
    }
}
