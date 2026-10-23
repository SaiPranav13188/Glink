import AppKit
import Observation
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, clipboard, snippets, quicklinks, ai, privacy, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .clipboard: "Clipboard"
        case .snippets: "Snippets"
        case .quicklinks: "Quicklinks"
        case .ai: "AI"
        case .privacy: "Privacy"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .clipboard: "doc.on.clipboard"
        case .snippets: "text.quote"
        case .quicklinks: "link"
        case .ai: "sparkles"
        case .privacy: "hand.raised"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .blue
        case .clipboard: .orange
        case .snippets: .pink
        case .quicklinks: .teal
        case .ai: .purple
        case .privacy: .indigo
        case .advanced: .gray
        case .about: .blue
        }
    }
}

@MainActor @Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
    /// Incremented to ask the current pane to start a new item ("Create Snippet").
    var createRequest = 0
    private var handledCreateRequest = 0

    /// True once per request, whether the pane was already open or appears because of it.
    func consumeCreateRequest() -> Bool {
        guard createRequest > handledCreateRequest else { return false }
        handledCreateRequest = createRequest
        return true
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    let navigation = SettingsNavigation()
    private var window: NSWindow?

    func show(pane: SettingsPane? = nil, createNew: Bool = false) {
        if let pane { navigation.pane = pane }
        if createNew { navigation.createRequest += 1 }
        let w = window ?? makeWindow()
        window = w
        w.appearance = AppSettings.shared.theme.appearance
        NSApp.activate()
        if !w.isVisible { w.center() }
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Glink Settings"
        w.titlebarAppearsTransparent = true
        w.toolbarStyle = .unified
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 700, height: 460)
        w.contentViewController = NSHostingController(rootView: SettingsView(navigation: navigation)
            .modelContainer(DataStore.shared.container))
        w.setFrameAutosaveName("GlinkSettings")
        w.delegate = self
        return w
    }

    func windowWillClose(_ notification: Notification) {
        TextExpander.shared.reloadSnippets()
    }
}

struct SettingsView: View {
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $navigation.pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SymbolTile(symbol: pane.symbol, tint: pane.tint, size: 20)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            ZStack {
                detail(for: navigation.pane)
                    .id(navigation.pane)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .motion(Motion.smooth, value: navigation.pane)
            .navigationTitle(navigation.pane.title)
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .clipboard: ClipboardSettingsPane()
        case .snippets: SnippetsSettingsPane(navigation: navigation)
        case .quicklinks: QuicklinksSettingsPane(navigation: navigation)
        case .ai: AISettingsPane()
        case .privacy: PrivacySettingsPane()
        case .advanced: AdvancedSettingsPane()
        case .about: AboutPane()
        }
    }
}
