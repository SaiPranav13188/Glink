import AppKit

/// Top clipboard matches in root search; the full history lives in its own view.
@MainActor
final class ClipboardProvider: SearchProvider {
    let id = "clipboard"
    let sectionTitle = "Clipboard"
    let sectionOrder = 4
    let limit = 3

    func results(for query: String) async -> [SearchItem] {
        guard query.count >= 2 else { return [] }
        return ClipboardStore.shared.search(query).prefix(3).map { Self.item(for: $0, score: 0.35) }
    }

    static func item(for entry: ClipboardEntry, score: Double) -> SearchItem {
        let icon: ItemIcon = switch entry.kind {
        case .image: .clipboardImage(entry.id)
        case .file: .path(entry.filePaths.first ?? "/")
        default: .symbol(entry.kind.symbol, tint: .orange)
        }
        return SearchItem(
            id: "clip:\(entry.id.uuidString)",
            title: entry.title,
            subtitle: entry.sourceAppName.map { "Copied from \($0)" },
            icon: icon,
            kind: .clipboard,
            score: score,
            accessory: entry.createdAt.formatted(.relative(presentation: .named)),
            actions: ClipboardActions.make(for: entry)
        )
    }
}

@MainActor
enum ClipboardActions {
    static func make(for entry: ClipboardEntry) -> [ItemAction] {
        let id = entry.id
        let store = ClipboardStore.shared
        return [
            ItemAction(id: "paste", title: "Paste", symbol: "doc.on.clipboard", shortcut: .returnKey) {
                guard let e = store.entry(id: id) else { return .dismiss }
                store.write(e)
                if Paster.canSynthesizeKeys {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Paster.pasteDelay) { Paster.pressCommandV() }
                    return .dismiss
                }
                return .dismissWithHUD("Copied — press ⌘V to paste")
            },
            ItemAction(id: "copy", title: "Copy to Clipboard", symbol: "doc.on.doc", shortcut: .cmdReturn) {
                guard let e = store.entry(id: id) else { return .dismiss }
                store.write(e)
                return .dismissWithHUD("Copied to Clipboard")
            },
            ItemAction(id: "pin", title: entry.isPinned ? "Unpin" : "Pin", symbol: entry.isPinned ? "pin.slash" : "pin",
                       shortcut: KeyHint([.command, .shift], "p")) {
                guard let e = store.entry(id: id) else { return .stay }
                store.togglePin(e)
                return .toast(.success(e.isPinned ? "Pinned" : "Unpinned"))
            },
            ItemAction(id: "delete", title: "Delete Entry", symbol: "trash", shortcut: KeyHint(.control, "x"), style: .destructive) {
                guard let e = store.entry(id: id) else { return .stay }
                store.delete(e)
                return .toast(.success("Deleted Entry"))
            },
            ItemAction(id: "deleteAll", title: "Delete All Unpinned", symbol: "trash.slash",
                       shortcut: KeyHint([.control, .shift], "x"), style: .destructive) {
                store.clearAll()
                return .toast(.success("Cleared Clipboard History"))
            },
        ]
    }
}
