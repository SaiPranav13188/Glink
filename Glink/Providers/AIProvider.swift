import AppKit
import GlinkCore

/// On-device AI commands. When the model isn't available they're hidden; asking for AI shows one
/// inline card that explains why instead.
@MainActor
final class AIProvider: SearchProvider {
    let id = "ai"
    let sectionTitle = "AI · On-device"
    let sectionOrder = 7
    let limit = 6

    private let targets: [(AICommand, MatchTarget)] = AICommand.allCases.map {
        ($0, MatchTarget(title: $0.title, keywords: ["ai assistant llm on-device private",
                                                     $0 == .ask ? "chat question" : "selection text clipboard"]))
    }

    func results(for query: String) async -> [SearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let q = FuzzyMatcher.prepareQuery(trimmed)
        let availability = AIService.availability

        guard case .available = availability else {
            // Hide the commands; only explain why when someone is clearly looking for AI.
            let lowered = trimmed.lowercased()
            guard ["ai", "ask", "rewrite", "summar"].contains(where: { lowered.hasPrefix($0) }),
                  case .unavailable(let reason) = availability else { return [] }
            return [Self.unavailableCard(reason)]
        }

        // "ask what is a closure in swift" runs directly.
        if trimmed.lowercased().hasPrefix("ask ") {
            let question = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            if !question.isEmpty {
                var item = Self.item(for: .ask, score: 3, indices: [])
                item.title = "Ask AI: \(question)"
                item.requiresArgument = false
                item.actions = [ItemAction(id: "ask", title: "Ask On-device AI", symbol: "sparkles", shortcut: .returnKey) {
                    .push(.ai(AIRequest(command: .ask, input: question)))
                }]
                return [item]
            }
        }

        return targets.compactMap { command, target in
            guard let m = target.match(q) else { return nil }
            return Self.item(for: command, score: m.score * 0.9, indices: m.matchedIndices)
        }
    }

    func item(withID id: String) -> SearchItem? {
        guard AIService.availability.isAvailable,
              id.hasPrefix("ai."), let command = AICommand(rawValue: String(id.dropFirst(3))) else { return nil }
        return Self.item(for: command, score: 0, indices: [])
    }

    func suggestions() -> [SearchItem] {
        AIService.availability.isAvailable ? [Self.item(for: .ask, score: 0, indices: [])] : []
    }

    static func unavailableCard(_ reason: AIUnavailableReason) -> SearchItem {
        SearchItem(id: "ai.unavailable", title: reason.title, subtitle: reason.message,
                   icon: .symbol("sparkles", tint: .gray), kind: .ai, score: 1, accessory: "AI",
                   actions: [ItemAction(id: "fix", title: reason.opensSystemSettings ? "Open Apple Intelligence Settings" : "Open Glink AI Settings",
                                        symbol: "gearshape", shortcut: .returnKey) {
                       if reason.opensSystemSettings { AIService.openAppleIntelligenceSettings() }
                       else { SettingsWindowController.shared.show(pane: .ai) }
                       return .dismiss
                   }])
    }

    static func item(for command: AICommand, score: Double, indices: [Int]) -> SearchItem {
        let subtitle: String? = switch command.source {
        case .none: "On-device · Private"
        case .selection: "Uses the selected text · On-device"
        case .clipboard: "Uses your clipboard · On-device"
        }
        var item = SearchItem(
            id: "ai.\(command.rawValue)", title: command.title, subtitle: subtitle,
            icon: .symbol(command.symbol, tint: .purple), kind: .ai, score: score, matchedIndices: indices,
            accessory: "AI"
        )
        switch command.source {
        case .none:
            item.argumentPlaceholder = "Ask anything"
            item.requiresArgument = true
            item.runWithArgument = { text in .push(.ai(AIRequest(command: .ask, input: text))) }
            item.actions = [ItemAction(id: "ask", title: "Ask AI", symbol: "sparkles", shortcut: .returnKey) { .stay }]
        case .clipboard:
            item.actions = [ItemAction(id: "run", title: "Summarize Clipboard", symbol: command.symbol, shortcut: .returnKey) {
                guard let clip = NSPasteboard.general.string(forType: .string),
                      !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return .toast(.failure("Clipboard has no text", "Copy some text, then try again."))
                }
                return .push(.ai(AIRequest(command: command, input: clip, sourceLabel: "Clipboard text")))
            }]
        case .selection:
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

    private let target = MatchTarget(title: "Check MCP Security", keywords: ["mcp config check", "security audit model context protocol servers risk scan"])

    func results(for query: String) async -> [SearchItem] {
        guard let m = target.match(FuzzyMatcher.prepareQuery(query)) else { return [] }
        return [Self.item(score: m.score, indices: m.matchedIndices)]
    }

    func item(withID id: String) -> SearchItem? { id == "mcp.check" ? Self.item(score: 0, indices: []) : nil }
    func suggestions() -> [SearchItem] { [Self.item(score: 0, indices: [])] }

    static func item(score: Double, indices: [Int]) -> SearchItem {
        SearchItem(id: "mcp.check", title: "Check MCP Security", subtitle: "Scan MCP server configs for risky settings",
                   icon: .symbol("checkmark.shield", tint: .green), kind: .mcp, score: score, matchedIndices: indices,
                   accessory: "Security",
                   actions: [ItemAction(id: "run", title: "Run Check", symbol: "checkmark.shield", shortcut: .returnKey) { .push(.mcpCheck) }])
    }
}
