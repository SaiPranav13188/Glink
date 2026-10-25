import AppKit
import Observation
import SwiftUI

/// A small floating confirmation ("Copied to Clipboard") shown after the panel closes.
@MainActor
final class HUDController {
    static let shared = HUDController()

    private var window: NSPanel?
    private let model = HUDModel()
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        let panel = window ?? makeWindow()
        window = panel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let size = NSSize(width: 420, height: 160)
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 60,
                              width: size.width, height: size.height), display: false)
        panel.appearance = AppSettings.shared.theme.appearance
        model.message = message
        model.symbol = symbol
        model.visible = false
        model.bounce += 1
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [model] in
            Motion.animate(Motion.bouncy) { model.visible = true }
        }
        hideTask?.cancel()
        hideTask = Task { [weak self, model] in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            Motion.animate(Motion.smooth) { model.visible = false }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.window?.orderOut(nil)
        }
    }

    private func makeWindow() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.contentView = NSHostingView(rootView: HUDView(model: model))
        return p
    }
}

@MainActor @Observable
final class HUDModel {
    var message = ""
    var symbol = "checkmark.circle.fill"
    var visible = false
    var bounce = 0
}

private struct HUDView: View {
    let model: HUDModel

    var body: some View {
        ZStack(alignment: .bottom) {
            MascotStage().frame(height: 120).padding(.bottom, 50)
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: model.symbol).accessibilityHidden(true)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.symbol.contains("exclamation") ? Color.orange : Color.green)
                    .symbolEffect(.bounce, value: model.bounce)
                Text(model.message)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(PanelBackground(cornerRadius: 19))
            .overlay(GlassEdge(cornerRadius: 19))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .scaleEffect(model.visible ? 1 : 0.9)
            .offset(y: model.visible ? 0 : 14)
            .opacity(model.visible ? 1 : 0)
            .padding(.bottom, 24)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
