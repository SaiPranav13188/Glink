import AppKit
import Observation
import SwiftUI

/// Shows where a window is about to go: a glassy outline glides from the window's current
/// frame to its target, the window moves, then the outline fades.
@MainActor
final class SnapPreviewController {
    static let shared = SnapPreviewController()

    private var window: NSWindow?
    private let model = SnapPreviewModel()

    func preview(from source: CGRect, to target: CGRect, on screen: NSScreen, completion: @escaping @MainActor () -> Void) {
        if Motion.isOff {
            completion()
            return
        }
        let overlay = window ?? makeWindow()
        window = overlay
        let bounds = screen.frame
        overlay.setFrame(bounds, display: false)

        // Convert to the overlay's local, top-left SwiftUI space.
        func local(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX - bounds.minX, y: bounds.maxY - r.maxY, width: r.width, height: r.height)
        }
        model.frame = local(source.intersection(bounds).isNull ? target : source).insetBy(dx: 4, dy: 4)
        model.opacity = 0
        overlay.orderFrontRegardless()

        let insetTarget = local(target).insetBy(dx: 6, dy: 6)
        DispatchQueue.main.async { [model] in
            Motion.animate(Motion.smooth) {
                model.frame = insetTarget
                model.opacity = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.isReduced ? 0.1 : 0.24)) { [weak self, model] in
            completion()
            Motion.animate(Motion.gentle) { model.opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if model.opacity == 0 { self?.window?.orderOut(nil) }
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        w.contentView = NSHostingView(rootView: SnapPreviewView(model: model))
        return w
    }
}

@MainActor @Observable
final class SnapPreviewModel {
    var frame: CGRect = .zero
    var opacity: Double = 0
}

private struct SnapPreviewView: View {
    let model: SnapPreviewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
                .background(VisualEffectBlur(material: .hudWindow).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
                .frame(width: max(0, model.frame.width), height: max(0, model.frame.height))
                .offset(x: model.frame.minX, y: model.frame.minY)
                .opacity(model.opacity)
        }
        .ignoresSafeArea()
    }
}
