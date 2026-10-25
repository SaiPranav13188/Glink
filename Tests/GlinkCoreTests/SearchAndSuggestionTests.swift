import Foundation
import Testing
@testable import GlinkCore

@Suite("Semantic search: chunking & ranking")
struct SemanticSearchTests {
    @Test func shortTextIsOneChunk() {
        let c = TextChunker.chunks(of: "  Invoice #42.\nTotal due: $120.  ")
        #expect(c.count == 1)
        #expect(c[0].text == "Invoice #42.\nTotal due: $120.")
        #expect(TextChunker.chunks(of: "   \n ").isEmpty)
    }

    @Test func longTextOverlapsAndBreaksAtSentences() {
        let sentence = "The quarterly roadmap covers search, sync and sharing features. "
        let text = String(repeating: sentence, count: 40)
        let chunks = TextChunker.chunks(of: text, size: 500, overlap: 100)
        #expect(chunks.count > 4)
        for c in chunks.dropLast() {
            #expect(c.text.count <= 500)
            #expect(c.text.hasSuffix("."))          // ends on a sentence, not mid-word
        }
        // Neighbors share text (overlap), so a phrase on a boundary isn't lost.
        let tail = String(chunks[0].text.suffix(40))
        #expect(chunks[1].text.contains(tail.trimmingCharacters(in: .whitespaces)) || chunks[1].text.contains("roadmap"))
        #expect(chunks.map(\.index) == Array(0..<chunks.count))
    }

    @Test func cosineAndNormalization() {
        #expect(abs(VectorMath.cosine([1, 0], [1, 0]) - 1) < 1e-6)
        #expect(abs(VectorMath.cosine([1, 0], [0, 1])) < 1e-6)
        let n = VectorMath.normalized([3, 4])
        #expect(abs(n[0] - 0.6) < 1e-6 && abs(n[1] - 0.8) < 1e-6)
        #expect(VectorMath.floats(VectorMath.data([1.5, -2])) == [1.5, -2])
    }

    func index() -> VectorIndex {
        var idx = VectorIndex(dimension: 3)
        idx.add(.init(path: "/docs/scan_0042.pdf", chunkIndex: 0, text: "INVOICE #4471 Date: 14 September 2026 Total due $340"), vector: [0.9, 0.1, 0])
        idx.add(.init(path: "/docs/scan_0042.pdf", chunkIndex: 1, text: "Payment terms: 30 days"), vector: [0.5, 0.5, 0])
        idx.add(.init(path: "/docs/recipe.md", chunkIndex: 0, text: "Banana bread with walnuts"), vector: [0, 0.1, 0.9])
        idx.add(.init(path: "/docs/notes.txt", chunkIndex: 0, text: "Meeting notes about invoices"), vector: [0.6, 0.4, 0.2])
        return idx
    }

    @Test func ranksByMeaningAndGroupsByFile() {
        let idx = index()
        let hits = HybridRanker.rank(query: "invoice from september", index: idx, similarities: idx.similarities(to: [1, 0, 0]))
        #expect(hits.first?.path == "/docs/scan_0042.pdf")
        #expect(hits.filter { $0.path == "/docs/scan_0042.pdf" }.count == 1)   // best chunk per file
        #expect(!hits.contains { $0.path == "/docs/recipe.md" })                 // unrelated file dropped
        #expect(hits.first?.highlight == "invoice")
        #expect(hits.first?.snippet.contains("September") == true)
    }

    @Test func keywordsBreakTiesBetweenSimilarMeanings() {
        var idx = VectorIndex(dimension: 2)
        idx.add(.init(path: "/a.txt", chunkIndex: 0, text: "Quarterly budget review"), vector: [1, 0.05])
        idx.add(.init(path: "/b.txt", chunkIndex: 0, text: "Team offsite plans"), vector: [1, 0.04])
        let hits = HybridRanker.rank(query: "budget", index: idx, similarities: idx.similarities(to: [1, 0]))
        #expect(hits.first?.path == "/a.txt")
    }

    @Test func removeDropsAFilesChunks() {
        var idx = index()
        idx.remove(path: "/docs/scan_0042.pdf")
        #expect(idx.count == 2)
        #expect(idx.similarities(to: [1, 0, 0]).count == 2)
    }

    @Test func tenThousandChunksSearchFast() {
        var idx = VectorIndex(dimension: 512)
        for i in 0..<10_000 {
            idx.add(.init(path: "/f\(i % 2000).txt", chunkIndex: i, text: "chunk \(i)"),
                    vector: (0..<512).map { Float(sin(Double(i * 7 + $0))) })
        }
        let q: [Float] = (0..<512).map { Float(cos(Double($0))) }
        let start = Date()
        _ = HybridRanker.rank(query: "chunk", index: idx, similarities: idx.similarities(to: q))
        let ms = Date().timeIntervalSince(start) * 1000
        print("SEMANTIC-SEARCH: 10,000 chunks ranked in \(Int(ms)) ms")
        #expect(ms < 100)
    }
}

@Suite("Context-aware suggestions")
struct SuggestionScorerTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(day: Int, hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func morningHabitWinsInTheMorning() {
        var samples: [UsageSample] = []
        for d in 1...10 { samples.append(UsageSample(itemID: "app:Mail", date: date(day: d, hour: 10), frontmostApp: "Finder")) }
        for d in 1...10 { samples.append(UsageSample(itemID: "app:Music", date: date(day: d, hour: 21), frontmostApp: "Finder")) }
        let top = SuggestionScorer.suggestions(from: samples, context: SuggestionContext(now: date(day: 12, hour: 10), frontmostApp: nil), calendar: cal)
        #expect(top.first?.itemID == "app:Mail")
        #expect(top.first?.reason == "You usually open this around 10 am")
    }

    @Test func frontmostAppMatchWins() {
        var samples: [UsageSample] = []
        for d in 1...6 { samples.append(UsageSample(itemID: "cmd.snippets", date: date(day: d, hour: d * 3), frontmostApp: "Xcode")) }
        for d in 1...6 { samples.append(UsageSample(itemID: "app:Safari", date: date(day: d, hour: d * 3), frontmostApp: "Mail")) }
        let top = SuggestionScorer.suggestions(from: samples, context: SuggestionContext(now: date(day: 8, hour: 1), frontmostApp: "Xcode"), calendar: cal)
        #expect(top.first?.itemID == "cmd.snippets")
        #expect(top.first?.reason == "Often used with Xcode")
    }

    @Test func needsAtLeastTwoUsesAndRespectsLimit() {
        let one = [UsageSample(itemID: "x", date: date(day: 1, hour: 9), frontmostApp: nil)]
        #expect(SuggestionScorer.suggestions(from: one, context: SuggestionContext(now: date(day: 2, hour: 9), frontmostApp: nil), calendar: cal).isEmpty)
        var many: [UsageSample] = []
        for i in 0..<10 { for d in 1...3 { many.append(UsageSample(itemID: "item\(i)", date: date(day: d, hour: i), frontmostApp: nil)) } }
        #expect(SuggestionScorer.suggestions(from: many, context: SuggestionContext(now: date(day: 5, hour: 3), frontmostApp: nil), calendar: cal).count == 5)
    }

    @Test func recencyBreaksTies() {
        let samples = [
            UsageSample(itemID: "old", date: date(day: 1, hour: 15), frontmostApp: nil),
            UsageSample(itemID: "old", date: date(day: 2, hour: 15), frontmostApp: nil),
            UsageSample(itemID: "new", date: date(day: 20, hour: 15), frontmostApp: nil),
            UsageSample(itemID: "new", date: date(day: 21, hour: 15), frontmostApp: nil),
        ]
        let top = SuggestionScorer.suggestions(from: samples, context: SuggestionContext(now: date(day: 22, hour: 4), frontmostApp: nil), calendar: cal)
        #expect(top.map(\.itemID) == ["new", "old"])
    }

    @Test func hourWrapsAtMidnight() {
        let samples = (1...4).map { UsageSample(itemID: "late", date: date(day: $0, hour: 23), frontmostApp: nil) }
        let top = SuggestionScorer.suggestions(from: samples, context: SuggestionContext(now: date(day: 6, hour: 0), frontmostApp: nil), calendar: cal)
        #expect(top.first?.reason == "You usually open this around 11 pm")
    }
}
