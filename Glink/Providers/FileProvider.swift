import AppKit
import GlinkCore

/// Spotlight-index file search. Streams in after the fast providers; the previous query
/// is cancelled on every keystroke.
@MainActor
final class FileProvider: SearchProvider {
    let id = "files"
    let sectionTitle = "Files"
    let sectionOrder = 3
    let limit = 6
    let isSlow = true

    private let searcher = MetadataSearcher()

    func results(for query: String) async -> [SearchItem] {
        guard AppSettings.shared.fileSearchEnabled, query.count >= 2 else { return [] }
        let hits = await searcher.search(query)
        let q = FuzzyMatcher.prepareQuery(query)
        return hits.compactMap { hit in
            let m = FuzzyMatcher.match(q, in: FuzzyCandidate(hit.name))
            // Recently opened files get a small nudge.
            let recency = hit.lastUsed.map { max(0, 0.15 - Date().timeIntervalSince($0) / 86400 / 30 * 0.15) } ?? 0
            return makeItem(path: hit.path, name: hit.name, isFolder: hit.isFolder,
                            score: (m?.score ?? 0.2) * 0.9 + recency, indices: m?.matchedIndices ?? [])
        }
    }

    func item(withID id: String) -> SearchItem? {
        guard id.hasPrefix("file:") else { return nil }
        let path = String(id.dropFirst(5))
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        return makeItem(path: path, name: (path as NSString).lastPathComponent, isFolder: isDir.boolValue, score: 0, indices: [])
    }

    private func makeItem(path: String, name: String, isFolder: Bool, score: Double, indices: [Int]) -> SearchItem {
        let parent = ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        return SearchItem(id: "file:\(path)", title: name, subtitle: parent, icon: .path(path),
                          kind: isFolder ? .folder : .file, score: score, matchedIndices: indices,
                          accessory: isFolder ? "Folder" : "File",
                          actions: FileActions.make(path: path, isApplication: false))
    }
}

struct MetadataHit: Sendable {
    let path: String
    let name: String
    let isFolder: Bool
    let lastUsed: Date?
}

/// Async wrapper over NSMetadataQuery (which must live on a run-loop thread — main here).
///
/// NSMetadataQuery can spin nested run loops. If that happens inside a Swift task's job,
/// SwiftUI may render while the task is still "current" and the main-actor executor checks
/// misfire. So every query call happens in plain main-queue blocks and notification handlers;
/// the async `search` only polls for the finished result.
@MainActor
final class MetadataSearcher {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var finished: (generation: Int, hits: [MetadataHit])?

    static let excludedFragments = ["/Library/", "/.", "/node_modules/", ".app/", "/DerivedData/", "/.Trash/"]

    func search(_ text: String) async -> [MetadataHit] {
        let words = text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        generation += 1
        let myGeneration = generation
        DispatchQueue.main.async {
            self.stop()   // cancel the previous keystroke's query
            if !words.isEmpty { self.start(words: words, generation: myGeneration) }
        }
        guard !words.isEmpty else { return [] }

        // Don't let a slow index hold results hostage: collect what we have after 700 ms.
        let deadline = Date().addingTimeInterval(0.7)
        while finished?.generation != myGeneration {
            try? await Task.sleep(for: .milliseconds(20))
            if Task.isCancelled || myGeneration != generation { return [] }
            if Date() > deadline {
                DispatchQueue.main.async { self.finish(generation: myGeneration) }
            }
        }
        return finished?.hits ?? []
    }

    private func start(words: [String], generation: Int) {
        guard generation == self.generation else { return }
        let q = NSMetadataQuery()
        // NSMetadataQuery rejects an AND-compound with a single subpredicate.
        let predicates = words.map { NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", $0) }
        q.predicate = predicates.count == 1 ? predicates[0] : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        q.notificationBatchingInterval = 0.1
        query = q
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(generation: generation) }
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryGatheringProgress, object: q, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, (self.query?.resultCount ?? 0) >= 120 { self.finish(generation: generation) }
            }
        })
        q.start()
    }

    private func finish(generation: Int) {
        guard generation == self.generation, finished?.generation != generation, let q = query else { return }
        q.disableUpdates()
        var hits: [MetadataHit] = []
        for i in 0..<min(q.resultCount, 200) {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if Self.excludedFragments.contains(where: path.contains) || path.hasSuffix(".app") { continue }
            let type = item.value(forAttribute: "kMDItemContentType") as? String
            let lastUsed = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
            hits.append(MetadataHit(path: path, name: (path as NSString).lastPathComponent,
                                    isFolder: type == "public.folder", lastUsed: lastUsed))
            if hits.count >= 40 { break }
        }
        finished = (generation, hits)
        stop()
    }

    private func stop() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
