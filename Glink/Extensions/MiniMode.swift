import AppKit
import SwiftUI

/// v2 menu bar mini mode: clicking the menu bar icon opens a compact search popover that shares
/// Glink's search engine. Sub-screens (clipboard, AI, MCP) open in the full panel.
@MainActor
final class MiniModeController: NSObject, NSPopoverDelegate {
    static let shared = MiniModeController()

    let model = PanelViewModel()
    private let popover = NSPopover()
    private var keyMonitor: Any?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = !Motion.isOff
        popover.contentSize = NSSize(width: 400, height: 420)
        popover.contentViewController = NSHostingController(rootView: MiniPanelView(model: model))
        popover.delegate = self
        model.onDismiss = { [weak self] in self?.close() }
        model.onPush = { [weak self] route in
            self?.close()
            PanelController.shared.show(route: route)
            return true
        }
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown { close(); return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { PanelController.shared.previousApp = front }
        model.prepareForOpen(resetState: true)
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.popover.contentViewController?.view.window else { return false }
                if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
                return self.model.handleKey(event)
            }
            return consumed ? nil : event
        }
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        PanelController.shared.previousApp?.activate()
    }
}

private struct MiniPanelView: View {
    @Bindable var model: PanelViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("", text: $model.query, prompt: Text("Search Glink…").foregroundStyle(.tertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .accessibilityLabel("Search")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            Divider()
            ResultsList(model: model, sections: model.sections)
            if let toast = model.toast {
                Divider()
                ToastView(toast: toast) { model.dismissToast() }
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 400, height: 420)
        .motion(Motion.bouncy, value: model.toast?.id)
        .onAppear { focused = true }
        .onChange(of: model.openCount) { focused = true }
    }
}
