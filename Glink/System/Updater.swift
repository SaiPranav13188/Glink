import AppKit
import Observation
import Sparkle

/// Sparkle auto-updates. Glink is a menu bar app, so scheduled checks use Sparkle's
/// "gentle reminders": a found update shows a HUD and a menu item instead of stealing focus.
@MainActor @Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// Set when a scheduled check found an update the user hasn't looked at yet.
    private(set) var pendingUpdateVersion: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController!

    /// Only installed copies update themselves. Development builds (Xcode, build/, DerivedData)
    /// skip Sparkle's startup checks, which would otherwise probe the bundle for writability.
    static var isInstalled: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: Self.isInstalled, updaterDelegate: nil, userDriverDelegate: self)
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        NSApp.activate()
        if !Self.isInstalled {
            let alert = NSAlert()
            alert.messageText = "Move Glink to Applications to get updates"
            alert.informativeText = "Updates are installed in place, so Glink checks for them only when it runs from your Applications folder."
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate (gentle reminders)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                         andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Only interrupt if the user is already looking at Glink.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            if !handleShowingUpdate && !state.userInitiated {
                pendingUpdateVersion = version
                HUDController.shared.show("Glink \(version) is available", symbol: "arrow.down.circle.fill")
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { pendingUpdateVersion = nil }
    }
}
