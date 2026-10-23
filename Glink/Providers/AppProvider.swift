import AppKit
import GlinkCore

/// Installed applications, scanned from the standard folders and cached in memory.
@MainActor
final class AppProvider: SearchProvider {
    let id = "apps"
    let sectionTitle = "Applications"
    let sectionOrder = 1
    let limit = 8

    struct AppEntry: Sendable {
        let path: String
        let name: String
        let target: MatchTarget
    }

    private var apps: [AppEntry] = [] { didSet { byPath = Dictionary(apps.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }) } }
    private var byPath: [String: AppEntry] = [:]
    private var lastScan: Date = .distantPast
    private var scanTask: Task<Void, Never>?

    nonisolated static let searchRoots = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications", "/System/Library/CoreServices/Applications",
    ]

    init() { refreshIfNeeded(force: true) }

    /// Rescans in the background when the panel opens if the cache is older than a minute.
    func refreshIfNeeded(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastScan) > 60, scanTask == nil else { return }
        scanTask = Task.detached(priority: .utility) {
            let found = Self.scan()
            await MainActor.run {
                self.apps = found
                self.lastScan = Date()
                self.scanTask = nil
            }
        }
    }

    nonisolated static func scan() -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [AppEntry] = []
        func add(_ path: String) {
            let resolved = (path as NSString).resolvingSymlinksInPath
            guard seen.insert(resolved).inserted else { return }
            var name = fm.displayName(atPath: path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            var keywords: [String] = []
            if let bundle = Bundle(path: path) {
                if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, bundleName != name {
                    keywords.append(bundleName)
                }
                if let id = bundle.bundleIdentifier, id == "com.apple.systempreferences" {
                    keywords += ["Preferences", "System Preferences"]
                }
            }
            result.append(AppEntry(path: path, name: name, target: MatchTarget(title: name, keywords: keywords)))
        }
        for root in searchRoots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") { add((root as NSString).appendingPathComponent(item)) }
        }
        add("/System/Library/CoreServices/Finder.app")
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func results(for query: String) async -> [SearchItem] {
        let q = FuzzyMatcher.prepareQuery(query)
        // Score everything (cheap), then build full items only for the best candidates. Usage
        // boosts are included in the cut so a favorite with a weaker text match still makes it.
        let ranking = RankingStore.shared
        let scored = apps.compactMap { app -> (AppEntry, FuzzyMatch, Double)? in
            guard let m = app.target.match(q) else { return nil }
            return (app, m, m.score + ranking.boost(for: "app:\(app.path)"))
        }
        return scored.sorted { $0.2 > $1.2 }.prefix(limit * 2).map { app, m, _ in
            item(for: app, score: m.score, indices: m.matchedIndices)
        }
    }

    func item(withID id: String) -> SearchItem? {
        guard id.hasPrefix("app:") else { return nil }
        let path = String(id.dropFirst(4))
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        if let app = byPath[path] { return item(for: app, score: 0, indices: []) }
        var name = FileManager.default.displayName(atPath: path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return item(for: AppEntry(path: path, name: name, target: MatchTarget(title: name)), score: 0, indices: [])
    }

    private func item(for app: AppEntry, score: Double, indices: [Int]) -> SearchItem {
        SearchItem(id: "app:\(app.path)", title: app.name, subtitle: nil, icon: .path(app.path), kind: .application,
                   score: score, matchedIndices: indices, accessory: "Application",
                   actions: FileActions.make(path: app.path, isApplication: true))
    }
}
