import AppKit
import Quartz

/// Borderless, non-activating floating panel: it takes keyboard focus without
/// pulling the previous app out of the foreground (so window snapping and paste target it).
final class CommandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false               // SwiftUI draws a softer, larger shadow
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none       // our own spring animation instead of AppKit's fade
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Never drawn (borderless), but VoiceOver announces it.
        title = "Glink"
        setAccessibilityLabel("Glink")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Quick Look (⌘Y) asks the responder chain for a controller.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = QuickLookController.shared
            panel.delegate = QuickLookController.shared
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { PanelController.shared.quickLookDidClose() }
    }
}
