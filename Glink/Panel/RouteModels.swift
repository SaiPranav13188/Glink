import AppKit
import GlinkCore
import UniformTypeIdentifiers
import MCPShieldCore
import Observation
import SwiftData
import SwiftUI

// MARK: - Clipboard History

@MainActor @Observable
final class ClipboardRouteModel {
    /// Toggled when the selection changes so the preview can "zoom" from the row thumbnail.
    var previewZoomed = true

    func refresh() { ClipboardStore.shared.reload() }

    func sections(query: String) -> [ResultSection] {
        let entries = ClipboardStore.shared.search(query)
        let calendar = Calendar.current
        var pinned: [SearchItem] = [], today: [SearchItem] = [], yesterday: [SearchItem] = [], earlier: [SearchItem] = []
        for e in entries {
            var item = ClipboardProvider.item(for: e, score: 0)
            item.subtitle = nil
            item.accessory = e.isPinned ? nil : e.createdAt.formatted(date: .omitted, time: .shortened)
            if e.isPinned { pinned.append(item) }
            else if calendar.isDateInToday(e.createdAt) { today.append(item) }
            else if calendar.isDateInYesterday(e.createdAt) { yesterday.append(item) }
            else {
                item.accessory = e.createdAt.formatted(.dateTime.month(.abbreviated).day())
                earlier.append(item)
            }
        }
        return [("pinned", "Pinned", pinned), ("today", "Today", today), ("yesterday", "Yesterday", yesterday), ("earlier", "Earlier", earlier)]
            .filter { !$0.2.isEmpty }
            .map { ResultSection(id: $0.0, title: $0.1, items: $0.2) }
    }

    func entry(for item: SearchItem?) -> ClipboardEntry? {
        guard let item, item.id.hasPrefix("clip:"), let uuid = UUID(uuidString: String(item.id.dropFirst(5))) else { return nil }
        return ClipboardStore.shared.entry(id: uuid)
    }
}

// MARK: - Snippets

@MainActor @Observable
final class SnippetsRouteModel {
    private(set) var snippets: [Snippet] = []

    func refresh() {
        snippets = (try? DataStore.shared.context.fetch(FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func sections(query: String) -> [ResultSection] {
        let q = FuzzyMatcher.prepareQuery(query)
        let items: [SearchItem] = snippets.compactMap { s in
            if q.isEmpty { return SnippetProvider.item(for: s, score: 0, indices: []) }
            guard let m = MatchTarget(title: s.name, keywords: [s.keyword, s.text]).match(q) else { return nil }
            return SnippetProvider.item(for: s, score: m.score, indices: m.matchedIndices)
        }
        .sorted { q.isEmpty ? false : $0.score > $1.score }
        .map { var i = $0; i.subtitle = nil; return i }
        return items.isEmpty ? [] : [ResultSection(id: "snippets", title: "Snippets", items: items)]
    }

    func snippet(for item: SearchItem?) -> Snippet? {
        guard let item, item.id.hasPrefix("snippet:"), let uuid = UUID(uuidString: String(item.id.dropFirst(8))) else { return nil }
        return snippets.first { $0.id == uuid }
    }
}

// MARK: - AI

struct AITurn: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
    var response: String = ""
}

/// Streams a response and reveals it word by word with a blinking caret.
@MainActor @Observable
final class AIConversationModel {
    private(set) var request: AIRequest?
    private(set) var turns: [AITurn] = []
    /// Text revealed so far for the last turn (trails the network stream for a smooth cadence).
    private(set) var revealed = ""
    private(set) var isStreaming = false
    private(set) var error: String?

    @ObservationIgnored private var received = ""
    @ObservationIgnored private var streamDone = false
    @ObservationIgnored private var history: [AIMessage] = []
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?

    var hasKey: Bool { AIService.shared.hasKey }
    var lastResponse: String { turns.last?.response ?? "" }

    func start(_ request: AIRequest) {
        cancel()
        self.request = request
        turns = []
        history = []
        error = nil
        let prompt: String
        if request.command == .ask {
            prompt = request.input
        } else {
            prompt = "\(request.command.instruction)\n\n<text>\n\(request.input)\n</text>"
        }
        send(prompt, display: request.input)
    }

    func followUp(_ text: String) {
        guard !isStreaming else { return }
        send(text, display: text)
    }

    func regenerate() {
        guard !isStreaming, let last = turns.last, let lastUser = history.last(where: { $0.role == "user" }) else { return }
        history.removeLast(history.last?.role == "assistant" ? 2 : 1)
        turns.removeLast()
        send(lastUser.content, display: last.prompt)
    }

    func cancel() {
        streamTask?.cancel()
        revealTask?.cancel()
        isStreaming = false
    }

    private func send(_ prompt: String, display: String) {
        error = nil
        history.append(AIMessage(role: "user", content: prompt))
        turns.append(AITurn(prompt: display))
        received = ""
        revealed = ""
        streamDone = false
        isStreaming = true

        let messages = history
        streamTask = Task { [weak self] in
            do {
                for try await chunk in AIService.shared.stream(messages) {
                    self?.received += chunk
                }
                self?.streamDone = true
            } catch {
                guard let self else { return }
                self.streamDone = true
                self.error = error.localizedDescription
            }
        }
        revealTask = Task { [weak self] in
            // Reveal whole words at a steady ~60 Hz cadence so text flows instead of jumping in chunks.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                let pending = self.received.count - self.revealed.count
                if pending > 0 {
                    let step = max(1, pending / 12)
                    var end = self.received.index(self.received.startIndex, offsetBy: self.revealed.count + step)
                    while end < self.received.endIndex, !self.received[end].isWhitespace { end = self.received.index(after: end) }
                    self.revealed = String(self.received[..<end])
                    self.turns[self.turns.count - 1].response = self.revealed
                } else if self.streamDone {
                    self.isStreaming = false
                    if !self.received.isEmpty { self.history.append(AIMessage(role: "assistant", content: self.received)) }
                    return
                }
            }
        }
    }

    var actions: [ItemAction] {
        let text = lastResponse
        let replaces = request?.command.replacesSelection ?? false
        let copy = ItemAction(id: "copy", title: "Copy Response", symbol: "doc.on.doc", shortcut: replaces ? .cmdReturn : .returnKey) {
            guard !text.isEmpty else { return .stay }
            Paster.copy(text)
            return .dismissWithHUD("Copied to Clipboard")
        }
        let paste = ItemAction(id: "paste", title: replaces ? "Replace Selection" : "Paste Response", symbol: "doc.on.clipboard",
                               shortcut: replaces ? .returnKey : .cmdReturn) {
            guard !text.isEmpty else { return .stay }
            if Paster.paste(text) { return .dismiss }
            return .dismissWithHUD("Copied — press ⌘V to paste")
        }
        let regenerate = ItemAction(id: "regenerate", title: "Regenerate", symbol: "arrow.clockwise", shortcut: KeyHint(.command, "r")) { [weak self] in
            self?.regenerate()
            return .stay
        }
        var list = replaces ? [paste, copy] : [copy, paste]
        list.append(regenerate)
        if !hasKey {
            list.insert(ItemAction(id: "settings", title: "Add API Key…", symbol: "key", shortcut: .returnKey) {
                SettingsWindowController.shared.show(pane: .ai)
                return .dismiss
            }, at: 0)
        }
        return list
    }
}

// MARK: - MCP Config Check

@MainActor @Observable
final class MCPCheckModel {
    private(set) var report: MCPReport?
    private(set) var isScanning = false
    /// 0…1 progress of the score gauge; views animate it.
    var gaugeProgress: Double = 0

    func scanIfNeeded() {
        if !isScanning { scan() }
    }

    func scan() {
        isScanning = true
        gaugeProgress = 0
        Task {
            let started = Date()
            let extra = AppSettings.shared.mcpExtraPaths.map { ("Added (\(($0 as NSString).lastPathComponent))", $0) }
            let result = await Task.detached(priority: .userInitiated) { MCPConfigAnalyzer.scan(extraPaths: extra) }.value
            // Keep the scanning state on screen briefly so the result doesn't flash.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.35 { try? await Task.sleep(for: .seconds(0.35 - elapsed)) }
            report = result
            isScanning = false
            try? await Task.sleep(for: .milliseconds(60))
            gaugeProgress = Double(result.score) / 100
        }
    }

    static func gradeStyle(_ score: Int) -> (symbol: String, tint: SymbolTint) {
        switch score {
        case 85...: ("checkmark.shield.fill", .green)
        case 60..<85: ("exclamationmark.triangle.fill", .orange)
        default: ("xmark.octagon.fill", .red)
        }
    }

    static func severityStyle(_ severity: Severity) -> (symbol: String, tint: SymbolTint) {
        switch severity {
        case .critical: ("xmark.octagon.fill", .red)
        case .high: ("exclamationmark.triangle.fill", .orange)
        case .medium: ("exclamationmark.circle.fill", .yellow)
        case .low: ("info.circle.fill", .blue)
        case .info: ("info.circle", .gray)
        }
    }

    /// Servers grouped by Tollgate's grade, worst first.
    func sections(query: String) -> [ResultSection] {
        guard let report else { return [] }
        let q = query.lowercased()
        let matching = report.results.filter { r in
            q.isEmpty || r.raw.name.lowercased().contains(q) || r.raw.source.lowercased().contains(q)
                || r.findings.contains { $0.title.lowercased().contains(q) || $0.ruleID.lowercased().contains(q) }
        }
        return ["At risk", "Needs work", "Good"].compactMap { grade in
            let items = matching.filter { $0.grade == grade }.map { item(for: $0, report: report) }
            return items.isEmpty ? nil : ResultSection(id: "grade.\(grade)", title: grade, items: items)
        }
    }

    func result(for item: SearchItem?) -> MCPServerResult? {
        guard let item else { return nil }
        return report?.results.first { $0.id == item.id }
    }

    /// Actions when there's no server to select (nothing found).
    var globalActions: [ItemAction] {
        var list = [
            ItemAction(id: "rescan", title: "Scan Again", symbol: "arrow.clockwise", shortcut: .returnKey) { [weak self] in
                self?.scan()
                return .stay
            },
            Self.addConfigAction,
        ]
        if let report, !report.results.isEmpty { list += reportActions(report) }
        return list
    }

    private func reportActions(_ report: MCPReport) -> [ItemAction] {
        [
            ItemAction(id: "copyReport", title: "Copy Full Report", symbol: "doc.richtext", shortcut: KeyHint([.command, .shift], "r")) {
                Paster.copy(MCPConfigAnalyzer.markdown(for: report))
                return .toast(.success("Copied Report", "Markdown, secrets redacted"))
            },
            ItemAction(id: "export", title: "Export JSON Report…", symbol: "square.and.arrow.up", shortcut: KeyHint(.command, "e")) {
                MCPCheckModel.exportJSON(report)
                return .dismiss
            },
        ]
    }

    private func item(for r: MCPServerResult, report: MCPReport) -> SearchItem {
        let style = Self.gradeStyle(r.score)
        let path = r.raw.configPath
        let fixes = r.findings.map { "• \($0.title): \($0.fix)" }.joined(separator: "\n")
        return SearchItem(
            id: r.id, title: r.raw.name, subtitle: r.raw.source + (r.raw.disabled ? " · disabled" : ""),
            icon: .symbol(style.symbol, tint: style.tint), kind: .mcp,
            accessory: "\(r.score)",
            actions: [
                ItemAction(id: "reveal", title: "Show Config in Finder", symbol: "folder", shortcut: .returnKey) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    return .dismiss
                },
                ItemAction(id: "open", title: "Open Config", symbol: "doc.text", shortcut: KeyHint(.command, "o")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    return .dismiss
                },
                ItemAction(id: "copyFixes", title: "Copy Fixes", symbol: "wrench.and.screwdriver", shortcut: KeyHint([.command, .shift], "c")) {
                    guard !fixes.isEmpty else { return .toast(.success("Nothing to fix")) }
                    Paster.copy(fixes)
                    return .toast(.success("Copied Fixes"))
                },
            ] + reportActions(report) + [Self.addConfigAction] + [
                ItemAction(id: "rescan", title: "Scan Again", symbol: "arrow.clockwise", shortcut: KeyHint(.command, "r")) { [weak self] in
                    self?.scan()
                    return .stay
                },
            ]
        )
    }

    static var addConfigAction: ItemAction {
        ItemAction(id: "addConfig", title: "Add Config…", symbol: "plus.rectangle.on.folder", shortcut: KeyHint(.command, "n")) {
            MCPCheckModel.addConfig()
            return .dismiss
        }
    }

    /// Lets the user add a config file or a project folder, then reopens the check with it included.
    static func addConfig() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate()
            let panel = NSOpenPanel()
            panel.message = "Choose an MCP config file, or a folder containing .mcp.json"
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.showsHiddenFiles = true
            guard panel.runModal() == .OK else { return }
            let settings = AppSettings.shared
            for url in panel.urls where !settings.mcpExtraPaths.contains(url.path) {
                settings.mcpExtraPaths.append(url.path)
            }
            PanelController.shared.show(route: .mcpCheck)
        }
    }

    /// Tollgate's JSON export (secrets redacted). Runs after the panel closes so the save sheet can take focus.
    static func exportJSON(_ report: MCPReport) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "MCP Config Check.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try MCPConfigAnalyzer.json(for: report).write(to: url)
                HUDController.shared.show("Report Exported")
            } catch {
                HUDController.shared.show("Export failed", symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}
