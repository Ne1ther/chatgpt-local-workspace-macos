import AppKit
import OSLog

/// Keeps the user's Dock choice authoritative when SwiftUI presents or closes
/// a scene. SwiftUI window presentation can promote an accessory app to regular.
@MainActor
final class AppPresenceController: NSObject {
    static let dockPreferenceDidChange = Notification.Name("WorkspaceDockPreferenceDidChange")
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "community.localworkspace.mac", category: "AppPresence")

    private var observing = false
    private var reconciliationQueued = false
    private let runningApplication = NSRunningApplication.current
    private var activationPolicyObservation: NSKeyValueObservation?

    func start() {
        guard !observing else { return }
        observing = true
        // Window scenes can change the activation policy without presenting a
        // key window (for example while restoring a previously closed scene).
        // Observe the real process policy instead of assuming window events
        // cover every promotion. AppKit delivers these changes on its run loop.
        activationPolicyObservation = runningApplication.observe(\.activationPolicy, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let actualPolicy = self.runningApplication.activationPolicy
                let desired = Self.desiredDockPolicy
                guard actualPolicy != desired else { return }
                // NSApp's local policy can already equal the preference while
                // LaunchServices still reports a different actual process
                // policy. Correct only a real undesired KVO state, not every
                // window event, to avoid redundant policy toggling.
                Self.applyDockPreference(actualPolicy: actualPolicy)
                self.reconcileAfterSceneChange()
            }
        }
        let center = NotificationCenter.default
        for name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.willCloseNotification,
            NSWindow.didDeminiaturizeNotification,
            NSApplication.didBecomeActiveNotification,
            NSApplication.didUnhideNotification,
            Self.dockPreferenceDidChange
        ] {
            center.addObserver(self, selector: #selector(presenceDidChange), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        reconcileAfterSceneChange()
    }

    /// There is no timer: the second check runs after the current AppKit/SwiftUI
    /// window transaction, including close and reopen, has finished.
    func reconcileAfterSceneChange() {
        Self.applyDockPreference()
        guard !reconciliationQueued else { return }
        reconciliationQueued = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reconciliationQueued = false
                Self.applyDockPreference()
            }
        }
    }

    private static var desiredDockPolicy: NSApplication.ActivationPolicy {
        let showDock = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        return showDock ? .regular : .accessory
    }

    static func applyDockPreference(actualPolicy: NSApplication.ActivationPolicy? = nil) {
        let desired = desiredDockPolicy
        let localPolicy = NSApp.activationPolicy()
        guard localPolicy != desired || (actualPolicy != nil && actualPolicy != desired) else { return }
        let succeeded = NSApp.setActivationPolicy(desired)
        logger.info("Dock policy correction: local=\(localPolicy.rawValue, privacy: .public), actual=\(actualPolicy?.rawValue ?? -1, privacy: .public), desired=\(desired.rawValue, privacy: .public), accepted=\(succeeded, privacy: .public)")
    }

    @objc private func presenceDidChange(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification {
            Self.logger.info("Window closing; keeping application and connection running")
        }
        reconcileAfterSceneChange()
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
        reconcileAfterSceneChange()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
