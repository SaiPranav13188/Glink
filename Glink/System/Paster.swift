import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Writes to the pasteboard and synthesizes keystrokes into the frontmost app.
@MainActor
enum Paster {
    /// Marks events Glink posts so the text expander ignores them.
    static let syntheticEventMarker: Int64 = 0x474C4E4B // "GLNK"

    static var canSynthesizeKeys: Bool { AXIsProcessTrusted() }

    /// Long enough for the panel to order out and the previous app's window to become key again.
    static var pasteDelay: TimeInterval { Motion.panelOutDuration + 0.1 }

    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        ClipboardStore.shared.ignoreCurrentChange()
    }

    /// Copies and then presses ⌘V in the app that was frontmost before Glink appeared.
    /// Returns false when Accessibility is missing (the text is still copied).
    @discardableResult
    static func paste(_ string: String, cursorOffsetFromEnd: Int? = nil) -> Bool {
        copy(string)
        guard canSynthesizeKeys else { return false }
        // The panel keeps keyboard focus until its exit animation ends; paste only after that,
        // or ⌘V would land in Glink's own search field.
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            pressCommandV()
            if let offset = cursorOffsetFromEnd, offset > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    for _ in 0..<offset { postKey(CGKeyCode(kVK_LeftArrow)) }
                }
            }
        }
        return true
    }

    static func pressCommandV() {
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    static func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Snapshot of every item/type on the general pasteboard, so a temporary paste can put things back.
    static func snapshotPasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        NSPasteboard.general.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let d = item.data(forType: type) { dict[type] = d } }
            return dict
        } ?? []
    }

    static func restorePasteboard(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let items = snapshot.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
        ClipboardStore.shared.ignoreCurrentChange()
    }
}

/// Reads the selected text in the frontmost app through the Accessibility API.
@MainActor
enum SelectedTextReader {
    static func selectedText() -> String? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }
}
