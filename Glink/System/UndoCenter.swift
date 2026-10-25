import AppKit
import ApplicationServices
import Carbon.HIToolbox
import GlinkCore
import Observation
import SwiftUI

/// What it takes to reverse one action.
enum UndoPayload {
    case windowFrame(window: AXUIElement, previous: CGRect, appName: String?)
    case trashedFile(original: URL, inTrash: URL)
    case clipboard([[NSPasteboard.PasteboardType: Data]])
    case snippet(insertedCharacters: Int, pid: pid_t)
    case aiRewrite(pid: pid_t)

    var symbol: String {
        switch self {
        case .windowFrame: "macwindow"
        case .trashedFile: "trash"
        case .clipboard: "doc.on.clipboard"
        case .snippet: "text.quote"
        case .aiRewrite: "sparkles"
        }
    }
}

/// Records reversible actions and undoes them (⌘Z in Glink, the Undo toast, or Recent Actions).
@MainActor @Observable
final class UndoCenter {
    static let shared = UndoCenter()

    private(set) var log = UndoLog<UndoPayload>(capacity: 20)

    // MARK: Recording

    func record(_ title: String, _ payload: UndoPayload, expiresAfter: TimeInterval? = nil, showToast: Bool = true) {
        let id = log.record(title, payload: payload, expiresAfter: expiresAfter)
        Mascots.shared.countAction()
        guard showToast else { return }
        let toast = Toast(style: .success, title: "\(title) · ⌘Z to undo", message: nil, undoID: id)
        if PanelController.shared.isVisible {
            PanelController.shared.viewModel.showToast(toast)
        } else {
            UndoToastController.shared.show(toast)
        }
    }

    func recordWindowMove(window: AXUIElement, previousAXFrame: CGRect, appName: String?, command: String) {
        record(command, .windowFrame(window: window, previous: previousAXFrame, appName: appName))
    }

    func recordTrash(original: URL, inTrash: URL) {
        record("Moved \(original.lastPathComponent) to Trash", .trashedFile(original: original, inTrash: inTrash))
    }

    func recordClipboardReplaced(previous: [[NSPasteboard.PasteboardType: Data]]) {
        record("Copied", .clipboard(previous), showToast: false)
    }

    func recordSnippet(name: String, insertedCharacters: Int) {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        // Only safe while the caret is still right after the expansion.
        record("Expanded \(name)", .snippet(insertedCharacters: insertedCharacters, pid: pid), expiresAfter: 30)
    }

    func recordAIRewrite(original: String, replacement: String) {
        guard let pid = PanelController.shared.previousApp?.processIdentifier else { return }
        record("Rewrote selection", .aiRewrite(pid: pid), expiresAfter: 120)
    }

    // MARK: Undoing

    /// Undoes the newest reversible action. Returns its title, or nil if there was nothing to undo.
    @discardableResult
    func undoLast() -> String? {
        guard let entry = log.lastReversible() else { return nil }
        return undo(entry.id) ? entry.title : nil
    }

    @discardableResult
    func undo(_ id: UUID) -> Bool {
        guard let entry = log.entry(id: id), entry.isReversible() else { return false }
        let ok = perform(entry.payload)
        if ok {
            log.markUndone(id)
            Mascots.celebrate(.undo)
            Haptics.level()
        }
        return ok
    }

    private func perform(_ payload: UndoPayload) -> Bool {
        switch payload {
        case .windowFrame(let window, let previous, _):
            var origin = previous.origin, size = previous.size
            guard let pos = AXValueCreate(.cgPoint, &origin), let sz = AXValueCreate(.cgSize, &size) else { return false }
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
            let r = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
            return r == .success
        case .trashedFile(let original, let inTrash):
            guard !FileManager.default.fileExists(atPath: original.path) else { return false }
            return (try? FileManager.default.moveItem(at: inTrash, to: original)) != nil
        case .clipboard(let snapshot):
            Paster.restorePasteboard(snapshot)
            return true
        case .snippet(let count, let pid):
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, Paster.canSynthesizeKeys else { return false }
            for _ in 0..<count { Paster.postKey(CGKeyCode(kVK_Delete)) }
            return true
        case .aiRewrite(let pid):
            guard Paster.canSynthesizeKeys, let app = NSRunningApplication(processIdentifier: pid) else { return false }
            PanelController.shared.hide()
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + Paster.pasteDelay) {
                Paster.postKey(CGKeyCode(kVK_ANSI_Z), flags: .maskCommand)
            }
            return true
        }
    }

    /// Recent Actions as panel rows.
    func sections(query: String) -> [ResultSection] {
        let q = query.lowercased()
        let items: [SearchItem] = log.entries.filter { q.isEmpty || $0.title.lowercased().contains(q) }.map { entry in
            let reversible = entry.isReversible()
            let id = entry.id
            return SearchItem(
                id: "undo.\(entry.id.uuidString)", title: entry.title,
                subtitle: entry.undone ? "Undone" : (reversible ? "Can be undone" : "Can no longer be undone"),
                icon: .symbol(entry.payload.symbol, tint: entry.undone ? .gray : .blue), kind: .command,
                accessory: entry.date.formatted(.relative(presentation: .named)),
                actions: reversible ? [ItemAction(id: "undo", title: "Undo", symbol: "arrow.uturn.backward", shortcut: .returnKey) {
                    UndoCenter.shared.undo(id) ? .toast(.success("Undone", entry.title)) : .toast(.failure("Couldn't undo", entry.title))
                }] : []
            )
        }
        return items.isEmpty ? [] : [ResultSection(id: "recent-actions", title: "Last \(items.count) actions", items: items)]
    }
}

// MARK: - Undo toast (shown after the panel closes)

/// A small clickable toast at the bottom of the screen: "Done · ⌘Z to undo [Undo]" with a draining bar.
@MainActor
final class UndoToastController {
    static let shared = UndoToastController()
    private var window: NSPanel?
    private let model = UndoToastModel()
    private var hideTask: Task<Void, Never>?

    func show(_ toast: Toast) {
        let panel = window ?? makeWindow()
        window = panel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let size = NSSize(width: 460, height: 120)
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 50,
                              width: size.width, height: size.height), display: false)
        panel.appearance = AppSettings.shared.theme.appearance
        model.toast = toast
        model.started = Date()
        model.visible = false
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [model] in withAnimation(Motion.resolved(Motion.bouncy)) { model.visible = true } }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        withAnimation(Motion.resolved(Motion.smooth)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if self?.model.visible == false { self?.window?.orderOut(nil) }
        }
    }

    private func makeWindow() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.contentView = NSHostingView(rootView: UndoToastView(model: model) { [weak self] in
            if let id = self?.model.toast?.undoID { UndoCenter.shared.undo(id) }
            self?.hide()
        })
        return p
    }
}

@MainActor @Observable
final class UndoToastModel {
    var toast: Toast?
    var started = Date()
    var visible = false
}

private struct UndoToastView: View {
    let model: UndoToastModel
    let onUndo: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            MascotStage().frame(height: 110)
            if let toast = model.toast {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                        Text(toast.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Undo", action: onUndo).controlSize(.small).buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    UndoCountdownBar(started: model.started, duration: 5)
                }
                .frame(width: 420)
                .background(PanelBackground(cornerRadius: 12))
                .overlay(GlassEdge(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                .offset(y: model.visible ? 0 : 20)
                .opacity(model.visible ? 1 : 0)
                .scaleEffect(model.visible ? 1 : 0.95)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// A thin bar that drains as the undo window runs out.
struct UndoCountdownBar: View {
    let started: Date
    let duration: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let left = max(0, 1 - ctx.date.timeIntervalSince(started) / duration)
            GeometryReader { geo in
                Capsule().fill(Color.accentColor.opacity(0.7)).frame(width: geo.size.width * left, height: 2)
            }
            .frame(height: 2)
        }
    }
}
