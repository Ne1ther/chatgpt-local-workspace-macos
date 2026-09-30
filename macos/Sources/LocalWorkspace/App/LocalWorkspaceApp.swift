import SwiftUI
import AppKit

@main
struct LocalWorkspaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = WorkspaceStore()
    var body: some Scene {
        WindowGroup("Local Workspace", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 1000, minHeight: 660)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
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
        Settings { ConnectionSettings(store: store) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkspaceStore?
    private var terminationSignal: DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
