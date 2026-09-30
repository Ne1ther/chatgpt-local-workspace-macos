import AppKit
import SwiftUI

struct StatusMenuView: View {
    let store: WorkspaceStore
    let delegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Label(store.state.label, systemImage: statusSymbol)
            .disabled(true)
        Divider()
        Button("打开主窗口", systemImage: "macwindow") { showWindow() }
        Button("打开实时工作台", systemImage: "rectangle.3.group") {
            store.destination = .workbench
            showWindow()
        }
        if store.running || store.busy {
            Button("停止连接", systemImage: "stop.circle") { store.stop() }
        } else {
            Button("连接 ChatGPT", systemImage: "link") {
                if store.canConnect { store.connect() }
                else { showSettings() }
            }
        }
        Divider()
        Button("连接与显示…", systemImage: "slider.horizontal.3") { showSettings() }
        Button("退出 ChatGPT Codex Workspace", systemImage: "power") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusSymbol: String {
        switch store.state {
        case .connected: "checkmark.circle"
        case .starting, .reconnecting: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.circle"
        case .local: "checkmark.shield"
        case .stopped: "circle.dotted"
        }
    }

    private func showWindow() {
        delegate.showMainWindow()
    }

    private func showSettings() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}
