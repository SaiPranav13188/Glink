import AppKit
import SwiftUI

/// v2 floating notes: a small always-on-top glass window for quick notes, saved as you type
/// to ~/Library/Application Support/Glink/Notes.md.
@MainActor
final class FloatingNotesController: NSObject, NSWindowDelegate {
    static let shared = FloatingNotesController()
    private var window: NSPanel?

    static var fileURL: URL { URL.applicationSupportDirectory.appending(path: "Glink/Notes.md") }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() { isVisible ? close() : show() }

    func show() {
        let w = window ?? makeWindow()
        window = w
        w.appearance = AppSettings.shared.theme.appearance
        w.alphaValue = 0
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.isOff ? 0 : 0.18
            w.animator().alphaValue = 1
        }
    }

    func close() {
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.isOff ? 0 : 0.12
            w.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { w.orderOut(nil) } })
    }

    private func makeWindow() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Notes"
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.minSize = NSSize(width: 240, height: 200)
        p.backgroundColor = .clear
        p.contentView = NSHostingView(rootView: FloatingNotesView())
        p.setFrameAutosaveName("GlinkFloatingNotes")
        if p.frame.origin == .zero, let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 344, y: screen.visibleFrame.maxY - 404))
        }
        p.delegate = self
        return p
    }
}

private struct FloatingNotesView: View {
    @State private var text = (try? String(contentsOf: FloatingNotesController.fileURL, encoding: .utf8)) ?? ""
    @State private var saveTask: Task<Void, Never>?
    @State private var saved = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notes").font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: saved ? "checkmark.circle" : "circle.dotted")
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(saved ? "Saved" : "Saving")
            }
            .padding(.horizontal, 14)
            .padding(.top, 30)
            .padding(.bottom, 6)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .accessibilityLabel("Note text")
        }
        .background(PanelBackground(cornerRadius: 0))
        .ignoresSafeArea()
        .onChange(of: text) {
            saved = false
            saveTask?.cancel()
            let snapshot = text
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                let url = FloatingNotesController.fileURL
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? snapshot.write(to: url, atomically: true, encoding: .utf8)
                withAnimation(Motion.resolved(Motion.gentle)) { saved = true }
            }
        }
    }
}
