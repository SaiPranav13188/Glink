import AppKit
import SwiftUI

/// Shows and hides the command panel. The panel is built once at launch and kept hidden,
/// so the hotkey only has to order it front — no view construction on the hot path.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    let viewModel = PanelViewModel()
    private(set) var panel: CommandPanel!
    /// The app that was frontmost when the panel opened (target for paste / window snapping).
    var previousApp: NSRunningApplication?
    private(set) var isVisible = false
    private var hiddenAt: Date?
    private var keyMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?

    /// After this long hidden, the panel reopens fresh at root search.
    static let resetAfter: TimeInterval = 30

    var windowSize: NSSize {
        NSSize(width: Theme.Panel.width + Theme.Panel.windowMargin * 2,
               height: Theme.Panel.maxHeight + Theme.Panel.windowMargin * 2)
    }

    func setUp() {
        let panel = CommandPanel(contentRect: NSRect(origin: .zero, size: windowSize))
        let host = NSHostingView(rootView: PanelRootView(model: viewModel))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: windowSize)
        host.autoresizingMask = [.width, .height]
        host.setAccessibilityLabel("Glink command panel")
        host.wantsLayer = true
        panel.contentView = host
        panel.delegate = self
        self.panel = panel
        warmUp()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isVisible, event.window === self.panel else { return false }
                // Don't steal Return/arrows from an input method that's composing (CJK, accents).
                if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
                return self.viewModel.handleKey(event)
            }
            return consumed ? nil : event
        }
    }

    /// Renders the panel once, invisibly, at launch so the first real open doesn't pay for
    /// shader compilation, font loading and the first layout pass.
    private func warmUp() {
        viewModel.prepareForOpen(resetState: false)
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show(route: Route? = nil) {
        hideWorkItem?.cancel()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        let reset = hiddenAt.map { Date().timeIntervalSince($0) > Self.resetAfter } ?? false

        // Order the panel in first (its content is still at opacity 0), then update state:
        // SwiftUI can skip updates made while the hosting window is off screen.
        panel.appearance = AppSettings.shared.theme.appearance
        position()
        panel.alphaValue = 1
        if !isVisible { panel.orderFrontRegardless() }
        panel.makeKey()
        isVisible = true

        viewModel.prepareForOpen(resetState: reset || route != nil)
        if let route { viewModel.push(route) }

        viewModel.isPresented = true
        animateEntrance()
        NotificationCenter.default.post(name: .panelDidOpen, object: nil)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        hiddenAt = Date()
        viewModel.closeActionsIfNeeded()
        viewModel.isPresented = false
        animateExit()

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
            // If Glink became active (Quick Look, an alert), hand focus back to where the user was.
            if NSApp.isActive, !NSApp.windows.contains(where: { $0.isVisible && $0 !== self.panel && $0.level == .normal }) {
                self.previousApp?.activate()
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.isOff ? 0 : Motion.panelOutDuration), execute: work)
    }

    // MARK: Entrance / exit (Core Animation)

    /// Transform that scales about the panel's center and shifts it vertically (layer space is y-up).
    private func panelTransform(scale: CGFloat, dropY: CGFloat) -> CATransform3D {
        let size = windowSize
        // The visible panel sits at the top of the window, below the margin.
        let panelHeight = min(Theme.Panel.maxHeight, max(Theme.Panel.minHeight, lastPanelHeight))
        let center = CGPoint(x: size.width / 2, y: size.height - Theme.Panel.windowMargin - panelHeight / 2)
        var t = CATransform3DMakeTranslation(center.x, center.y + dropY, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return CATransform3DTranslate(t, -center.x, -center.y, 0)
    }

    /// Approximate height of the visible panel, used as the scale origin.
    var lastPanelHeight: CGFloat = Theme.Panel.maxHeight

    /// Scale 0.96 → 1, 6pt drop, fade in — a spring with the same feel as Motion.panelIn.
    private func animateEntrance() {
        guard let layer = panel.contentView?.layer else { return }
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        CATransaction.commit()
        guard !Motion.isOff else { return }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = Motion.isReduced ? 0.1 : 0.16
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fade")
        guard !Motion.isReduced else { return }

        // response 0.28, damping 0.82 ≈ perceptual duration 0.28, bounce 0.18
        let spring = CASpringAnimation(perceptualDuration: 0.28, bounce: 0.18)
        spring.keyPath = "transform"
        spring.fromValue = NSValue(caTransform3D: panelTransform(scale: 0.96, dropY: 6))
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "entrance")
    }

    /// Scale → 0.98 and fade out, fast (120 ms).
    private func animateExit() {
        guard let layer = panel.contentView?.layer, !Motion.isOff else { return }
        let end = Motion.isReduced ? CATransform3DIdentity : panelTransform(scale: 0.98, dropY: 0)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Motion.panelOutDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? CATransform3DIdentity)
        scale.toValue = NSValue(caTransform3D: end)
        for a in [fade, scale] {
            a.duration = Motion.panelOutDuration
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            a.timingFunction = CAMediaTimingFunction(name: .easeIn)
        }
        layer.add(fade, forKey: "fade")
        layer.add(scale, forKey: "entrance")
        CATransaction.commit()
    }

    /// Centered horizontally, ~20% from the top of the screen under the mouse (multi-monitor aware).
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = windowSize
        let panelTop: CGFloat
        switch AppSettings.shared.panelPosition {
        case .upper: panelTop = visible.maxY - visible.height * 0.2
        case .center: panelTop = visible.midY + Theme.Panel.maxHeight / 2
        }
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: panelTop + Theme.Panel.windowMargin - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere closes the panel — unless Quick Look took focus on our behalf.
        guard isVisible, !QuickLookController.shared.isVisible else { return }
        hide()
    }

    func quickLookDidClose() {
        guard isVisible else { return }
        panel.makeKey()
    }
}

extension PanelViewModel {
    func closeActionsIfNeeded() {
        if actionsPresented { closeActions() }
    }
}

