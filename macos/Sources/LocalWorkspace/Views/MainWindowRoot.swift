import SwiftUI

struct MainWindowRoot: View {
    let store: WorkspaceStore
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(store: store)
            .frame(minWidth: 1000, minHeight: 660)
            .onAppear {
                delegate.store = store
                delegate.reopenMainWindow = { openWindow(id: "main") }
            }
    }
}
