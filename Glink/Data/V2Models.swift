import Foundation
import SwiftData

/// One use of a result, with the context it happened in (for context-aware suggestions). Local only.
@Model
final class UsageEvent {
    var itemID: String
    var date: Date
    var hour: Int
    var weekday: Int
    var frontmostApp: String?

    init(itemID: String, date: Date = Date(), frontmostApp: String?) {
        self.itemID = itemID
        self.date = date
        let c = Calendar.current.dateComponents([.hour, .weekday], from: date)
        hour = c.hour ?? 0
        weekday = c.weekday ?? 1
        self.frontmostApp = frontmostApp
    }
}

/// A piece of a file's text and its on-device embedding (semantic search). Never leaves the Mac.
@Model
final class SemanticChunk {
    var path: String
    var chunkIndex: Int
    var text: String
    /// Float32 vector, little-endian.
    var vector: Data
    var modified: Date
    var kind: String

    init(path: String, chunkIndex: Int, text: String, vector: Data, modified: Date, kind: String) {
        self.path = path
        self.chunkIndex = chunkIndex
        self.text = text
        self.vector = vector
        self.modified = modified
        self.kind = kind
    }
}
