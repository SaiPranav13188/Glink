import Foundation
import SwiftData

enum ClipKind: String, Codable, CaseIterable {
    case text, link, image, file, color

    var title: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        case .color: "Color"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }
}

@Model
final class ClipboardEntry {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var text: String?
    @Attribute(.externalStorage) var imageData: Data?
    var filePaths: [String]
    var sourceBundleID: String?
    var sourceAppName: String?
    var createdAt: Date
    var contentHash: String
    var isPinned: Bool
    var imageWidth: Int
    var imageHeight: Int

    init(kind: ClipKind, text: String? = nil, imageData: Data? = nil, filePaths: [String] = [],
         sourceBundleID: String?, sourceAppName: String?, contentHash: String, imageSize: CGSize = .zero) {
        id = UUID()
        kindRaw = kind.rawValue
        self.text = text
        self.imageData = imageData
        self.filePaths = filePaths
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        createdAt = Date()
        self.contentHash = contentHash
        isPinned = false
        imageWidth = Int(imageSize.width)
        imageHeight = Int(imageSize.height)
    }

    var kind: ClipKind { ClipKind(rawValue: kindRaw) ?? .text }

    /// One-line title for list rows.
    var title: String {
        switch kind {
        case .image: return "Image (\(imageWidth)×\(imageHeight))"
        case .file:
            let names = filePaths.map { ($0 as NSString).lastPathComponent }
            return names.count > 1 ? "\(names[0]) and \(names.count - 1) more" : (names.first ?? "File")
        default:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = t.split(whereSeparator: \.isNewline).first.map(String.init) ?? t
            return String(firstLine.prefix(200))
        }
    }
}

@Model
final class Snippet {
    @Attribute(.unique) var id: UUID
    var name: String
    var keyword: String
    var text: String
    var createdAt: Date
    var useCount: Int

    init(name: String, keyword: String, text: String) {
        id = UUID()
        self.name = name
        self.keyword = keyword
        self.text = text
        createdAt = Date()
        useCount = 0
    }
}

@Model
final class Quicklink {
    @Attribute(.unique) var id: UUID
    var name: String
    var keyword: String
    /// URL template; "{query}" is replaced with the URL-encoded argument.
    var urlTemplate: String
    var symbol: String
    var createdAt: Date

    init(name: String, keyword: String, urlTemplate: String, symbol: String = "link") {
        id = UUID()
        self.name = name
        self.keyword = keyword
        self.urlTemplate = urlTemplate
        self.symbol = symbol
        createdAt = Date()
    }

    var takesArgument: Bool { urlTemplate.contains("{query}") }

    func url(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? query
        return URL(string: urlTemplate.replacingOccurrences(of: "{query}", with: encoded))
    }
}

@Model
final class UsageRecord {
    @Attribute(.unique) var itemID: String
    var count: Int
    var lastUsed: Date

    init(itemID: String) {
        self.itemID = itemID
        count = 0
        lastUsed = Date()
    }
}

/// Owns the SwiftData container (stored in ~/Library/Application Support/Glink).
@MainActor
final class DataStore {
    static let shared = DataStore()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private init() {
        let schema = Schema([ClipboardEntry.self, Snippet.self, Quicklink.self, UsageRecord.self,
                             MCPServerEntry.self, MCPToolPreference.self, MCPAuditRecord.self,
                             UsageEvent.self, SemanticChunk.self])
        let dir = URL.applicationSupportDirectory.appending(path: "Glink", directoryHint: .isDirectory)
        if !Self.isEphemeral { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        // `--ephemeral` (UI tests, benchmarks) keeps everything in memory so runs never touch real data.
        let config = Self.isEphemeral
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: dir.appending(path: "Glink.store"))
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            Log.app.error("Store failed to open, falling back to in-memory: \(error.localizedDescription)")
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
        context.autosaveEnabled = true
        seedDefaultsIfNeeded()
    }

    static var isEphemeral: Bool { ProcessInfo.processInfo.arguments.contains("--ephemeral") }

    func save() {
        do { try context.save() } catch { Log.app.error("Save failed: \(error.localizedDescription)") }
    }

    private func seedDefaultsIfNeeded() {
        let key = "seededDefaults.v1"
        guard Self.isEphemeral || !UserDefaults.standard.bool(forKey: key) else { return }
        if !Self.isEphemeral { UserDefaults.standard.set(true, forKey: key) }
        let links: [Quicklink] = [
            Quicklink(name: "Search Google", keyword: "g", urlTemplate: "https://www.google.com/search?q={query}", symbol: "magnifyingglass"),
            Quicklink(name: "GitHub Repository", keyword: "gh", urlTemplate: "https://github.com/{query}", symbol: "chevron.left.forwardslash.chevron.right"),
            Quicklink(name: "Search YouTube", keyword: "yt", urlTemplate: "https://www.youtube.com/results?search_query={query}", symbol: "play.rectangle"),
            Quicklink(name: "Search Wikipedia", keyword: "wiki", urlTemplate: "https://en.wikipedia.org/w/index.php?search={query}", symbol: "book"),
            Quicklink(name: "Search Maps", keyword: "map", urlTemplate: "maps://?q={query}", symbol: "map"),
        ]
        links.forEach(context.insert)
        let snippets: [Snippet] = [
            Snippet(name: "Today's Date", keyword: ";date", text: "{date:yyyy-MM-dd}"),
            Snippet(name: "Email Sign-off", keyword: ";thx", text: "Thanks,\nSai Pranav"),
            Snippet(name: "Meeting Notes", keyword: ";mtg", text: "## Meeting — {date}\n\nAttendees: \nNotes: {cursor}\n\nAction items:\n- "),
        ]
        snippets.forEach(context.insert)
        save()
    }
}
