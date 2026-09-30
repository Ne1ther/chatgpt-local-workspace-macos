import SwiftUI
import AppKit
import OSLog

@main
struct LocalWorkspaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = WorkspaceStore()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var bootstrapped = false
    var body: some Scene {
        mainWindow
            .onChange(of: scenePhase, initial: true) {
                // The app/scene environment exists even when the previous
                // session ended with its main window closed. Register reopening
                // before relying on a window's content appearing.
                delegate.store = store
                delegate.reopenMainWindow = { openWindow(id: "main") }
                guard !bootstrapped else { return }
                bootstrapped = true
                delegate.showMainWindow()
            }
        MenuBarExtra(isInserted: $store.showMenuBarIcon) {
            StatusMenuView(store: store, delegate: delegate)
        } label: {
            Image(nsImage: WorkspaceBrand.menuBarImage)
                .accessibilityLabel("ChatGPT Codex Workspace")
        }
        .menuBarExtraStyle(.menu)
        Settings { ConnectionSettings(store: store) }
    }

    private var mainWindow: some Scene {
        Window("ChatGPT Codex Workspace", id: "main") {
            MainWindowRoot(store: store, delegate: delegate)
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开主窗口") { delegate.showMainWindow() }
                    .keyboardShortcut("n")
            }
            CommandMenu("工作区") {
                ForEach(Array(Destination.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.rawValue) { store.destination = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Divider()
                Button("刷新工作台") { store.refreshDashboard() }.keyboardShortcut("r")
                    .disabled(store.dashboardURL == nil)
                Button("在浏览器中打开") { store.openBrowser() }.disabled(store.dashboardURL == nil)
                Button("诊断连接") { store.showDiagnostics() }
                Divider()
                Button("停止连接") { store.stop() }.disabled(!store.running)
            }
            CommandGroup(replacing: .help) {
                Link("连接指南", destination: store.supportURL)
                Link("原版开源项目", destination: URL(string: "https://github.com/CSL19980820/chatgpt-local-workspace")!)
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkspaceStore?
    var reopenMainWindow: (() -> Void)?
    let presenceController = AppPresenceController()
    private var terminationSignal: DispatchSourceSignal?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "community.localworkspace.mac", category: "Windowing")
    func applicationWillFinishLaunching(_ notification: Notification) {
        presenceController.start()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        presenceController.start()
        NSApp.activate(ignoringOtherApps: true)
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.store?.stop()
            NSApp.terminate(nil)
        }
        source.resume()
        terminationSignal = source
    }
    func applicationWillTerminate(_ notification: Notification) { store?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // A cold launch can restore no main window, so MainWindowRoot.onAppear
        // has not supplied an openWindow action yet. Let SwiftUI handle that
        // first reopen rather than swallowing it with a no-op callback.
        guard reopenMainWindow != nil else {
            presenceController.reconcileAfterSceneChange()
            return true
        }
        showMainWindow()
        return false
    }
    func showMainWindow() {
        logger.info("Show main window: actionReady=\(self.reopenMainWindow != nil, privacy: .public), windows=\(NSApp.windows.count, privacy: .public)")
        reopenMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
        presenceController.reconcileAfterSceneChange()
    }
}
