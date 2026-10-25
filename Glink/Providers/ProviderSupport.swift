import AppKit
import GlinkCore
import Quartz

/// Title + extra keywords, prepared once for fast fuzzy matching.
struct MatchTarget: Sendable {
    let title: FuzzyCandidate
    let keywords: [FuzzyCandidate]

    init(title: String, keywords: [String] = []) {
        self.title = FuzzyCandidate(title)
        self.keywords = keywords.map(FuzzyCandidate.init)
    }

    /// Title matches score fully and highlight characters; keyword-only matches score lower.
    func match(_ q: [Character]) -> FuzzyMatch? {
        if let m = FuzzyMatcher.match(q, in: title) { return m }
        let best = keywords.compactMap { FuzzyMatcher.match(q, in: $0) }.max { $0.score < $1.score }
        return best.map { FuzzyMatch(score: $0.score * 0.8, matchedIndices: []) }
    }
}

/// Standard actions for anything that lives on disk.
@MainActor
enum FileActions {
    static func make(path: String, isApplication: Bool) -> [ItemAction] {
        let url = URL(fileURLWithPath: path)
        var actions: [ItemAction] = [
            ItemAction(id: "open", title: isApplication ? "Open Application" : "Open", symbol: "arrow.up.forward.app",
                       shortcut: .returnKey) {
                if isApplication {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config)
                } else {
                    NSWorkspace.shared.open(url)
                }
                return .dismiss
            },
            ItemAction(id: "reveal", title: "Show in Finder", symbol: "folder", shortcut: .cmdReturn) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return .dismiss
            },
            ItemAction(id: "quicklook", title: "Quick Look", symbol: "eye", shortcut: KeyHint(.command, "y")) {
                QuickLookController.shared.toggle(url)
                return .stay
            },
            ItemAction(id: "copyPath", title: "Copy Path", symbol: "doc.on.doc", shortcut: KeyHint([.command, .shift], "c")) {
                Paster.copy(path)
                return .toast(.success("Copied Path", (path as NSString).abbreviatingWithTildeInPath))
            },
            ItemAction(id: "copyName", title: "Copy Name", symbol: "textformat", shortcut: KeyHint([.command, .shift], ".")) {
                Paster.copy(url.deletingPathExtension().lastPathComponent)
                return .toast(.success("Copied Name"))
            },
        ]
        if isApplication {
            if let running = RunningApps.app(atPath: path) {
                actions.append(ItemAction(id: "quit", title: "Quit Application", symbol: "xmark.circle",
                                          shortcut: KeyHint([.command, .option], "q")) {
                    running.terminate()
                    return .toast(.success("Quit \(running.localizedName ?? "App")"))
                })
            }
        } else {
            actions.append(ItemAction(id: "trash", title: "Move to Trash", symbol: "trash",
                                      shortcut: KeyHint(.control, "x"), style: .destructive) {
                .confirm(ConfirmRequest(title: "Move to Trash?", symbol: "trash",
                                        changes: ["\((path as NSString).abbreviatingWithTildeInPath)  →  Trash"],
                                        confirmTitle: "Move to Trash") {
                    do {
                        var inTrash: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &inTrash)
                        if let inTrash = inTrash as URL? {
                            UndoCenter.shared.recordTrash(original: url, inTrash: inTrash)
                            return .stay
                        }
                        return .toast(.success("Moved to Trash", url.lastPathComponent))
                    } catch {
                        return .toast(.failure("Couldn't move to Trash", error.localizedDescription))
                    }
                })
            })
        }
        return actions
    }
}

/// Running apps by bundle path, cached briefly: asking NSWorkspace once per result was the
/// biggest main-thread cost while typing.
@MainActor
enum RunningApps {
    private static var cache: [String: NSRunningApplication] = [:]
    private static var cachedAt = Date.distantPast

    static func app(atPath path: String) -> NSRunningApplication? {
        if Date().timeIntervalSince(cachedAt) > 2 {
            cache = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in
                app.bundleURL.map { ($0.path, app) }
            }, uniquingKeysWith: { a, _ in a })
            cachedAt = Date()
        }
        return cache[path]
    }
}

/// Quick Look for the selected file, driven by the shared QLPreviewPanel.
@MainActor
final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var url: URL?

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func toggle(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        NSApp.activate()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url as NSURL?
    }
}
