import Foundation

/// One past use of an item, with its context. Recorded locally only.
public struct UsageSample: Sendable, Equatable {
    public let itemID: String
    public let date: Date
    public let frontmostApp: String?

    public init(itemID: String, date: Date, frontmostApp: String?) {
        self.itemID = itemID
        self.date = date
        self.frontmostApp = frontmostApp
    }
}

public struct SuggestionContext: Sendable {
    public let now: Date
    public let frontmostApp: String?
    public init(now: Date = Date(), frontmostApp: String?) {
        self.now = now
        self.frontmostApp = frontmostApp
    }
}

public struct Suggestion: Sendable, Equatable {
    public let itemID: String
    public let score: Double
    public let reason: String
}

/// Context-aware suggestions for the empty search field.
///
///     score = 1.0 · frequency      log2(1 + uses) / log2(1 + most uses of any item)
///           + 1.0 · recency        e^(−hours since last use / 72)
///           + 1.5 · timeOfDay      share of uses within ±1 hour of now (wrapping at midnight)
///           + 1.5 · appMatch       share of uses while the current frontmost app was in front
///           + 0.5 · weekday        share of uses on today's weekday
///
/// Items need at least 2 uses. The reason shown is the strongest *contextual* signal.
public enum SuggestionScorer {
    public static let minimumUses = 2

    public static func suggestions(from samples: [UsageSample], context: SuggestionContext,
                                   calendar: Calendar = .current, limit: Int = 5) -> [Suggestion] {
        let byItem = Dictionary(grouping: samples, by: \.itemID).filter { $0.value.count >= minimumUses }
        guard let maxUses = byItem.values.map(\.count).max() else { return [] }
        let nowHour = calendar.component(.hour, from: context.now)
        let nowWeekday = calendar.component(.weekday, from: context.now)

        return byItem.map { id, uses -> Suggestion in
            let n = Double(uses.count)
            let frequency = log2(1 + n) / log2(1 + Double(maxUses))
            let last = uses.map(\.date).max() ?? .distantPast
            let recency = exp(-max(0, context.now.timeIntervalSince(last)) / 3600 / 72)
            let hours = uses.map { calendar.component(.hour, from: $0.date) }
            let nearNow = hours.filter { h in let d = abs(h - nowHour); return min(d, 24 - d) <= 1 }.count
            let timeOfDay = Double(nearNow) / n
            let appUses = context.frontmostApp.map { app in uses.filter { $0.frontmostApp == app }.count } ?? 0
            let appMatch = Double(appUses) / n
            let weekday = Double(uses.filter { calendar.component(.weekday, from: $0.date) == nowWeekday }.count) / n

            let score = 1.0 * frequency + 1.0 * recency + 1.5 * timeOfDay + 1.5 * appMatch + 0.5 * weekday

            let reason: String
            if appMatch >= 0.5, let app = context.frontmostApp, appMatch >= timeOfDay {
                reason = "Often used with \(app)"
            } else if timeOfDay >= 0.5 {
                reason = "You usually open this around \(typicalHour(hours))"
            } else if frequency >= 0.8 {
                reason = "One of your most used"
            } else if recency >= 0.7 {
                reason = "Used recently"
            } else {
                reason = "Used \(uses.count) times"
            }
            return Suggestion(itemID: id, score: score, reason: reason)
        }
        .sorted { ($0.score, $1.itemID) > ($1.score, $0.itemID) }
        .prefix(limit)
        .map { $0 }
    }

    /// The most common hour, as "10 am" / "3 pm".
    static func typicalHour(_ hours: [Int]) -> String {
        let h = Dictionary(grouping: hours, by: { $0 }).max { ($0.value.count, -$0.key) < ($1.value.count, -$1.key) }?.key ?? 9
        switch h {
        case 0: return "midnight"
        case 12: return "noon"
        case 1..<12: return "\(h) am"
        default: return "\(h - 12) pm"
        }
    }
}
