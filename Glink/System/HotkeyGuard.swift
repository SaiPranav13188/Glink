import AppKit
import ApplicationServices
import KeyboardShortcuts

/// Makes the "Open Glink" shortcut win even when another app registered the same keys
/// (Claude's Quick Entry and others default to ⌥Space). Carbon hotkeys don't conflict
/// with an error: the system silently delivers the keys to someone else. With Accessibility
/// granted, an active session event tap catches the shortcut first and swallows it, so
/// it can't reach the other app. Without Accessibility, the Carbon hotkey is all there is.
@MainActor
final class HotkeyGuard {
    static let shared = HotkeyGuard()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyCode: Int64 = -1
    private var flags: CGEventFlags = []
    private var swallowKeyUp = false
    private var lastToggle = Date.distantPast
    private(set) var isRunning = false

    private static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    func startIfPossible() {
        guard AXIsProcessTrusted(), tap == nil else { return }
        reloadShortcut()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            let swallow = MainActor.assumeIsolated { HotkeyGuard.shared.handle(type: type, event: event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback, userInfo: nil) else {
            Log.system.error("Couldn't create event tap for the Glink shortcut")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HotkeyGuard.shared.reloadShortcut() }
        }
    }

    /// Both the tap and the Carbon hotkey can fire for one press; only the first counts.
    func toggleFromHotkey() {
        guard Date().timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = Date()
        PanelController.shared.toggle()
    }

    private func reloadShortcut() {
        guard let s = KeyboardShortcuts.getShortcut(for: .togglePanel) else { keyCode = -1; return }
        keyCode = Int64(s.carbonKeyCode)
        var f: CGEventFlags = []
        if s.modifiers.contains(.command) { f.insert(.maskCommand) }
        if s.modifiers.contains(.option) { f.insert(.maskAlternate) }
        if s.modifiers.contains(.control) { f.insert(.maskControl) }
        if s.modifiers.contains(.shift) { f.insert(.maskShift) }
        flags = f
    }

    /// Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown, .keyUp:
            break
        default:
            return false
        }
        guard keyCode >= 0, event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { return false }
        if type == .keyUp {
            defer { swallowKeyUp = false }
            return swallowKeyUp
        }
        guard event.flags.intersection(Self.modifierMask) == flags else { return false }
        // Let Glink's own windows (the shortcut recorder in Settings/onboarding) see the keys.
        if NSApp.isActive, let key = NSApp.keyWindow, !(key is CommandPanel) { return false }
        swallowKeyUp = true
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { HotkeyGuard.shared.toggleFromHotkey() }
        }
        return true
    }
}
