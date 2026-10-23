import AppKit
import GlinkCore

/// Window snapping commands (left/right halves, thirds, maximize…).
@MainActor
final class WindowCommandProvider: SearchProvider {
    let id = "window"
    let sectionTitle = "Window Management"
    let sectionOrder = 5
    let limit = 6

    private let targets: [(WindowCommand, MatchTarget)] = WindowCommand.allCases.map {
        ($0, MatchTarget(title: $0.title, keywords: [$0.keywords, "window " + $0.title]))
    }

    func results(for query: String) async -> [SearchItem] {
        let prepared = FuzzyMatcher.prepareQuery(query)
        return targets.compactMap { command, target in
            guard let m = target.match(prepared) else { return nil }
            return Self.item(for: command, score: m.score * 0.95, indices: m.matchedIndices)
        }
    }

    func item(withID id: String) -> SearchItem? {
        guard id.hasPrefix("window."), let command = WindowCommand(rawValue: String(id.dropFirst(7))) else { return nil }
        return Self.item(for: command, score: 0, indices: [])
    }

    func suggestions() -> [SearchItem] {
        [WindowCommand.leftHalf, .maximize].map { Self.item(for: $0, score: 0, indices: []) }
    }

    static func item(for command: WindowCommand, score: Double, indices: [Int]) -> SearchItem {
        SearchItem(
            id: "window.\(command.rawValue)", title: command.title, subtitle: nil,
            icon: .symbol(command.symbol, tint: .indigo), kind: .window, score: score, matchedIndices: indices,
            accessory: "Window Management",
            actions: [ItemAction(id: "run", title: "Run Command", symbol: command.symbol, shortcut: .returnKey) {
                guard PermissionsManager.shared.isAccessibilityTrusted else {
                    return .toast(.failure("Accessibility access needed", "Window snapping moves other apps' windows.",
                                           retry: { PermissionsManager.shared.requestAccessibility() }))
                }
                let app = PanelController.shared.previousApp
                // Let the panel's exit animation start, then snap.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    if case .failure(let error) = WindowManager.shared.perform(command, in: app) {
                        HUDController.shared.show(error.message, symbol: "exclamationmark.triangle.fill")
                    }
                }
                return .dismiss
            }]
        )
    }
}
