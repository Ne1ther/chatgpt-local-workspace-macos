import AppKit
import SwiftUI

struct StatusMenuView: View {
    let store: WorkspaceStore
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Label(store.state.label, systemImage: store.state == .connected ? "checkmark.circle" : "circle.dotted")
            .disabled(true)
        Divider()
        Button("打开主窗口") { showWindow() }
        Button("打开实时工作台") {
            store.destination = .workbench
            showWindow()
        }
        if store.running || store.busy {
            Button("停止连接") { store.stop() }
        } else {
            Button("连接 ChatGPT") {
                if store.canConnect { store.connect() }
                else { openSettings(); NSApp.activate(ignoringOtherApps: true) }
            }
        }
        Divider()
        Button("连接设置…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("退出 Local Workspace") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
