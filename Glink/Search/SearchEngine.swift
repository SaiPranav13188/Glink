import AppKit
import GlinkCore

/// Every source of results implements this, which keeps features independent.
@MainActor
protocol SearchProvider: AnyObject, Sendable {
    var id: String { get }
    var sectionTitle: String { get }
    /// Tie-breaker when two sections score the same; lower comes first.
    var sectionOrder: Int { get }
    /// Max rows this provider contributes to root search.
    var limit: Int { get }
    /// Slow providers (file search) stream in after the fast ones are already on screen.
    var isSlow: Bool { get }
    func results(for query: String) async -> [SearchItem]
    /// Rebuilds an item from a stored ID, for the "Recent" section.
    func item(withID id: String) -> SearchItem?
    /// Items shown under "Suggestions" when the query is empty.
    func suggestions() -> [SearchItem]
}

extension SearchProvider {
    var isSlow: Bool { false }
    var limit: Int { 8 }
    func item(withID id: String) -> SearchItem? { nil }
    func suggestions() -> [SearchItem] { [] }
}

struct SearchSnapshot {
    var sections: [ResultSection]
    var pendingSlowProviders: Bool
    var isFallback: Bool
}

@MainActor
final class SearchEngine {
    let providers: [any SearchProvider]
    let ranking = RankingStore.shared

    init(providers: [any SearchProvider]) {
        self.providers = providers
    }

    /// Runs on every keystroke. Fast providers publish immediately; slow ones merge in when ready.
    func search(_ rawQuery: String, publish: (SearchSnapshot) -> Void) async {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            publish(SearchSnapshot(sections: emptyQuerySections(), pendingSlowProviders: false, isFallback: false))
            return
        }

        var collected: [String: [SearchItem]] = [:]
        for provider in providers where !provider.isSlow {
            collected[provider.id] = await provider.results(for: query)
            if Task.isCancelled { return }
        }
        let slow = providers.filter(\.isSlow)
        publish(snapshot(from: collected, query: query, pending: !slow.isEmpty))

        guard !slow.isEmpty else { return }
        for provider in slow {
            let items = await provider.results(for: query)
            if Task.isCancelled { return }
            collected[provider.id] = items
        }
        publish(snapshot(from: collected, query: query, pending: false))
    }

    private func snapshot(from collected: [String: [SearchItem]], query: String, pending: Bool) -> SearchSnapshot {
        var sections: [(section: ResultSection, best: Double, order: Int, slow: Bool)] = []
        for provider in providers {
            guard var items = collected[provider.id], !items.isEmpty else { continue }
            for i in items.indices { items[i].score += ranking.boost(for: items[i].id) }
            items.sort { $0.score > $1.score }
            items = Array(items.prefix(provider.limit))
            sections.append((ResultSection(id: provider.id, title: provider.sectionTitle, items: items),
                             items.first?.score ?? 0, provider.sectionOrder, provider.isSlow))
        }
        // Calculator stays pinned to the top and streamed-in files go last, so late results never
        // shove the selection around; other sections order by their best match.
        sections.sort {
            if $0.section.id == "calculator" { return true }
            if $1.section.id == "calculator" { return false }
            if $0.slow != $1.slow { return !$0.slow }
            if abs($0.best - $1.best) > 0.05 { return $0.best > $1.best }
            return $0.order < $1.order
        }
        // The same file can match by name and by meaning: keep the first (name) row only.
        var seen = Set<String>()
        let result = sections.map(\.section).compactMap { section -> ResultSection? in
            var s = section
            s.items = s.items.filter { seen.insert($0.id).inserted }
            return s.items.isEmpty ? nil : s
        }
        if result.isEmpty && !pending {
            return SearchSnapshot(sections: [fallbackSection(for: query)], pendingSlowProviders: false, isFallback: true)
        }
        return SearchSnapshot(sections: result, pendingSlowProviders: pending, isFallback: false)
    }

    // MARK: Empty query: Recent + Suggestions

    private func emptyQuerySections() -> [ResultSection] {
        var seen = Set<String>()
        // Context-aware suggestions, each with a reason under it.
        var suggested: [SearchItem] = []
        for s in SuggestionsEngine.suggestions(frontmostApp: PanelController.shared.previousApp?.localizedName) {
            guard let item = providers.lazy.compactMap({ $0.item(withID: s.itemID) }).first else { continue }
            var row = item
            row.subtitle = s.reason
            suggested.append(row)
            seen.insert(s.itemID)
        }
        var recent: [SearchItem] = []
        for id in ranking.recentIDs(limit: 12) where !seen.contains(id) {
            guard recent.count < 5 else { break }
            for provider in providers {
                if let item = provider.item(withID: id) {
                    recent.append(item)
                    seen.insert(id)
                    break
                }
            }
        }
        var suggestions: [SearchItem] = []
        for provider in providers {
            for item in provider.suggestions() where !seen.contains(item.id) {
                suggestions.append(item)
                seen.insert(item.id)
            }
        }
        var sections: [ResultSection] = []
        if !suggested.isEmpty { sections.append(ResultSection(id: "suggested", title: "Suggested", items: suggested)) }
        if !recent.isEmpty { sections.append(ResultSection(id: "recent", title: "Recent", items: recent)) }
        sections.append(ResultSection(id: "suggestions", title: suggested.isEmpty ? "Suggestions" : "Quick Actions", items: suggestions))
        return sections
    }

    // MARK: No results: never a dead end

    func fallbackSection(for query: String) -> ResultSection {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let web = SearchItem(
            id: "fallback.web", title: "Search the web for “\(query)”", subtitle: "Google",
            icon: .symbol("globe", tint: .blue), kind: .web, accessory: "Web",
            actions: [ItemAction(id: "open", title: "Search the Web", symbol: "globe", shortcut: .returnKey) {
                if let url = URL(string: "https://www.google.com/search?q=\(encoded)") { NSWorkspace.shared.open(url) }
                return .dismiss
            }]
        )
        let files = SearchItem(
            id: "fallback.spotlight", title: "Search files for “\(query)”", subtitle: "Spotlight",
            icon: .symbol("doc.text.magnifyingglass", tint: .gray), kind: .file, accessory: "Files",
            actions: [ItemAction(id: "open", title: "Search with Spotlight", symbol: "magnifyingglass", shortcut: .returnKey) {
                NSWorkspace.shared.showSearchResults(forQueryString: query)
                return .dismiss
            }]
        )
        let ai = SearchItem(
            id: "fallback.ai", title: "Ask AI “\(query)”", subtitle: "On-device · Private",
            icon: .symbol("sparkles", tint: .purple), kind: .ai, accessory: "AI",
            actions: [ItemAction(id: "open", title: "Ask AI", symbol: "sparkles", shortcut: .returnKey) {
                .push(.ai(AIRequest(command: .ask, input: query)))
            }]
        )
        let items = AIService.availability.isAvailable ? [web, files, ai] : [web, files]
        return ResultSection(id: "fallback", title: "Use “\(query)” with…", items: items)
    }
}
