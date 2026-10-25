import AppKit
import GlinkCore
import SwiftData

/// "Semantic" results: files whose contents match the query's meaning. Streams in after name matches.
@MainActor
final class SemanticProvider: SearchProvider {
    let id = "semantic"
    let sectionTitle = "By Meaning"
    let sectionOrder = 4
    let limit = 5
    let isSlow = true

    func results(for query: String) async -> [SearchItem] {
        let hits = await SemanticIndexer.shared.search(query)
        return hits.map { hit in
            var item = SearchItem(
                id: "file:\(hit.path)", title: (hit.path as NSString).lastPathComponent, subtitle: hit.snippet,
                icon: .path(hit.path), kind: .file,
                // Below name matches on purpose: an exact name still wins (hybrid ranking).
                score: hit.score * 0.8, accessory: "By meaning",
                actions: FileActions.make(path: hit.path, isApplication: false))
            item.subtitleHighlight = hit.highlight
            item.matchedByMeaning = true
            return item
        }
    }
}

/// Context-aware suggestions for the empty search field (scoring lives in GlinkCore.SuggestionScorer).
@MainActor
enum SuggestionsEngine {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "suggestionsEnabled") as? Bool ?? true }

    static func record(itemID: String, frontmostApp: String?) {
        DataStore.shared.context.insert(UsageEvent(itemID: itemID, frontmostApp: frontmostApp))
        DataStore.shared.save()
    }

    static func suggestions(frontmostApp: String?) -> [Suggestion] {
        guard enabled else { return [] }
        let since = Date().addingTimeInterval(-60 * 86400)
        var d = FetchDescriptor<UsageEvent>(predicate: #Predicate { $0.date > since }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 5000
        let samples = ((try? DataStore.shared.context.fetch(d)) ?? []).map {
            UsageSample(itemID: $0.itemID, date: $0.date, frontmostApp: $0.frontmostApp)
        }
        return SuggestionScorer.suggestions(from: samples, context: SuggestionContext(frontmostApp: frontmostApp))
    }

    static func resetLearning() {
        try? DataStore.shared.context.delete(model: UsageEvent.self)
        DataStore.shared.save()
    }
}
