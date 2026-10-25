import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if AppSettings.shared.menuBarMiniMode && !wantsMenu {
            MiniModeController.shared.toggle(relativeTo: sender)
        } else if let item = statusItem, let menu = statusMenu {
            item.menu = menu
            sender.performClick(nil)   // shows the menu
            item.menu = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = DataStore.shared
        AppSettings.shared.applyAppearance()
        NSApp.mainMenu = makeMainMenu()
        setUpStatusItem()

        PanelController.shared.setUp()
        _ = Updater.shared
        if !DataStore.isEphemeral { ClipboardMonitor.shared.start() }
        TextExpander.shared.startIfPossible()

        KeyboardShortcuts.onKeyDown(for: .togglePanel) {
            MainActor.assumeIsolated { PanelController.shared.toggle() }
        }
        KeyboardShortcuts.onKeyDown(for: .clipboardHistory) {
            MainActor.assumeIsolated { PanelController.shared.show(route: .clipboard) }
        }

        NotificationCenter.default.addObserver(forName: .accessibilityGranted, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TextExpander.shared.startIfPossible() }
        }

        if !AppSettings.shared.hasCompletedOnboarding {
            OnboardingWindowController.shared.show()
        }
        handleDemoArguments()
        if ProcessInfo.processInfo.arguments.contains("--benchmark") { Benchmark.run() }
        if ProcessInfo.processInfo.arguments.contains("--animation-benchmark") { Benchmark.runAnimationScript() }
    }

    /// `Glink --open [query]` opens the panel at launch (handy for screenshots and UI tests).
    /// `--route clipboard|mcp|snippets` opens a sub-screen instead.
    private func handleDemoArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--ask"), i + 1 < args.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                PanelController.shared.show(route: .ai(AIRequest(command: .ask, input: args[i + 1])))
            }
            return
        }
        guard let i = args.firstIndex(of: "--open") ?? args.firstIndex(of: "--route") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if args[i] == "--route", i + 1 < args.count {
                let route: Route? = switch args[i + 1] {
                case "clipboard": .clipboard
                case "mcp": .mcpCheck
                case "snippets": .snippets
                default: nil
                }
                PanelController.shared.show(route: route)
            } else {
                PanelController.shared.show()
                if i + 1 < args.count, !args[i + 1].hasPrefix("-") {
                    PanelController.shared.viewModel.query = args[i + 1]
                }
            }
        }
    }

    /// Opening Glink again from Finder or Spotlight shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.show()
        return false
    }

    // MARK: Menus

    /// LSUIElement apps have no visible menu bar, but text fields still need the standard
    /// Edit key equivalents (⌘C, ⌘V, ⌘A, ⌘Z) and ⌘W for windows.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Glink", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "command.square.fill", accessibilityDescription: "Glink")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = menu.addItem(withTitle: "Open Glink", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) {
            open.setShortcut(shortcut)
        }
        menu.addItem(withTitle: "Clipboard History", action: #selector(openClipboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check MCP Security", action: #selector(openMCP), keyEquivalent: "").target = self
        menu.addItem(withTitle: FloatingNotesController.shared.isVisible ? "Hide Floating Notes" : "Floating Notes",
                     action: #selector(toggleNotes), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let update = menu.addItem(withTitle: Updater.shared.pendingUpdateVersion.map { "Update to \($0)…" } ?? "Check for Updates…",
                                  action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Welcome Tour", action: #selector(openOnboarding), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openPanel() { PanelController.shared.show() }
    @objc private func openClipboard() { PanelController.shared.show(route: .clipboard) }
    @objc private func openMCP() { PanelController.shared.show(route: .mcpCheck) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func checkForUpdates() { Updater.shared.checkForUpdates() }
    @objc private func toggleNotes() { FloatingNotesController.shared.toggle() }
    @objc private func openOnboarding() { OnboardingWindowController.shared.show() }
}
