import AppKit
import KeyboardShortcuts
import Observation
import ServiceManagement
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
    static let clipboardHistory = Self("clipboardHistory")
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum WindowStyle: String, CaseIterable, Identifiable {
    case glass, solid
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AnimationLevel: String, CaseIterable, Identifiable {
    case full, reduced, off
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TextSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scale: CGFloat {
        switch self {
        case .small: 0.92
        case .medium: 1
        case .large: 1.12
        }
    }
}

enum PanelPosition: String, CaseIterable, Identifiable {
    case upper, center
    var id: String { rawValue }
    var title: String { self == .upper ? "Upper Third" : "Center" }
}

/// User preferences, persisted in UserDefaults. Observable so every view updates live.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var theme: ThemePreference { didSet { save(theme.rawValue, "theme"); applyAppearance() } }
    var windowStyle: WindowStyle { didSet { save(windowStyle.rawValue, "windowStyle") } }
    var animationLevel: AnimationLevel { didSet { save(animationLevel.rawValue, "animationLevel") } }
    var textSize: TextSize { didSet { save(textSize.rawValue, "textSize") } }
    var panelPosition: PanelPosition { didSet { save(panelPosition.rawValue, "panelPosition") } }
    var clipboardHistoryLimit: Int { didSet { save(clipboardHistoryLimit, "clipboardHistoryLimit") } }
    var clipboardEnabled: Bool { didSet { save(clipboardEnabled, "clipboardEnabled") } }
    var ignoredBundleIDs: [String] { didSet { save(ignoredBundleIDs, "ignoredBundleIDs") } }
    var snippetsEnabled: Bool { didSet { save(snippetsEnabled, "snippetsEnabled") } }
    var fileSearchEnabled: Bool { didSet { save(fileSearchEnabled, "fileSearchEnabled") } }
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }
    /// Extra MCP config files or folders added with "Add Config…".
    var mcpExtraPaths: [String] { didSet { save(mcpExtraPaths, "mcpExtraPaths") } }
    /// Clicking the menu bar icon opens a compact search popover instead of the menu.
    var menuBarMiniMode: Bool { didSet { save(menuBarMiniMode, "menuBarMiniMode") } }

    /// Bumped whenever ranking data is reset, so open views can refresh.
    var rankingVersion = 0

    private init() {
        let d = UserDefaults.standard
        theme = ThemePreference(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        windowStyle = WindowStyle(rawValue: d.string(forKey: "windowStyle") ?? "") ?? .glass
        animationLevel = AnimationLevel(rawValue: d.string(forKey: "animationLevel") ?? "") ?? .full
        textSize = TextSize(rawValue: d.string(forKey: "textSize") ?? "") ?? .medium
        panelPosition = PanelPosition(rawValue: d.string(forKey: "panelPosition") ?? "") ?? .upper
        clipboardHistoryLimit = d.object(forKey: "clipboardHistoryLimit") as? Int ?? 200
        clipboardEnabled = d.object(forKey: "clipboardEnabled") as? Bool ?? true
        ignoredBundleIDs = d.stringArray(forKey: "ignoredBundleIDs") ?? [
            "com.apple.keychainaccess", "com.1password.1password", "com.agilebits.onepassword7",
            "com.bitwarden.desktop", "com.apple.Passwords",
        ]
        snippetsEnabled = d.object(forKey: "snippetsEnabled") as? Bool ?? true
        fileSearchEnabled = d.object(forKey: "fileSearchEnabled") as? Bool ?? true
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        mcpExtraPaths = d.stringArray(forKey: "mcpExtraPaths") ?? []
        menuBarMiniMode = d.bool(forKey: "menuBarMiniMode")
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    func applyAppearance() {
        NSApp.appearance = theme.appearance
    }

    // MARK: Launch at login (SMAppService)

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLoginToken)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.app.error("Launch at login failed: \(error.localizedDescription)")
            }
            withMutation(keyPath: \.launchAtLoginToken) { launchAtLoginToken += 1 }
        }
    }

    private var launchAtLoginToken = 0

    // MARK: Export / import

    static let exportedKeys = ["theme", "windowStyle", "animationLevel", "textSize", "panelPosition",
                               "clipboardHistoryLimit", "clipboardEnabled", "ignoredBundleIDs", "snippetsEnabled",
                               "fileSearchEnabled", "aiEnabled", "mcpExtraPaths", "menuBarMiniMode"]

    func exportDictionary() -> [String: Any] {
        var out: [String: Any] = [:]
        for key in Self.exportedKeys { if let v = defaults.object(forKey: key) { out[key] = v } }
        return out
    }

    func importDictionary(_ dict: [String: Any]) {
        for key in Self.exportedKeys { if let v = dict[key] { defaults.set(v, forKey: key) } }
        let d = defaults
        theme = ThemePreference(rawValue: d.string(forKey: "theme") ?? "") ?? theme
        windowStyle = WindowStyle(rawValue: d.string(forKey: "windowStyle") ?? "") ?? windowStyle
        animationLevel = AnimationLevel(rawValue: d.string(forKey: "animationLevel") ?? "") ?? animationLevel
        textSize = TextSize(rawValue: d.string(forKey: "textSize") ?? "") ?? textSize
        panelPosition = PanelPosition(rawValue: d.string(forKey: "panelPosition") ?? "") ?? panelPosition
        clipboardHistoryLimit = d.object(forKey: "clipboardHistoryLimit") as? Int ?? clipboardHistoryLimit
        clipboardEnabled = d.object(forKey: "clipboardEnabled") as? Bool ?? clipboardEnabled
        ignoredBundleIDs = d.stringArray(forKey: "ignoredBundleIDs") ?? ignoredBundleIDs
        snippetsEnabled = d.object(forKey: "snippetsEnabled") as? Bool ?? snippetsEnabled
        fileSearchEnabled = d.object(forKey: "fileSearchEnabled") as? Bool ?? fileSearchEnabled
    }
}
