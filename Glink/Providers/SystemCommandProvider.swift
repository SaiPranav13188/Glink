import AppKit
import GlinkCore

/// Built-in commands: Clipboard History, Settings, Sleep, appearance toggle, Quit…
@MainActor
final class SystemCommandProvider: SearchProvider {
    let id = "commands"
    let sectionTitle = "Commands"
    let sectionOrder = 2
    let limit = 6

    struct Command {
        let id: String
        let title: String
        let subtitle: String?
        let symbol: String
        let tint: SymbolTint
        let keywords: [String]
        let suggested: Bool
        let run: @MainActor () async -> ActionOutcome
    }

    private lazy var commands: [Command] = [
        Command(id: "clipboard", title: "Clipboard History", subtitle: "Search everything you've copied",
                symbol: "doc.on.clipboard", tint: .orange, keywords: ["paste copy history"], suggested: true) { .push(.clipboard) },
        Command(id: "snippets", title: "Search Snippets", subtitle: nil, symbol: "text.quote", tint: .pink,
                keywords: ["text expansion templates"], suggested: false) { .push(.snippets) },
        Command(id: "newSnippet", title: "Create Snippet", subtitle: nil, symbol: "plus.square.on.square", tint: .pink,
                keywords: ["new add snippet"], suggested: false) {
            SettingsWindowController.shared.show(pane: .snippets, createNew: true)
            return .dismiss
        },
        Command(id: "newQuicklink", title: "Create Quicklink", subtitle: nil, symbol: "link.badge.plus", tint: .blue,
                keywords: ["new add bookmark url"], suggested: false) {
            SettingsWindowController.shared.show(pane: .quicklinks, createNew: true)
            return .dismiss
        },
        Command(id: "recentActions", title: "Recent Actions", subtitle: "Undo window snaps, trashed files and more",
                symbol: "arrow.uturn.backward", tint: .blue, keywords: ["undo history revert"], suggested: false) {
            .push(.recentActions)
        },
        Command(id: "notes", title: "Floating Notes", subtitle: "Toggle the always-on-top notes window", symbol: "note.text",
                tint: .yellow, keywords: ["scratchpad jot memo sticky"], suggested: false) {
            FloatingNotesController.shared.toggle()
            return .dismiss
        },
        Command(id: "scriptsFolder", title: "Open Script Commands Folder", subtitle: "Add your own commands as scripts",
                symbol: "terminal", tint: .gray, keywords: ["extensions scripts custom"], suggested: false) {
            ScriptRunner.ensureFolder()
            NSWorkspace.shared.open(ScriptRunner.folder)
            return .dismiss
        },
        Command(id: "miniMode", title: "Toggle Menu Bar Mini Mode", subtitle: "Click the menu bar icon to search",
                symbol: "menubar.rectangle", tint: .blue, keywords: ["menu bar popover compact"], suggested: false) {
            AppSettings.shared.menuBarMiniMode.toggle()
            return .toast(.success(AppSettings.shared.menuBarMiniMode ? "Mini mode on" : "Mini mode off"))
        },
        Command(id: "settings", title: "Glink Settings", subtitle: nil, symbol: "gearshape", tint: .gray,
                keywords: ["preferences config hotkey"], suggested: true) {
            SettingsWindowController.shared.show()
            return .dismiss
        },
        Command(id: "onboarding", title: "Welcome to Glink", subtitle: "Replay the introduction", symbol: "hand.wave", tint: .yellow,
                keywords: ["onboarding tour intro help"], suggested: false) {
            OnboardingWindowController.shared.show()
            return .dismiss
        },
        Command(id: "appearance", title: "Toggle System Appearance", subtitle: "Switch between Light and Dark Mode",
                symbol: "circle.lefthalf.filled", tint: .indigo, keywords: ["dark mode light mode theme"], suggested: false) {
            let ok = await Shell.osascript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            return ok ? .dismiss : .toast(.failure("Couldn't change appearance", "Allow Glink to control System Events in Privacy & Security › Automation."))
        },
        Command(id: "sleep", title: "Sleep", subtitle: nil, symbol: "moon.zzz", tint: .teal, keywords: ["system sleep"], suggested: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Task { _ = await Shell.run("/usr/bin/pmset", ["sleepnow"]) } }
            return .dismiss
        },
        Command(id: "displaySleep", title: "Turn Off Display", subtitle: nil, symbol: "display", tint: .teal,
                keywords: ["screen off lock"], suggested: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Task { _ = await Shell.run("/usr/bin/pmset", ["displaysleepnow"]) } }
            return .dismiss
        },
        Command(id: "quit", title: "Quit Glink", subtitle: nil, symbol: "power", tint: .red, keywords: ["exit close"], suggested: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
            return .dismiss
        },
    ]

    private lazy var targets: [(Command, MatchTarget)] = commands.map { ($0, MatchTarget(title: $0.title, keywords: $0.keywords)) }

    func results(for query: String) async -> [SearchItem] {
        let q = FuzzyMatcher.prepareQuery(query)
        return targets.compactMap { command, target in
            guard let m = target.match(q) else { return nil }
            return item(for: command, score: m.score, indices: m.matchedIndices)
        }
    }

    func item(withID id: String) -> SearchItem? {
        guard id.hasPrefix("cmd."), let command = commands.first(where: { "cmd.\($0.id)" == id }) else { return nil }
        return item(for: command, score: 0, indices: [])
    }

    func suggestions() -> [SearchItem] {
        commands.filter(\.suggested).map { item(for: $0, score: 0, indices: []) }
    }

    private func item(for c: Command, score: Double, indices: [Int]) -> SearchItem {
        SearchItem(id: "cmd.\(c.id)", title: c.title, subtitle: c.subtitle, icon: .symbol(c.symbol, tint: c.tint),
                   kind: .command, score: score, matchedIndices: indices, accessory: "Command",
                   actions: [ItemAction(id: "run", title: "Run Command", symbol: "return", shortcut: .returnKey, perform: c.run)])
    }
}

/// Runs helper processes off the main thread.
enum Shell {
    static func run(_ path: String, _ args: [String]) async -> Bool {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus == 0) }
            do { try p.run() } catch { cont.resume(returning: false) }
        }
    }

    static func osascript(_ script: String) async -> Bool {
        await run("/usr/bin/osascript", ["-e", script])
    }
}
