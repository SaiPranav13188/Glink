import Accelerate
import Foundation

// MARK: - Chunking

public struct TextChunk: Sendable, Equatable {
    public let index: Int
    public let text: String
}

/// Splits text into ~`size`-character chunks with `overlap` characters shared between neighbors,
/// preferring to break at sentence or line ends so chunks read naturally.
public enum TextChunker {
    public static func chunks(of raw: String, size: Int = 500, overlap: Int = 100) -> [TextChunk] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let chars = Array(text)
        guard chars.count > size else { return [TextChunk(index: 0, text: text)] }

        var out: [TextChunk] = []
        var start = 0
        while start < chars.count {
            var end = min(start + size, chars.count)
            if end < chars.count {
                // Back up to the last sentence/line break in the final third of the window.
                let floor = start + size * 2 / 3
                var i = end
                while i > floor, !(chars[i - 1] == "\n" || ((chars[i - 1] == "." || chars[i - 1] == "!" || chars[i - 1] == "?") && chars[i] == " ")) {
                    i -= 1
                }
                if i > floor { end = i }
            }
            let piece = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(TextChunk(index: out.count, text: piece)) }
            if end >= chars.count { break }
            start = max(end - overlap, start + 1)
        }
        return out
    }
}

// MARK: - Vectors

public enum VectorMath {
    public static func normalized(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = sqrt(norm)
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &na, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &nb, vDSP_Length(b.count))
        let d = sqrt(na) * sqrt(nb)
        return d > 0 ? dot / d : 0
    }

    public static func data(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }

    public static func floats(_ d: Data) -> [Float] {
        d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

// MARK: - In-memory index & hybrid ranking

/// All chunk vectors in one contiguous, pre-normalized matrix so a query is a single
/// matrix–vector multiply (vDSP), well under 100 ms for 10,000+ chunks.
public struct VectorIndex: Sendable {
    public struct Entry: Sendable, Equatable {
        public let path: String
        public let chunkIndex: Int
        public let text: String
        public init(path: String, chunkIndex: Int, text: String) {
            self.path = path
            self.chunkIndex = chunkIndex
            self.text = text
        }
    }

    public private(set) var entries: [Entry] = []
    private var matrix: [Float] = []
    public private(set) var dimension: Int

    public init(dimension: Int) { self.dimension = dimension }

    public var count: Int { entries.count }

    public mutating func add(_ entry: Entry, vector: [Float]) {
        guard vector.count == dimension else { return }
        entries.append(entry)
        matrix.append(contentsOf: VectorMath.normalized(vector))
    }

    public mutating func remove(path: String) {
        let keep = entries.indices.filter { entries[$0].path != path }
        guard keep.count != entries.count else { return }
        var m: [Float] = []
        m.reserveCapacity(keep.count * dimension)
        for i in keep { m.append(contentsOf: matrix[(i * dimension)..<((i + 1) * dimension)]) }
        entries = keep.map { entries[$0] }
        matrix = m
    }

    /// Cosine similarity of the query against every chunk.
    public func similarities(to query: [Float]) -> [Float] {
        guard !entries.isEmpty, query.count == dimension else { return [] }
        let q = VectorMath.normalized(query)
        var out = [Float](repeating: 0, count: entries.count)
        matrix.withUnsafeBufferPointer { m in
            vDSP_mmul(m.baseAddress!, 1, q, 1, &out, 1, vDSP_Length(entries.count), 1, vDSP_Length(dimension))
        }
        return out
    }
}

public struct SemanticHit: Sendable, Equatable {
    public let path: String
    public let score: Double
    public let snippet: String
    /// The query word or best sentence to highlight inside the snippet.
    public let highlight: String?
}

public enum HybridRanker {
    static let stopWords: Set<String> = ["the", "a", "an", "of", "from", "to", "in", "on", "for", "and", "or", "my",
                                         "with", "at", "by", "is", "it", "that", "this", "about", "find", "show"]

    public static func keywords(_ query: String) -> [String] {
        query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }

    /// Share of query keywords that appear in the text (prefix match, so "invoice" finds "invoices").
    public static func keywordOverlap(_ keywords: [String], in text: String) -> Double {
        guard !keywords.isEmpty else { return 0 }
        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let hits = keywords.filter { k in words.contains { $0.hasPrefix(k) || (k.count > 4 && k.hasPrefix($0) && $0.count >= 4) } }
        return Double(hits.count) / Double(keywords.count)
    }

    /// Blends meaning (cosine) with keyword overlap, keeps the best chunk per file, and drops weak matches.
    /// score = 0.7 · cosine + 0.3 · keywordOverlap
    public static func rank(query: String, index: VectorIndex, similarities: [Float],
                            limit: Int = 8, minimumScore: Double = 0.40) -> [SemanticHit] {
        let kw = keywords(query)
        var best: [String: (score: Double, entry: VectorIndex.Entry)] = [:]
        for (i, sim) in similarities.enumerated() {
            let e = index.entries[i]
            let score = 0.7 * Double(sim) + 0.3 * keywordOverlap(kw, in: e.text)
            if score > (best[e.path]?.score ?? -1) { best[e.path] = (score, e) }
        }
        return best.values.filter { $0.score >= minimumScore }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { hit in
                let lower = hit.entry.text.lowercased()
                return SemanticHit(path: hit.entry.path, score: hit.score, snippet: snippet(hit.entry.text, keywords: kw),
                                   highlight: kw.first { lower.contains($0) })
            }
    }

    /// ~140 characters around the first keyword hit (or the start).
    public static func snippet(_ text: String, keywords: [String], length: Int = 140) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let lower = flat.lowercased()
        guard let k = keywords.first(where: { lower.contains($0) }), let r = lower.range(of: k) else {
            return String(flat.prefix(length)) + (flat.count > length ? "…" : "")
        }
        let center = lower.distance(from: lower.startIndex, to: r.lowerBound)
        let start = max(0, center - length / 3)
        let chars = Array(flat)
        let end = min(chars.count, start + length)
        return (start > 0 ? "…" : "") + String(chars[start..<end]) + (end < chars.count ? "…" : "")
    }
}
