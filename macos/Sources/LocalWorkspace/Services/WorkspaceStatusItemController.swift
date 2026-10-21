import AppKit
import Observation
import SwiftUI

/// A narrow AppKit bridge: SwiftUI owns content and state; the native status
/// button owns the live compositor layer that MenuBarExtra labels snapshot.
@MainActor final class WorkspaceStatusItemController: NSObject, NSPopoverDelegate {
    private let store: WorkspaceStore
    private weak var delegate: AppDelegate?
    private var item: NSStatusItem?
    private var signalView: MenuBarSignalView?
    private let popover = NSPopover()
    private var motionObserver: NSObjectProtocol?

    init(store: WorkspaceStore, delegate: AppDelegate) {
        self.store = store; self.delegate = delegate
        super.init()
        popover.behavior = .transient; popover.delegate = self
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observe()
    }
    private func observe() {
        withObservationTracking {
            _ = store.showMenuBarIcon; _ = store.activeWorkCount; _ = store.snapshotStale; _ = store.state
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
    private func refresh() {
        guard store.showMenuBarIcon else {
            signalView?.stop(); popover.close()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil; signalView = nil
            return
        }
        if item == nil {
            let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item = created
            if let button = created.button {
                button.target = self; button.action = #selector(togglePopover)
                button.toolTip = "ChatGPT Codex Workspace"
                let signal = MenuBarSignalView(); signal.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(signal)
                NSLayoutConstraint.activate([signal.widthAnchor.constraint(equalToConstant: WorkspaceBrand.menuBarSize), signal.heightAnchor.constraint(equalToConstant: WorkspaceBrand.menuBarSize), signal.centerXAnchor.constraint(equalTo: button.centerXAnchor), signal.centerYAnchor.constraint(equalTo: button.centerYAnchor)])
                signalView = signal
            }
        }
        let attention = store.state == .failed || store.state == .reconnecting || (store.running && store.snapshotStale)
        signalView?.update(running: store.running && store.activeWorkCount > 0, attention: attention, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        item?.button?.setAccessibilityLabel("ChatGPT Codex Workspace，\(store.state.label)，\(store.activeWorkCount) 项执行中")
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.close(); return }
        guard let button = item?.button, let delegate else { return }
        let host = NSHostingController(rootView: StatusMenuView(store: store, delegate: delegate))
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }
    deinit { if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) } }
}
