import AppKit
import ApplicationServices

enum WindowCommand: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case maximize, almostMaximize, center
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight
    case nextDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .maximize: "Maximize"
        case .almostMaximize: "Almost Maximize"
        case .center: "Center"
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First Two Thirds"
        case .lastTwoThirds: "Last Two Thirds"
        case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"
        case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"
        case .nextDisplay: "Move to Next Display"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.inset.filled"
        case .rightHalf: "rectangle.righthalf.inset.filled"
        case .topHalf: "rectangle.tophalf.inset.filled"
        case .bottomHalf: "rectangle.bottomhalf.inset.filled"
        case .maximize: "rectangle.inset.filled"
        case .almostMaximize: "rectangle.center.inset.filled"
        case .center: "rectangle.center.inset.filled"
        case .firstThird: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .lastThird: "rectangle.trailingthird.inset.filled"
        case .firstTwoThirds: "rectangle.leadingtwothirds.inset.filled"
        case .lastTwoThirds: "rectangle.trailingtwothirds.inset.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .nextDisplay: "rectangle.on.rectangle"
        }
    }

    var keywords: String {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: "snap split half window"
        case .maximize, .almostMaximize: "fullscreen full zoom fill window"
        case .center: "middle window"
        case .nextDisplay: "monitor screen window"
        default: "snap window"
        }
    }

    /// Target frame in Cocoa coordinates (bottom-left origin) within a screen's visible frame.
    func frame(in v: CGRect, current: CGRect) -> CGRect {
        switch self {
        case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        case .rightHalf: return CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        case .topHalf: return CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        case .bottomHalf: return CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        case .maximize, .nextDisplay: return v
        case .almostMaximize: return v.insetBy(dx: v.width * 0.05, dy: v.height * 0.05)
        case .center:
            let w = min(current.width, v.width), h = min(current.height, v.height)
            return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h)
        case .firstThird: return CGRect(x: v.minX, y: v.minY, width: v.width / 3, height: v.height)
        case .centerThird: return CGRect(x: v.minX + v.width / 3, y: v.minY, width: v.width / 3, height: v.height)
        case .lastThird: return CGRect(x: v.minX + v.width * 2 / 3, y: v.minY, width: v.width / 3, height: v.height)
        case .firstTwoThirds: return CGRect(x: v.minX, y: v.minY, width: v.width * 2 / 3, height: v.height)
        case .lastTwoThirds: return CGRect(x: v.minX + v.width / 3, y: v.minY, width: v.width * 2 / 3, height: v.height)
        case .topLeft: return CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .topRight: return CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .bottomLeft: return CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .bottomRight: return CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
        }
    }
}

enum WindowManagerError: Error {
    case notTrusted, noWindow, notResizable

    var message: String {
        switch self {
        case .notTrusted: "Accessibility permission is needed to move windows."
        case .noWindow: "No window to move. Click a window first."
        case .notResizable: "This window can't be moved or resized."
        }
    }
}

/// Moves the frontmost app's focused window through the Accessibility API (AXUIElement).
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    func perform(_ command: WindowCommand, in app: NSRunningApplication?) -> Result<Void, WindowManagerError> {
        guard AXIsProcessTrusted() else { return .failure(.notTrusted) }
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return .failure(.noWindow) }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.5)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return .failure(.noWindow) }
        let window = windowRef as! AXUIElement

        guard let axFrame = frame(of: window) else { return .failure(.noWindow) }
        let current = Self.cocoaRect(fromAX: axFrame)
        let screens = NSScreen.screens
        let screen = screens.max { $0.frame.intersection(current).area < $1.frame.intersection(current).area } ?? NSScreen.main!

        var destinationScreen = screen
        if command == .nextDisplay, screens.count > 1, let i = screens.firstIndex(of: screen) {
            destinationScreen = screens[(i + 1) % screens.count]
        }
        let target = command.frame(in: destinationScreen.visibleFrame, current: current).integral

        SnapPreviewController.shared.preview(from: current, to: target, on: destinationScreen) { [weak self] in
            UndoCenter.shared.recordWindowMove(window: window, previousAXFrame: axFrame, appName: app.localizedName,
                                               command: command.title)
            self?.apply(target, to: window)
            Haptics.tick()
            Mascots.celebrate(.windowSnapped)
        }
        return .success(())
    }

    private func apply(_ cocoaFrame: CGRect, to window: AXUIElement) {
        let ax = Self.axRect(fromCocoa: cocoaFrame)
        var size = ax.size
        var origin = ax.origin
        // Size → position → size: some apps clamp size against the old position first.
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// AX uses a top-left origin anchored to the primary screen; Cocoa uses bottom-left.
    static func cocoaRect(fromAX r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func axRect(fromCocoa r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
