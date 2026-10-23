import Foundation
import GlinkCore
import SwiftData

/// Tracks how often and how recently each item is used, so favorites rise to the top.
@MainActor
final class RankingStore {
    static let shared = RankingStore()

    private var cache: [String: (count: Int, lastUsed: Date)] = [:]
    private var context: ModelContext { DataStore.shared.context }

    private init() { reload() }

    func reload() {
        let records = (try? context.fetch(FetchDescriptor<UsageRecord>())) ?? []
        cache = Dictionary(records.map { ($0.itemID, ($0.count, $0.lastUsed)) }, uniquingKeysWith: { a, _ in a })
    }

    func boost(for id: String) -> Double {
        guard let entry = cache[id] else { return 0 }
        return RankingScore.boost(count: entry.count, lastUsed: entry.lastUsed)
    }

    func recordUse(of id: String) {
        let descriptor = FetchDescriptor<UsageRecord>(predicate: #Predicate { $0.itemID == id })
        let record = (try? context.fetch(descriptor).first) ?? {
            let r = UsageRecord(itemID: id)
            context.insert(r)
            return r
        }()
        record.count += 1
        record.lastUsed = Date()
        cache[id] = (record.count, record.lastUsed)
        DataStore.shared.save()
    }

    /// Most recently used item IDs, newest first.
    func recentIDs(limit: Int) -> [String] {
        cache.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(limit).map(\.key)
    }

    func reset() {
        try? context.delete(model: UsageRecord.self)
        DataStore.shared.save()
        cache = [:]
        AppSettings.shared.rankingVersion += 1
    }
}
