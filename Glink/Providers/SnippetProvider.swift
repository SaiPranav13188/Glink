import AppKit
import GlinkCore
import SwiftData

/// Snippets in root search: ↵ pastes the expanded text into the frontmost app.
@MainActor
final class SnippetProvider: SearchProvider {
    let id = "snippets"
    let sectionTitle = "Snippets"
    let sectionOrder = 6
    let limit = 4

    func results(for query: String) async -> [SearchItem] {
        let q = FuzzyMatcher.prepareQuery(query)
        let snippets = (try? DataStore.shared.context.fetch(FetchDescriptor<Snippet>())) ?? []
        return snippets.compactMap { s in
            guard let m = MatchTarget(title: s.name, keywords: [s.keyword]).match(q) else { return nil }
            return Self.item(for: s, score: m.score * 0.85, indices: m.matchedIndices)
        }
    }

    static func item(for s: Snippet, score: Double, indices: [Int]) -> SearchItem {
        let template = s.text
        let preview = SnippetExpander.expand(template).text.replacingOccurrences(of: "\n", with: " ")
        return SearchItem(
            id: "snippet:\(s.id.uuidString)", title: s.name, subtitle: preview, icon: .symbol("text.quote", tint: .pink),
            kind: .snippet, score: score, matchedIndices: indices, accessory: s.keyword,
            actions: SnippetActions.make(template: template)
        )
    }
}

@MainActor
enum SnippetActions {
    static func make(template: String) -> [ItemAction] {
        [
            ItemAction(id: "paste", title: "Paste Snippet", symbol: "doc.on.clipboard", shortcut: .returnKey) {
                let expanded = SnippetExpander.expand(template, context: SnippetContext(clipboard: NSPasteboard.general.string(forType: .string)))
                if Paster.paste(expanded.text, cursorOffsetFromEnd: expanded.cursorOffsetFromEnd) { return .dismiss }
                return .dismissWithHUD("Copied — press ⌘V to paste")
            },
            ItemAction(id: "copy", title: "Copy Snippet", symbol: "doc.on.doc", shortcut: .cmdReturn) {
                Paster.copy(SnippetExpander.expand(template).text)
                return .dismissWithHUD("Copied to Clipboard")
            },
            ItemAction(id: "edit", title: "Edit Snippets…", symbol: "pencil", shortcut: KeyHint(.command, "e")) {
                SettingsWindowController.shared.show(pane: .snippets)
                return .dismiss
            },
        ]
    }
}

/// Saved URLs with an optional query: "gh apple/swift" opens github.com/apple/swift.
@MainActor
final class QuicklinkProvider: SearchProvider {
    let id = "quicklinks"
    let sectionTitle = "Quicklinks"
    let sectionOrder = 2
    let limit = 4

    func results(for query: String) async -> [SearchItem] {
        let links = (try? DataStore.shared.context.fetch(FetchDescriptor<Quicklink>())) ?? []
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // "gh swift" → keyword with inline argument.
        if let space = trimmed.firstIndex(of: " ") {
            let keyword = trimmed[..<space].lowercased()
            let argument = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
            if !argument.isEmpty, let link = links.first(where: { $0.keyword.lowercased() == keyword && $0.takesArgument }) {
                var item = Self.item(for: link, score: 2, indices: [])
                item.title = "\(link.name): \(argument)"
                item.requiresArgument = false
                item.actions = Self.actions(for: link, argument: argument)
                return [item]
            }
        }

        let q = FuzzyMatcher.prepareQuery(trimmed)
        return links.compactMap { link in
            if link.keyword.lowercased() == trimmed.lowercased() { return Self.item(for: link, score: 1.6, indices: []) }
            guard let m = MatchTarget(title: link.name, keywords: [link.keyword]).match(q) else { return nil }
            return Self.item(for: link, score: m.score * 0.9, indices: m.matchedIndices)
        }
    }

    func item(withID id: String) -> SearchItem? {
        guard id.hasPrefix("quicklink:"), let uuid = UUID(uuidString: String(id.dropFirst(10))) else { return nil }
        let links = (try? DataStore.shared.context.fetch(FetchDescriptor<Quicklink>(predicate: #Predicate { $0.id == uuid }))) ?? []
        return links.first.map { Self.item(for: $0, score: 0, indices: []) }
    }

    static func item(for link: Quicklink, score: Double, indices: [Int]) -> SearchItem {
        let template = link.urlTemplate
        var item = SearchItem(
            id: "quicklink:\(link.id.uuidString)", title: link.name,
            subtitle: URL(string: template.replacingOccurrences(of: "{query}", with: ""))?.host() ?? template,
            icon: .symbol(link.symbol, tint: .blue), kind: .quicklink, score: score, matchedIndices: indices,
            accessory: link.keyword, actions: actions(for: link, argument: nil)
        )
        if link.takesArgument {
            item.argumentPlaceholder = "Query"
            item.requiresArgument = true
            item.runWithArgument = { argument in
                guard let url = Self.url(template: template, query: argument) else { return .stay }
                NSWorkspace.shared.open(url)
                return .dismiss
            }
        }
        return item
    }

    static func actions(for link: Quicklink, argument: String?) -> [ItemAction] {
        let template = link.urlTemplate
        return [
            ItemAction(id: "open", title: "Open Quicklink", symbol: "safari", shortcut: .returnKey) {
                guard let url = url(template: template, query: argument ?? "") else {
                    return .toast(.failure("Invalid URL", template))
                }
                NSWorkspace.shared.open(url)
                return .dismiss
            },
            ItemAction(id: "copy", title: "Copy URL", symbol: "link", shortcut: KeyHint([.command, .shift], "c")) {
                Paster.copy(url(template: template, query: argument ?? "")?.absoluteString ?? template)
                return .toast(.success("Copied URL"))
            },
            ItemAction(id: "edit", title: "Edit Quicklinks…", symbol: "pencil", shortcut: KeyHint(.command, "e")) {
                SettingsWindowController.shared.show(pane: .quicklinks)
                return .dismiss
            },
        ]
    }

    static func url(template: String, query: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        let encoded = template.contains("github.com/{query}") ? query : (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query)
        return URL(string: template.replacingOccurrences(of: "{query}", with: encoded))
    }
}
