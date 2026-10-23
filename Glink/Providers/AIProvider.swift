import AppKit
import GlinkCore

/// AI commands: Ask AI (takes an argument) and actions on the selected text.
@MainActor
final class AIProvider: SearchProvider {
    let id = "ai"
    let sectionTitle = "AI"
    let sectionOrder = 7
    let limit = 4

    private let targets: [(AICommand, MatchTarget)] = AICommand.allCases.map {
        ($0, MatchTarget(title: $0.title, keywords: ["ai claude llm", $0 == .ask ? "chat question" : "selection text"]))
    }

    func results(for query: String) async -> [SearchItem] {
        let q = FuzzyMatcher.prepareQuery(query)
        return targets.compactMap { command, target in
            guard let m = target.match(q) else { return nil }
            return Self.item(for: command, score: m.score * 0.9, indices: m.matchedIndices)
        }
    }

    func item(withID id: String) -> SearchItem? {
        guard id.hasPrefix("ai."), let command = AICommand(rawValue: String(id.dropFirst(3))) else { return nil }
        return Self.item(for: command, score: 0, indices: [])
    }

    func suggestions() -> [SearchItem] { [Self.item(for: .ask, score: 0, indices: [])] }

    static func item(for command: AICommand, score: Double, indices: [Int]) -> SearchItem {
        var item = SearchItem(
            id: "ai.\(command.rawValue)", title: command.title,
            subtitle: command.usesSelection ? "Uses the selected text" : nil,
            icon: .symbol(command.symbol, tint: .purple), kind: .ai, score: score, matchedIndices: indices,
            accessory: "AI"
        )
        if command == .ask {
            item.argumentPlaceholder = "Ask anything"
            item.requiresArgument = true
            item.runWithArgument = { text in
                .push(.ai(AIRequest(command: .ask, input: text)))
            }
            item.actions = [ItemAction(id: "ask", title: "Ask AI", symbol: "sparkles", shortcut: .returnKey) { .stay }]
        } else {
            item.actions = [ItemAction(id: "run", title: "Run with Selected Text", symbol: command.symbol, shortcut: .returnKey) {
                let appName = PanelController.shared.previousApp?.localizedName
                if let selected = SelectedTextReader.selectedText() {
                    return .push(.ai(AIRequest(command: command, input: selected,
                                               sourceLabel: "Selected text\(appName.map { " in \($0)" } ?? "")")))
                }
                if let clip = NSPasteboard.general.string(forType: .string), !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .push(.ai(AIRequest(command: command, input: clip, sourceLabel: "Clipboard text")))
                }
                return .toast(.failure("No text selected", PermissionsManager.shared.isAccessibilityTrusted
                                       ? "Select some text in any app, then try again."
                                       : "Copy some text first, or enable Accessibility so Glink can read the selection."))
            }]
        }
        return item
    }
}

/// The differentiator: scan local MCP server configs and score their risk.
@MainActor
final class MCPCheckProvider: SearchProvider {
    let id = "mcp"
    let sectionTitle = "Developer"
    let sectionOrder = 8
    let limit = 1

    private let target = MatchTarget(title: "MCP Config Check", keywords: ["security audit model context protocol servers risk scan"])

    func results(for query: String) async -> [SearchItem] {
        guard let m = target.match(FuzzyMatcher.prepareQuery(query)) else { return [] }
        return [Self.item(score: m.score, indices: m.matchedIndices)]
    }

    func item(withID id: String) -> SearchItem? { id == "mcp.check" ? Self.item(score: 0, indices: []) : nil }
    func suggestions() -> [SearchItem] { [Self.item(score: 0, indices: [])] }

    static func item(score: Double, indices: [Int]) -> SearchItem {
        SearchItem(id: "mcp.check", title: "MCP Config Check", subtitle: "Scan MCP server configs for risky settings",
                   icon: .symbol("checkmark.shield", tint: .green), kind: .mcp, score: score, matchedIndices: indices,
                   accessory: "Security",
                   actions: [ItemAction(id: "run", title: "Run Check", symbol: "checkmark.shield", shortcut: .returnKey) { .push(.mcpCheck) }])
    }
}
