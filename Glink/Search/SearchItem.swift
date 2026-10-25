import AppKit
import SwiftUI

enum ItemKind: String, Sendable {
    case application, file, folder, calculator, clipboard, command, window, snippet, quicklink, ai, mcp, web, system

    var accessoryLabel: String {
        switch self {
        case .application: "Application"
        case .file: "File"
        case .folder: "Folder"
        case .calculator: "Calculator"
        case .clipboard: "Clipboard"
        case .command: "Command"
        case .window: "Window"
        case .snippet: "Snippet"
        case .quicklink: "Quicklink"
        case .ai: "AI"
        case .mcp: "Command"
        case .web: "Web"
        case .system: "System"
        }
    }
}

/// How a row's icon is produced. Resolved lazily (and cached) by `IconCache`.
enum ItemIcon: Hashable, Sendable {
    case path(String)                         // real Finder icon for an app/file
    case symbol(String, tint: SymbolTint)     // SF Symbol on a colored rounded square
    case clipboardImage(UUID)                 // thumbnail of a clipboard image
    case glink                                // the app's own icon
}

enum SymbolTint: String, Hashable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray, indigo

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .gray: .gray
        case .indigo: .indigo
        }
    }
}

/// A keyboard shortcut shown next to an action, and matched against key events.
struct KeyHint: Hashable, Sendable {
    var modifiers: NSEvent.ModifierFlags.RawValue
    var key: String        // lowercase character, or a named key: "return", "delete"

    init(_ modifiers: NSEvent.ModifierFlags, _ key: String) {
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift]).rawValue
        self.key = key
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var symbols: [String] {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        switch key {
        case "return": parts.append("↵")
        case "delete": parts.append("⌫")
        case "tab": parts.append("⇥")
        default: parts.append(key.uppercased())
        }
        return parts
    }

    @MainActor func matches(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard mods.rawValue == modifiers else { return false }
        switch key {
        case "return": return event.keyCode == 36 || event.keyCode == 76
        case "delete": return event.keyCode == 51
        case "tab": return event.keyCode == 48
        default: return event.charactersIgnoringModifiers?.lowercased() == key
        }
    }

    static let returnKey = KeyHint([], "return")
    static let cmdReturn = KeyHint(.command, "return")
}

/// What should happen to the panel after an action runs.
enum ActionOutcome {
    case dismiss
    case dismissWithHUD(String, symbol: String = "checkmark.circle.fill")
    case stay
    case toast(Toast)
    case push(Route)
    case setQuery(String)
    /// Show exactly what will change, then run `onConfirm` only if the user confirms.
    case confirm(ConfirmRequest)
}

/// A destructive action waiting for the user's go-ahead.
struct ConfirmRequest: Identifiable {
    let id = UUID()
    var title: String
    var symbol: String = "exclamationmark.triangle.fill"
    /// Exactly what will change, one line each.
    var changes: [String]
    var confirmTitle: String
    var destructive = true
    let onConfirm: @MainActor () async -> ActionOutcome
}

struct ItemAction: Identifiable {
    enum Style { case normal, destructive }

    let id: String
    let title: String
    let symbol: String
    var shortcut: KeyHint?
    var style: Style = .normal
    let perform: @MainActor () async -> ActionOutcome
}

struct SearchItem: Identifiable {
    let id: String
    var title: String
    var subtitle: String?
    var icon: ItemIcon
    var kind: ItemKind
    var score: Double = 0
    /// Character offsets in `title` to emphasize (from the fuzzy matcher).
    var matchedIndices: [Int] = []
    var accessory: String?
    /// First one is the primary action (↵).
    var actions: [ItemAction] = []
    /// Placeholder shown in the argument chip when this item takes input (quicklinks, Ask AI).
    var argumentPlaceholder: String?
    /// Runs with the typed argument (Tab → type → ↵).
    var runWithArgument: (@MainActor (String) async -> ActionOutcome)?
    /// When true, ↵ enters argument mode instead of running (e.g. a quicklink with no query yet).
    var requiresArgument = false
    /// Payload used by special row renderers (calculator).
    var calculation: CalculationPayload?

    var primaryAction: ItemAction? { actions.first }
    var takesArgument: Bool { runWithArgument != nil }
}

struct CalculationPayload: Hashable {
    let input: String
    let result: String
    let resultLabel: String
}

extension SearchItem: Equatable, Hashable {
    static func == (a: SearchItem, b: SearchItem) -> Bool {
        a.id == b.id && a.title == b.title && a.subtitle == b.subtitle && a.matchedIndices == b.matchedIndices
            && a.calculation == b.calculation && a.icon == b.icon
    }

    func hash(into h: inout Hasher) { h.combine(id) }
}

struct ResultSection: Identifiable, Equatable {
    let id: String
    let title: String
    var items: [SearchItem]
}

struct Toast: Identifiable, Equatable {
    enum Style: Equatable { case success, failure, info, progress }

    let id = UUID()
    var style: Style
    var title: String
    var message: String?
    var retry: (@MainActor () -> Void)?
    /// When set, the toast offers Undo for that UndoCenter entry and drains over 5 seconds.
    var undoID: UUID?

    init(style: Style, title: String, message: String? = nil, retry: (@MainActor () -> Void)? = nil, undoID: UUID? = nil) {
        self.style = style
        self.title = title
        self.message = message
        self.retry = retry
        self.undoID = undoID
    }

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }

    static func success(_ title: String, _ message: String? = nil) -> Toast { Toast(style: .success, title: title, message: message) }
    static func failure(_ title: String, _ message: String? = nil, retry: (@MainActor () -> Void)? = nil) -> Toast {
        Toast(style: .failure, title: title, message: message, retry: retry)
    }
}

/// Pushed screens inside the panel.
enum Route: Hashable {
    case clipboard
    case ai(AIRequest)
    case mcpCheck
    case snippets
    case scriptOutput(ScriptOutput)
    case recentActions

    var title: String {
        switch self {
        case .clipboard: "Clipboard History"
        case .ai(let r): r.command.title
        case .mcpCheck: "Check MCP Security"
        case .snippets: "Search Snippets"
        case .scriptOutput(let o): o.title
        case .recentActions: "Recent Actions"
        }
    }

    var icon: ItemIcon {
        switch self {
        case .clipboard: .symbol("doc.on.clipboard", tint: .orange)
        case .ai: .symbol("sparkles", tint: .purple)
        case .mcpCheck: .symbol("checkmark.shield", tint: .green)
        case .snippets: .symbol("text.quote", tint: .pink)
        case .scriptOutput: .symbol("terminal", tint: .gray)
        case .recentActions: .symbol("arrow.uturn.backward", tint: .blue)
        }
    }

    var placeholder: String {
        switch self {
        case .clipboard: "Search clipboard history…"
        case .ai: "Ask a follow-up…"
        case .mcpCheck: "Filter servers, clients or rules…"
        case .snippets: "Search snippets…"
        case .scriptOutput: "Filter output…"
        case .recentActions: "Search recent actions…"
        }
    }
}
