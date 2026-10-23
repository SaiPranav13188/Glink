import AppKit
import Carbon.HIToolbox
import GlinkCore
import Observation
import SwiftUI

enum SelectionSource { case keyboard, mouse }

enum PanelFocus: Hashable { case search, actions }

/// State and keyboard logic for the command panel. Views render it; PanelController feeds it key events.
@MainActor @Observable
final class PanelViewModel {
    // Search
    var query = "" { didSet { if query != oldValue { queryDidChange() } } }
    private(set) var rootSections: [ResultSection] = []
    private(set) var isLoading = false
    private(set) var showSkeleton = false
    private(set) var isFallback = false
    private(set) var searchGeneration = 0

    // Selection
    var selectedID: String?
    private(set) var selectionSource: SelectionSource = .keyboard
    @ObservationIgnored var lastMouseLocation: NSPoint = .zero

    // Argument mode (Tab on a quicklink / Ask AI)
    private(set) var argumentItem: SearchItem?

    // Navigation
    private(set) var route: Route?
    @ObservationIgnored private var rootQueryBeforePush = ""

    // Actions panel (⌘K)
    private(set) var actionsPresented = false
    var actionsQuery = "" { didSet { actionsSelectedID = filteredActions.first?.id } }
    var actionsSelectedID: String?

    // Feedback
    private(set) var toast: Toast?
    private(set) var shakeTrigger = 0
    private(set) var commandHeld = false
    var focus: PanelFocus = .search

    // Presentation
    var isPresented = false
    private(set) var openCount = 0
    @ObservationIgnored private(set) var openedAt = Date.distantPast

    // Sub-screens
    let clipboard = ClipboardRouteModel()
    let ai = AIConversationModel()
    let mcp = MCPCheckModel()
    let snippets = SnippetsRouteModel()

    /// How this model closes its container (the panel by default; the menu bar popover in mini mode).
    @ObservationIgnored var onDismiss: @MainActor () -> Void = { PanelController.shared.hide() }
    /// Lets a container hand sub-screens elsewhere (mini mode opens them in the full panel).
    @ObservationIgnored var onPush: (@MainActor (Route) -> Bool)?

    @ObservationIgnored let engine: SearchEngine
    @ObservationIgnored let appProvider: AppProvider
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var skeletonTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        let apps = AppProvider()
        appProvider = apps
        engine = SearchEngine(providers: [
            CalculatorProvider(), apps, SystemCommandProvider(), QuicklinkProvider(), WindowCommandProvider(),
            AIProvider(), MCPCheckProvider(), SnippetProvider(), ScriptCommandProvider(), ClipboardProvider(), FileProvider(),
        ])
    }

    // MARK: - Derived

    /// Sections for whatever screen is showing.
    var sections: [ResultSection] {
        switch route {
        case nil: return argumentItem == nil ? rootSections : []
        case .clipboard: return clipboard.sections(query: query)
        case .snippets: return snippets.sections(query: query)
        case .scriptOutput: return []
        case .mcpCheck: return mcp.sections(query: query)
        case .ai: return []
        }
    }

    var flatItems: [SearchItem] { sections.flatMap(\.items) }

    /// Changes whenever the visible rows change, so views can animate inserts, moves and height.
    var resultsSignature: String {
        flatItems.map { $0.id + ($0.calculation?.result ?? "") }.joined(separator: "|") + "\(isFallback)\(isLoading)"
    }

    var selectedItem: SearchItem? {
        let items = flatItems
        return items.first { $0.id == selectedID } ?? items.first
    }

    /// Actions offered for the current selection (or for the AI response).
    var currentActions: [ItemAction] {
        if case .ai = route { return ai.actions }
        if case .scriptOutput(let output) = route { return ScriptActions.outputActions(output) }
        if case .mcpCheck = route, flatItems.isEmpty { return mcp.globalActions }
        if let argumentItem { return argumentItem.actions.isEmpty ? [] : [argumentRunAction(argumentItem)] }
        return selectedItem?.actions ?? []
    }

    var filteredActions: [ItemAction] {
        let q = FuzzyMatcher.prepareQuery(actionsQuery)
        guard !q.isEmpty else { return currentActions }
        return currentActions.filter { FuzzyMatcher.match(q, in: FuzzyCandidate($0.title)) != nil }
    }

    var placeholder: String {
        if let argumentItem { return argumentItem.argumentPlaceholder ?? "Type…" }
        return route?.placeholder ?? "Search apps, files, and commands…"
    }

    var hasWindowCommandsVisible: Bool { route == nil && rootSections.contains { $0.id == "window" } }

    // MARK: - Lifecycle

    func prepareForOpen(resetState: Bool) {
        if resetState { resetToRoot() }
        openCount += 1
        openedAt = Date()
        // A mouse resting where the panel appears must not steal the keyboard selection.
        lastMouseLocation = NSEvent.mouseLocation
        appProvider.refreshIfNeeded()
        clipboard.refresh()
        actionsPresented = false
        toast = nil
        commandHeld = false
        focus = .search
        if route == nil && argumentItem == nil { runSearch(animated: false) }
    }

    func resetToRoot() {
        ai.cancel()
        route = nil
        argumentItem = nil
        if !query.isEmpty { query = "" }
        rootQueryBeforePush = ""
    }

    // MARK: - Searching

    private func queryDidChange() {
        selectionSource = .keyboard
        switch route {
        case nil where argumentItem == nil:
            runSearch(animated: true)
        default:
            selectedID = flatItems.first?.id
        }
    }

    func runSearch(animated: Bool) {
        searchTask?.cancel()
        skeletonTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let q = query
        var isFirstSnapshot = true

        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.engine.search(q) { snapshot in
                guard generation == self.searchGeneration else { return }
                self.apply(snapshot, animated: animated, resetSelection: isFirstSnapshot)
                isFirstSnapshot = false
            }
        }
        // Skeleton rows only if results take longer than 120 ms.
        skeletonTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled, generation == self.searchGeneration, self.isLoading, self.rootSections.isEmpty else { return }
            self.showSkeleton = true
        }
    }

    private func apply(_ snapshot: SearchSnapshot, animated: Bool, resetSelection: Bool) {
        let update = {
            self.rootSections = snapshot.sections
            self.isFallback = snapshot.isFallback
            self.isLoading = snapshot.pendingSlowProviders
            if !snapshot.pendingSlowProviders || !snapshot.sections.isEmpty { self.showSkeleton = false }
            let ids = Set(self.flatItems.map(\.id))
            if resetSelection || self.selectedID.map({ !ids.contains($0) }) ?? true {
                self.selectedID = self.flatItems.first?.id
            }
        }
        update()
    }

    // MARK: - Selection

    func select(_ id: String?, source: SelectionSource) {
        selectionSource = source
        selectedID = id
    }

    func moveSelection(_ delta: Int) {
        let items = flatItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        let next = current + delta
        guard items.indices.contains(next) else {
            Haptics.tick()   // reached the end of the list
            return
        }
        select(items[next].id, source: .keyboard)
    }

    func hoverSelect(_ id: String) {
        let location = NSEvent.mouseLocation
        // Only steal the keyboard selection when the mouse actually moved.
        guard location != lastMouseLocation else { return }
        lastMouseLocation = location
        if selectedID != id { select(id, source: .mouse) }
    }

    // MARK: - Running

    func activate(_ item: SearchItem) {
        selectedID = item.id
        if item.requiresArgument {
            enterArgumentMode(item)
            return
        }
        guard let action = item.primaryAction else { return shake() }
        run(action, for: item)
    }

    func run(_ action: ItemAction, for item: SearchItem?) {
        if let item, ![ItemKind.calculator, .web].contains(item.kind), !item.id.hasPrefix("fallback"), route == nil {
            RankingStore.shared.recordUse(of: item.id)
        }
        actionsPresented = false
        focus = .search
        Task {
            let outcome = await action.perform()
            handle(outcome)
        }
    }

    func handle(_ outcome: ActionOutcome) {
        switch outcome {
        case .dismiss:
            onDismiss()
        case .dismissWithHUD(let message, let symbol):
            onDismiss()
            HUDController.shared.show(message, symbol: symbol)
        case .stay:
            break
        case .toast(let t):
            if t.style == .failure { shake() }
            showToast(t)
        case .push(let r):
            if onPush?(r) == true { return }
            push(r)
        case .setQuery(let q):
            query = q
        }
    }

    func push(_ r: Route) {
        if route == nil { rootQueryBeforePush = argumentItem == nil ? query : "" }
        argumentItem = nil
        route = r
        actionsPresented = false
        query = ""
        switch r {
        case .ai(let request): ai.start(request)
        case .mcpCheck: mcp.scanIfNeeded()
        case .clipboard: clipboard.refresh()
        case .snippets: snippets.refresh()
        case .scriptOutput: break
        }
        selectedID = flatItems.first?.id
    }

    func pop() {
        guard route != nil else { return }
        ai.cancel()
        route = nil
        let previous = query
        query = rootQueryBeforePush   // didSet re-runs the search when the text changes
        if previous == query { runSearch(animated: false) }
    }

    func enterArgumentMode(_ item: SearchItem) {
        guard item.takesArgument else { return shake() }
        argumentItem = item
        query = ""
    }

    func exitArgumentMode() {
        argumentItem = nil
        runSearch(animated: true)
    }

    private func argumentRunAction(_ item: SearchItem) -> ItemAction {
        ItemAction(id: "runArgument", title: item.title, symbol: "return", shortcut: .returnKey) { [weak self] in
            guard let self, let run = item.runWithArgument else { return .stay }
            let text = self.query.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return .toast(.failure("Type something first")) }
            RankingStore.shared.recordUse(of: item.id)
            return await run(text)
        }
    }

    func submitArgument() {
        guard let item = argumentItem else { return }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let run = item.runWithArgument else { return shake() }
        RankingStore.shared.recordUse(of: item.id)
        Task {
            let outcome = await run(text)
            if case .push = outcome {} else { argumentItem = nil }
            handle(outcome)
        }
    }

    // MARK: - Actions panel

    func toggleActions() {
        guard !currentActions.isEmpty else { return shake() }
        actionsPresented.toggle()
        actionsQuery = ""
        actionsSelectedID = filteredActions.first?.id
        focus = actionsPresented ? .actions : .search
    }

    func closeActions() {
        actionsPresented = false
        focus = .search
    }

    func moveActionSelection(_ delta: Int) {
        let list = filteredActions
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == actionsSelectedID } ?? 0
        let next = i + delta
        guard list.indices.contains(next) else { return Haptics.tick() }
        actionsSelectedID = list[next].id
    }

    // MARK: - Feedback

    func shake() {
        shakeTrigger += 1
        Haptics.tick()
    }

    func showToast(_ t: Toast) {
        toastTask?.cancel()
        toast = t
        let duration: Double = t.style == .failure ? 4 : 2
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled, self.toast?.id == t.id else { return }
            self.toast = nil
        }
    }

    func dismissToast() {
        toast = nil
    }

    // MARK: - Keyboard

    /// Returns true when the event was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            let held = event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            if held != commandHeld { commandHeld = held }
            return false
        }

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)

        // ⌘K toggles actions from anywhere.
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
            toggleActions()
            return true
        }
        if mods == .command, event.charactersIgnoringModifiers == "," {
            onDismiss()
            SettingsWindowController.shared.show()
            return true
        }

        if actionsPresented { return handleActionsKey(event, mods: mods, code: code) }

        switch code {
        case kVK_Escape:
            escape()
            return true
        case kVK_UpArrow where mods.isEmpty || mods == .control:
            moveSelection(-1)
            return true
        case kVK_DownArrow where mods.isEmpty || mods == .control:
            moveSelection(1)
            return true
        case kVK_UpArrow where mods == .command:
            if let first = flatItems.first { select(first.id, source: .keyboard) }
            return true
        case kVK_DownArrow where mods == .command:
            if let last = flatItems.last { select(last.id, source: .keyboard) }
            return true
        case kVK_Return where mods.isEmpty, kVK_ANSI_KeypadEnter where mods.isEmpty:
            returnPressed()
            return true
        case kVK_Tab where mods.isEmpty:
            tabPressed()
            return true
        case kVK_Delete where mods.isEmpty && query.isEmpty:
            if argumentItem != nil { exitArgumentMode(); return true }
            if route != nil { pop(); return true }
            return false
        default:
            break
        }

        // Emacs-style ⌃N / ⌃P
        if mods == .control, let c = event.charactersIgnoringModifiers?.lowercased() {
            if c == "n" { moveSelection(1); return true }
            if c == "p" { moveSelection(-1); return true }
        }

        // ⌘1–9 jump to (and run) a result.
        if mods == .command, let c = event.charactersIgnoringModifiers, let n = Int(c), (1...9).contains(n) {
            let items = flatItems
            guard items.indices.contains(n - 1) else { shake(); return true }
            select(items[n - 1].id, source: .keyboard)
            activate(items[n - 1])
            return true
        }

        // Shortcuts of the selected item's actions (⌘↵, ⌘Y, ⌃X …).
        if !mods.isEmpty, let action = currentActions.dropFirst().first(where: { $0.shortcut?.matches(event) == true }) {
            run(action, for: selectedItem)
            return true
        }
        return false
    }

    private func handleActionsKey(_ event: NSEvent, mods: NSEvent.ModifierFlags, code: Int) -> Bool {
        switch code {
        case kVK_Escape:
            closeActions()
            return true
        case kVK_UpArrow:
            moveActionSelection(-1)
            return true
        case kVK_DownArrow:
            moveActionSelection(1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let action = filteredActions.first(where: { $0.id == actionsSelectedID }) ?? filteredActions.first {
                runFromActionsPanel(action)
            } else {
                shake()
            }
            return true
        default:
            if !mods.isEmpty, let action = currentActions.first(where: { $0.shortcut?.matches(event) == true }) {
                runFromActionsPanel(action)
                return true
            }
            return false
        }
    }

    private func escape() {
        if toast != nil, toast?.style == .failure { dismissToast() }
        if !query.isEmpty {
            query = ""
        } else if argumentItem != nil {
            exitArgumentMode()
        } else if route != nil {
            pop()
        } else {
            onDismiss()
        }
    }

    private func returnPressed() {
        if argumentItem != nil { return submitArgument() }
        if case .ai = route {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                ai.followUp(text)
                query = ""
            } else if let primary = ai.actions.first {
                run(primary, for: nil)
            }
            return
        }
        guard let item = selectedItem else { return shake() }
        activate(item)
    }

    private func tabPressed() {
        guard route == nil, argumentItem == nil, let item = selectedItem else { return shake() }
        if item.takesArgument {
            enterArgumentMode(item)
        } else if !query.isEmpty, item.title.lowercased() != query.lowercased(), item.kind != .calculator {
            query = item.title   // autocomplete
        } else {
            shake()
        }
    }
}
