import Foundation

/// Result of matching a query against a candidate string.
public struct FuzzyMatch: Sendable, Equatable {
    /// Higher is better. Roughly 0...1.5; exact matches score highest.
    public let score: Double
    /// Indices into `Array(candidate)` (Character offsets) that matched the query.
    public let matchedIndices: [Int]

    public init(score: Double, matchedIndices: [Int]) {
        self.score = score
        self.matchedIndices = matchedIndices
    }
}

/// A candidate string prepared once so repeated matching on every keystroke stays cheap.
public struct FuzzyCandidate: Sendable, Hashable {
    public let original: String
    let folded: [Character]
    let boundaryBonus: [Double]

    public init(_ string: String) {
        original = string
        let chars = Array(string)
        folded = chars.map { FuzzyMatcher.fold($0) }
        var bonus = [Double](repeating: 0, count: chars.count)
        for i in chars.indices {
            if i == 0 {
                bonus[i] = FuzzyMatcher.Weights.startBonus
                continue
            }
            let prev = chars[i - 1], cur = chars[i]
            if FuzzyMatcher.isSeparator(prev) {
                bonus[i] = FuzzyMatcher.Weights.wordBoundaryBonus
            } else if prev.isLowercase && cur.isUppercase {
                bonus[i] = FuzzyMatcher.Weights.camelBonus
            } else if prev.isLetter && cur.isNumber {
                bonus[i] = FuzzyMatcher.Weights.camelBonus * 0.5
            }
        }
        boundaryBonus = bonus
    }
}

public enum FuzzyMatcher {
    enum Weights {
        static let match = 1.0
        static let consecutive = 1.6
        static let startBonus = 2.2
        static let wordBoundaryBonus = 1.6
        static let camelBonus = 1.2
        static let gapPenalty = 0.06
        static let leadingGapPenalty = 0.03
        static let maxLeadingPenalty = 0.6
    }

    static let separators: Set<Character> = [" ", "-", "_", ".", "/", "\\", ":", "(", ")", "[", "]", "+", "&", ","]

    static func isSeparator(_ c: Character) -> Bool { separators.contains(c) }

    static func fold(_ c: Character) -> Character {
        let s = String(c).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return s.first ?? c
    }

    /// Prepares a query (folded, whitespace-trimmed characters).
    public static func prepareQuery(_ query: String) -> [Character] {
        Array(query.trimmingCharacters(in: .whitespacesAndNewlines)).map(fold)
    }

    public static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        match(prepareQuery(query), in: FuzzyCandidate(candidate))
    }

    /// Dynamic-programming subsequence match. Picks the alignment with the best score,
    /// rewarding consecutive runs and characters at word / camelCase boundaries.
    public static func match(_ q: [Character], in candidate: FuzzyCandidate) -> FuzzyMatch? {
        let c = candidate.folded
        let m = q.count, n = c.count
        guard m > 0 else { return FuzzyMatch(score: 0, matchedIndices: []) }
        guard m <= n else { return nil }

        // Quick reject: every query character must appear in order.
        var probe = 0
        for ch in c where probe < m && ch == q[probe] { probe += 1 }
        guard probe == m else { return nil }

        let negInf = -Double.greatestFiniteMagnitude
        // score[i][j]: best score with q[i] matched at c[j]
        var score = [[Double]](repeating: [Double](repeating: negInf, count: n), count: m)
        var back = [[Int]](repeating: [Int](repeating: -1, count: n), count: m)

        for j in 0..<n where c[j] == q[0] {
            let leading = min(Weights.maxLeadingPenalty, Double(j) * Weights.leadingGapPenalty)
            score[0][j] = Weights.match + candidate.boundaryBonus[j] - leading
        }

        if m > 1 {
            for i in 1..<m {
                // Running max of score[i-1][k] + gap*k for k < j-1 (non-adjacent predecessors).
                var bestPrev = negInf
                var bestPrevIndex = -1
                for j in i..<n {
                    let k = j - 2
                    if k >= 0, score[i - 1][k] > negInf {
                        let v = score[i - 1][k] + Weights.gapPenalty * Double(k)
                        if v > bestPrev { bestPrev = v; bestPrevIndex = k }
                    }
                    guard c[j] == q[i] else { continue }
                    var best = negInf
                    var from = -1
                    let adjacent = score[i - 1][j - 1]
                    if adjacent > negInf {
                        best = adjacent + Weights.consecutive
                        from = j - 1
                    }
                    if bestPrev > negInf {
                        let gapped = bestPrev - Weights.gapPenalty * Double(j - 1)
                        if gapped > best { best = gapped; from = bestPrevIndex }
                    }
                    guard from >= 0 else { continue }
                    score[i][j] = best + Weights.match + candidate.boundaryBonus[j]
                    back[i][j] = from
                }
            }
        }

        var endIndex = -1
        var endScore = negInf
        for j in 0..<n where score[m - 1][j] > endScore {
            endScore = score[m - 1][j]
            endIndex = j
        }
        guard endIndex >= 0 else { return nil }

        var indices = [Int](repeating: 0, count: m)
        var j = endIndex
        for i in stride(from: m - 1, through: 0, by: -1) {
            indices[i] = j
            j = back[i][j]
        }

        // Normalize to roughly 0...1 relative to a perfect prefix run.
        let ideal = Weights.match * Double(m) + Weights.startBonus + Weights.consecutive * Double(m - 1)
        var normalized = endScore / ideal
        // Mild preference for shorter candidates (tighter matches).
        normalized -= min(0.15, Double(n - m) * 0.004)
        if m == n { normalized += 0.5 }                                  // exact
        else if indices.last == m - 1 { normalized += 0.2 }              // prefix
        return FuzzyMatch(score: normalized, matchedIndices: indices)
    }
}
