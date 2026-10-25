import AppKit
import GlinkCore
import KeyboardShortcuts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - General

struct GeneralSettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Hotkeys") {
                KeyboardShortcuts.Recorder("Open Glink", name: .togglePanel)
                KeyboardShortcuts.Recorder("Clipboard History", name: .clipboardHistory)
            }
            Section("Startup") {
                Toggle("Launch Glink at login", isOn: $settings.launchAtLogin)
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { Updater.shared.automaticallyChecks },
                    set: { Updater.shared.automaticallyChecks = $0 }))
                HStack {
                    Button("Check Now") { Updater.shared.checkForUpdates() }
                    if let version = Updater.shared.pendingUpdateVersion {
                        Label("Version \(version) is available", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            Section("Panel") {
                Picker("Position", selection: $settings.panelPosition) {
                    ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                }
                Picker("Text size", selection: $settings.textSize) {
                    ForEach(TextSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Include files in search", isOn: $settings.fileSearchEnabled)
            }
            Section {
                Toggle("Menu bar mini mode", isOn: $settings.menuBarMiniMode)
                Button("Open Script Commands Folder") {
                    ScriptRunner.ensureFolder()
                    NSWorkspace.shared.open(ScriptRunner.folder)
                }
            } header: {
                Text("Extras")
            } footer: {
                Text("Mini mode: clicking the menu bar icon opens a compact search; right-click for the menu. Script commands: drop executable scripts with # @glink.title comments into the folder.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Show Welcome Tour…") { OnboardingWindowController.shared.show() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance (with a live preview that morphs as settings change)

struct AppearanceSettingsPane: View {
    @Bindable private var settings = AppSettings.shared
    @AppStorage("playfulMascots") private var mascots = true

    var body: some View {
        Form {
            Section {
                MiniPanelPreview(style: settings.windowStyle, theme: settings.theme, level: settings.animationLevel)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(ThemePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Window style", selection: $settings.windowStyle) {
                    ForEach(WindowStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Animations", selection: $settings.animationLevel) {
                    ForEach(AnimationLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Playful mascots (a kitten, a puppy and friends now and then)", isOn: $mascots)
                Button("Say hi 👋") { Mascots.shared.celebrate(.milestone(100)) }
                    .disabled(!mascots)
            } footer: {
                Text("Glink also follows Reduce Motion, Reduce Transparency and Increase Contrast in System Settings › Accessibility.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MiniPanelPreview: View {
    let style: WindowStyle
    let theme: ThemePreference
    let level: AnimationLevel
    @State private var selected = 0
    @State private var timer: Timer?
    @Namespace private var ns

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple, .pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.orange.opacity(0.6)).frame(width: 120).blur(radius: 30).offset(x: -120, y: 40)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true).foregroundStyle(.secondary)
                    Text("Search apps, files, and commands…").foregroundStyle(.tertiary)
                    Spacer()
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .frame(height: 34)
                Divider()
                VStack(spacing: 0) {
                    ForEach(0..<3) { i in
                        HStack(spacing: 8) {
                            SymbolTile(symbol: ["safari", "doc.on.clipboard", "rectangle.lefthalf.inset.filled"][i],
                                       tint: [.blue, .orange, .indigo][i], size: 16)
                            Text(["Safari", "Clipboard History", "Left Half"][i]).font(.system(size: 11))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background {
                            if selected == i {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.18))
                                    .matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(width: 300)
            .background(PanelBackground(cornerRadius: 12, style: style))
            .overlay(GlassEdge(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .environment(\.colorScheme, scheme)
            .animation(level == .off ? nil : (level == .reduced ? Motion.reducedFade : Motion.snappy), value: selected)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(Motion.smooth, value: style)
        .animation(Motion.smooth, value: theme)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { _ in
                MainActor.assumeIsolated { selected = (selected + 1) % 3 }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var scheme: ColorScheme {
        switch theme {
        case .light: .light
        case .dark: .dark
        case .system: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
    }
}

// MARK: - Clipboard

struct ClipboardSettingsPane: View {
    @Bindable private var settings = AppSettings.shared
    @State private var confirmClear = false
    @State private var selectedIgnored: String?

    var body: some View {
        Form {
            Section {
                Toggle("Save clipboard history", isOn: $settings.clipboardEnabled)
                Picker("Keep", selection: $settings.clipboardHistoryLimit) {
                    ForEach([50, 100, 200, 500, 1000], id: \.self) { Text("\($0) items").tag($0) }
                }
            } footer: {
                Text("Items marked as concealed by password managers are never saved.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Ignored apps") {
                if settings.ignoredBundleIDs.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(settings.ignoredBundleIDs, id: \.self) { id in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            ItemIconView(icon: .path(url.path), size: 18)
                            Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                        } else {
                            Image(systemName: "app.dashed").accessibilityHidden(true).frame(width: 18)
                            Text(id).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            withAnimation(Motion.smooth) { settings.ignoredBundleIDs.removeAll { $0 == id } }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Button("Add App…", action: addApp)
            }
            Section {
                Button("Clear Clipboard History…", role: .destructive) { confirmClear = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear all unpinned clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { ClipboardStore.shared.clearAll() }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.ignoredBundleIDs.contains(id) {
                withAnimation(Motion.smooth) { settings.ignoredBundleIDs.append(id) }
            }
        }
    }
}

// MARK: - Snippets

struct SnippetsSettingsPane: View {
    let navigation: SettingsNavigation
    @Environment(\.modelContext) private var context
    @Query(sort: \Snippet.name) private var snippets: [Snippet]
    @State private var selection: Snippet.ID?
    @Bindable private var settings = AppSettings.shared
    private var permissions: PermissionsManager { PermissionsManager.shared }

    var body: some View {
        VStack(spacing: 0) {
            if settings.snippetsEnabled && !permissions.isAccessibilityTrusted {
                PermissionCard(feature: "expand snippets as you type")
                    .padding([.horizontal, .top], 16)
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    List(snippets, selection: $selection) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name.isEmpty ? "Untitled" : s.name)
                            Text(s.keyword).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        .tag(s.id)
                    }
                    Divider()
                    HStack(spacing: 0) {
                        Button { add() } label: { Image(systemName: "plus").frame(width: 28, height: 22) }.accessibilityLabel("Add")
                        Button { removeSelected() } label: { Image(systemName: "minus").frame(width: 28, height: 22) }.accessibilityLabel("Remove")
                            .disabled(selection == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .padding(4)
                }
                .frame(width: 200)
                Divider()
                if let s = snippets.first(where: { $0.id == selection }) {
                    SnippetEditor(snippet: s)
                        .id(s.id)
                        .transition(.opacity)
                } else {
                    EmptyStateView(symbol: "text.quote", title: "No snippet selected", message: "Pick a snippet or press + to make one.")
                }
            }
            Divider()
            Toggle("Expand keywords as you type in any app", isOn: $settings.snippetsEnabled)
                .padding(12)
                .onChange(of: settings.snippetsEnabled) { _, on in
                    on ? TextExpander.shared.startIfPossible() : TextExpander.shared.stop()
                }
        }
        .motion(Motion.gentle, value: selection)
        .onAppear {
            if navigation.consumeCreateRequest() { add() } else if selection == nil { selection = snippets.first?.id }
        }
        .onChange(of: navigation.createRequest) { if navigation.consumeCreateRequest() { add() } }
    }

    private func add() {
        let s = Snippet(name: "New Snippet", keyword: ";new\(snippets.count + 1)", text: "Hello {cursor}")
        context.insert(s)
        try? context.save()
        withAnimation(Motion.smooth) { selection = s.id }
        TextExpander.shared.reloadSnippets()
    }

    private func removeSelected() {
        guard let s = snippets.first(where: { $0.id == selection }) else { return }
        let index = snippets.firstIndex(of: s) ?? 0
        context.delete(s)
        try? context.save()
        selection = snippets.indices.contains(index + 1) ? snippets[index + 1].id : snippets.first?.id
        TextExpander.shared.reloadSnippets()
    }
}

private struct SnippetEditor: View {
    @Bindable var snippet: Snippet

    var body: some View {
        Form {
            TextField("Name", text: $snippet.name)
            TextField("Keyword", text: $snippet.keyword)
                .font(.body.monospaced())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Text")
                    Spacer()
                    Menu("Insert Placeholder") {
                        ForEach(SnippetExpander.placeholders, id: \.self) { p in
                            Button(p) { snippet.text += p }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                TextEditor(text: $snippet.text)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            Section("Preview") {
                // Live preview: re-renders every second so {time} stays current.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(SnippetExpander.expand(snippet.text, context: SnippetContext(clipboard: NSPasteboard.general.string(forType: .string))).text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .contentTransition(.opacity)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { try? DataStore.shared.context.save() }
    }
}

// MARK: - Quicklinks

struct QuicklinksSettingsPane: View {
    let navigation: SettingsNavigation
    @Environment(\.modelContext) private var context
    @Query(sort: \Quicklink.name) private var links: [Quicklink]
    @State private var selection: Quicklink.ID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(links, selection: $selection) { link in
                    HStack(spacing: 8) {
                        SymbolTile(symbol: link.symbol, tint: .blue, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.name)
                            Text(link.keyword).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .tag(link.id)
                }
                Divider()
                HStack(spacing: 0) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 28, height: 22) }.accessibilityLabel("Add")
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 28, height: 22) }.accessibilityLabel("Remove")
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 210)
            Divider()
            if let link = links.first(where: { $0.id == selection }) {
                QuicklinkEditor(link: link).id(link.id).transition(.opacity)
            } else {
                EmptyStateView(symbol: "link", title: "No quicklink selected", message: "Quicklinks open a URL with what you type, e.g. “gh apple/swift”.")
            }
        }
        .motion(Motion.gentle, value: selection)
        .onAppear {
            if navigation.consumeCreateRequest() { add() } else if selection == nil { selection = links.first?.id }
        }
        .onChange(of: navigation.createRequest) { if navigation.consumeCreateRequest() { add() } }
    }

    private func add() {
        let link = Quicklink(name: "New Quicklink", keyword: "new", urlTemplate: "https://example.com/search?q={query}")
        context.insert(link)
        try? context.save()
        withAnimation(Motion.smooth) { selection = link.id }
    }

    private func remove() {
        guard let link = links.first(where: { $0.id == selection }) else { return }
        context.delete(link)
        try? context.save()
        selection = links.first?.id
    }
}

private struct QuicklinkEditor: View {
    @Bindable var link: Quicklink
    @State private var testQuery = "swift"
    static let symbols = ["link", "magnifyingglass", "globe", "book", "map", "play.rectangle", "cart",
                          "chevron.left.forwardslash.chevron.right", "bubble.left", "newspaper", "music.note", "airplane"]

    var body: some View {
        Form {
            TextField("Name", text: $link.name)
            TextField("Keyword", text: $link.keyword).font(.body.monospaced())
            TextField("URL", text: $link.urlTemplate).font(.body.monospaced())
            Picker("Icon", selection: $link.symbol) {
                ForEach(Self.symbols, id: \.self) { Label($0, systemImage: $0).labelStyle(.iconOnly).tag($0) }
            }
            Section {
                HStack {
                    TextField("Test query", text: $testQuery)
                    Button("Open") {
                        if let url = QuicklinkProvider.url(template: link.urlTemplate, query: testQuery) { NSWorkspace.shared.open(url) }
                    }
                }
            } footer: {
                Text("Use {query} where your search text goes. In Glink type “\(link.keyword) something”, or select it and press Tab.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { try? DataStore.shared.context.save() }
    }
}

// MARK: - AI (on-device)

struct AISettingsPane: View {
    @AppStorage("aiEnabled") private var enabled = true
    @State private var availability = AIService.availability

    var body: some View {
        Form {
            Section {
                Toggle("Enable on-device AI", isOn: $enabled)
                    .onChange(of: enabled) { availability = AIService.availability }
                HStack(spacing: 10) {
                    Image(systemName: availability.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(availability.isAvailable ? Color.green : Color.orange)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if case .unavailable(let reason) = availability {
                            Text(reason.title)
                            Text(reason.message).font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("Apple's on-device model is ready")
                            Text("Ask AI, rewrite selected text and summarize your clipboard.").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if case .unavailable(let reason) = availability, reason.opensSystemSettings {
                        Button("Open Settings") { AIService.openAppleIntelligenceSettings() }
                    }
                }
                .motion(Motion.smooth, value: availability)
            } header: {
                Text("Status")
            } footer: {
                Text("Glink's AI runs entirely on this Mac with Apple's Foundation Models. Nothing you ask or select is ever sent anywhere. Requires macOS 26, Apple silicon and Apple Intelligence.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { availability = AIService.availability }
    }
}

// MARK: - Privacy

struct PrivacySettingsPane: View {
    var body: some View {
        Form {
            Section("What Glink stores") {
                row("doc.on.clipboard", "Clipboard history", "Text, links, images and file references you copy. Stored only on this Mac.")
                row("text.quote", "Snippets & quicklinks", "The ones you create.")
                row("chart.bar", "Usage counts", "How often you open each result, so favorites rank higher.")
            }
            Section("What Glink never stores") {
                row("keyboard", "Keystrokes", "The snippet expander keeps only the last few characters in memory to spot keywords. Nothing is logged.")
                row("lock", "Password-manager items", "Clipboard entries marked as concealed are skipped.")
                row("antenna.radiowaves.left.and.right", "Analytics", "Glink sends no analytics or telemetry.")
                row("sparkles", "AI prompts", "AI runs on-device with Apple's Foundation Models. Nothing is sent off this Mac.")
            }
            Section {
                Button("Reveal Data Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL.applicationSupportDirectory.appending(path: "Glink")])
                }
            } footer: {
                Text(URL.applicationSupportDirectory.appending(path: "Glink").path).font(.footnote.monospaced()).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).accessibilityHidden(true).frame(width: 20).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedSettingsPane: View {
    @Bindable private var settings = AppSettings.shared
    @State private var confirmReset = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Ranking") {
                Button("Reset Ranking…") { confirmReset = true }
            }
            Section("Settings") {
                HStack {
                    Button("Export Settings…", action: export)
                    Button("Import Settings…", action: importSettings)
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary).transition(.opacity)
                }
            }
            Section {
                if settings.mcpExtraPaths.isEmpty {
                    Text("None. Use “Add Config…” in Check MCP Security to include project configs.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.mcpExtraPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "doc.text").accessibilityHidden(true).foregroundStyle(.secondary)
                        Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            withAnimation(Motion.smooth) { settings.mcpExtraPaths.removeAll { $0 == path } }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text("MCP security: added configs")
            }
            Section("Debugging") {
                Button("Copy Diagnostics") {
                    Paster.copy(diagnostics)
                    flash("Diagnostics copied.")
                }
                Button("Open Console") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset ranking?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                RankingStore.shared.reset()
                flash("Ranking reset.")
            }
        } message: {
            Text("Results go back to their default order and the Recent list is cleared.")
        }
    }

    private var diagnostics: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return """
        Glink \(v)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accessibility: \(PermissionsManager.shared.isAccessibilityTrusted ? "granted" : "not granted")
        Snippet expander: \(TextExpander.shared.isRunning ? "running" : "stopped")
        Clipboard items: \(ClipboardStore.shared.entries.count)
        """
    }

    private func flash(_ text: String) {
        withAnimation(Motion.smooth) { message = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(Motion.smooth) { message = nil } }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Glink Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ctx = DataStore.shared.context
        let snippets = ((try? ctx.fetch(FetchDescriptor<Snippet>())) ?? []).map { ["name": $0.name, "keyword": $0.keyword, "text": $0.text] }
        let links = ((try? ctx.fetch(FetchDescriptor<Quicklink>())) ?? []).map {
            ["name": $0.name, "keyword": $0.keyword, "url": $0.urlTemplate, "symbol": $0.symbol]
        }
        let payload: [String: Any] = ["version": 1, "settings": settings.exportDictionary(), "snippets": snippets, "quicklinks": links]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            flash("Exported to \(url.lastPathComponent).")
        } catch {
            flash("Export failed: \(error.localizedDescription)")
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let s = json["settings"] as? [String: Any] { settings.importDictionary(s) }
        let ctx = DataStore.shared.context
        let existingSnippets = Set(((try? ctx.fetch(FetchDescriptor<Snippet>())) ?? []).map(\.keyword))
        for s in json["snippets"] as? [[String: String]] ?? [] where !existingSnippets.contains(s["keyword"] ?? "") {
            ctx.insert(Snippet(name: s["name"] ?? "", keyword: s["keyword"] ?? "", text: s["text"] ?? ""))
        }
        let existingLinks = Set(((try? ctx.fetch(FetchDescriptor<Quicklink>())) ?? []).map(\.keyword))
        for l in json["quicklinks"] as? [[String: String]] ?? [] where !existingLinks.contains(l["keyword"] ?? "") {
            ctx.insert(Quicklink(name: l["name"] ?? "", keyword: l["keyword"] ?? "", urlTemplate: l["url"] ?? "", symbol: l["symbol"] ?? "link"))
        }
        DataStore.shared.save()
        TextExpander.shared.reloadSnippets()
        flash("Imported \(url.lastPathComponent).")
    }
}

// MARK: - About

struct AboutPane: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
            Text("Glink").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("A keyboard-first command bar for the Mac.\nBuilt by B. Sai Pranav with Swift, SwiftUI and AppKit.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { Motion.animate(Motion.bouncy) { appeared = true } }
    }
}
