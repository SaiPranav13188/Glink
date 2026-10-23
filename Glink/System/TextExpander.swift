import AppKit
import ApplicationServices
import Carbon.HIToolbox
import GlinkCore
import SwiftData

/// Keyword-triggered snippet expansion via a listen-only CGEventTap.
///
/// Privacy: typed characters live only in a short in-memory buffer (last 64 characters)
/// used to spot keywords. Nothing is ever logged or written to disk.
@MainActor
final class TextExpander {
    static let shared = TextExpander()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
    private var keywords: [String: Snippet] = [:]
    private(set) var isRunning = false

    func reloadSnippets() {
        let snippets = (try? DataStore.shared.context.fetch(FetchDescriptor<Snippet>())) ?? []
        keywords = Dictionary(snippets.filter { !$0.keyword.isEmpty }.map { ($0.keyword, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func startIfPossible() {
        guard AppSettings.shared.snippetsEnabled, AXIsProcessTrusted(), tap == nil else { return }
        reloadSnippets()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            MainActor.assumeIsolated {
                TextExpander.shared.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: callback, userInfo: nil) else {
            Log.system.error("Couldn't create event tap for snippets")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        buffer = ""
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .leftMouseDown, .rightMouseDown:
            buffer = ""   // caret probably moved
            return
        case .keyDown:
            break
        default:
            return
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Paster.syntheticEventMarker else { return }
        // Ignore typing inside Glink itself and in secure fields.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        if IsSecureEventInputEnabled() { buffer = ""; return }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { buffer = ""; return }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            if !buffer.isEmpty { buffer.removeLast() }
            return
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape,
             kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            buffer = ""
            return
        default:
            break
        }

        guard let chars = NSEvent(cgEvent: event)?.characters, !chars.isEmpty else { return }
        buffer += chars
        if buffer.count > 64 { buffer.removeFirst(buffer.count - 64) }

        guard let keyword = SnippetTrigger.match(typed: buffer, keywords: keywords.keys), let snippet = keywords[keyword] else { return }
        buffer = ""
        expand(snippet, replacing: keyword.count)
    }

    private func expand(_ snippet: Snippet, replacing count: Int) {
        let expanded = SnippetExpander.expand(snippet.text, context: SnippetContext(clipboard: NSPasteboard.general.string(forType: .string)))
        snippet.useCount += 1
        DataStore.shared.save()

        // Let the keyword's final keystroke land before deleting it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            for _ in 0..<count { Paster.postKey(CGKeyCode(kVK_Delete)) }
            let saved = Paster.snapshotPasteboard()
            Paster.paste(expanded.text, cursorOffsetFromEnd: expanded.cursorOffsetFromEnd)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Paster.restorePasteboard(saved) }
        }
    }
}
