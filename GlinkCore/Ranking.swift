import Foundation

/// Turns usage history into a score boost so frequently and recently used items rise to the top.
public enum RankingScore {
    /// Boost in 0...0.7: frequency (log-scaled, capped) plus a recency term that halves every ~2 days.
    public static func boost(count: Int, lastUsed: Date?, now: Date = Date()) -> Double {
        guard count > 0 else { return 0 }
        let frequency = min(0.45, log2(Double(count) + 1) * 0.09)
        var recency = 0.0
        if let lastUsed {
            let hours = max(0, now.timeIntervalSince(lastUsed) / 3600)
            recency = 0.25 * pow(0.5, hours / 48)
        }
        return frequency + recency
    }
}
