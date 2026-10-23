import AppKit
import ApplicationServices
import Observation

/// Tracks the Accessibility permission (needed for window snapping, pasting and snippets).
@MainActor @Observable
final class PermissionsManager {
    static let shared = PermissionsManager()

    private(set) var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var observers = 0

    private init() {}

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isAccessibilityTrusted {
            isAccessibilityTrusted = trusted
            if trusted { NotificationCenter.default.post(name: .accessibilityGranted, object: nil) }
        }
    }

    /// Shows the system prompt, then opens the Accessibility pane so the user can flip the switch.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
        beginPolling()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Polls once a second while some UI is waiting for the permission to flip.
    func beginPolling() {
        observers += 1
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { PermissionsManager.shared.refresh() }
        }
    }

    func endPolling() {
        observers = max(0, observers - 1)
        if observers == 0 {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}

extension Notification.Name {
    static let accessibilityGranted = Notification.Name("GlinkAccessibilityGranted")
    static let panelDidOpen = Notification.Name("GlinkPanelDidOpen")
}
