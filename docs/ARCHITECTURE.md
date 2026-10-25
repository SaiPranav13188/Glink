# Glink architecture

This document covers how the code is organized today, where things live, how it differs from the original plan (`glink.md`), and the risks found while building v2.

## Map

```mermaid
flowchart LR
    HK[Global hotkey<br/>KeyboardShortcuts] --> PC[PanelController<br/>NSPanel, CA spring]
    PC --> VM[PanelViewModel<br/>@Observable]
    VM --> SE[SearchEngine]
    SE --> FAST["Fast providers<br/>Calculator · Apps · Commands · Quicklinks<br/>Window · AI · MCP · Snippets · Scripts<br/>MCP Tools · Clipboard"]
    SE --> SLOW["Slow providers (stream in)<br/>Files (NSMetadataQuery) · By Meaning (vectors)"]
    VM --> ROUTES["Sub-screens<br/>Clipboard · AI · MCP check · MCP tool<br/>MCP Activity · Snippets · Recent Actions"]
    ROUTES --> AI[AIService<br/>Foundation Models]
    ROUTES --> MCPC[MCPClientManager<br/>MCP Swift SDK, stdio]
    MCPC --> SAFE["GlinkCore safety<br/>risk · permissions · injection"]
    SLOW --> IDX[SemanticIndexer<br/>NLEmbedding · Vision OCR · FSEvents]
    VM --> UNDO[UndoCenter]
    VM --> MASCOT[Mascots]
```

**From hotkey to result:**

1. `KeyboardShortcuts.onKeyDown(.togglePanel)` calls `PanelController.toggle()`.
2. The pre-built `CommandPanel` is ordered in, then `PanelViewModel.prepareForOpen()` runs. The entrance spring is a Core Animation spring on the hosting layer.
3. Each keystroke runs `queryDidChange()` → `runSearch()` → `SearchEngine.search()`:
   - Fast providers run and their results are published at once.
   - Slow providers (files, by meaning) merge in afterwards.
   - Sections are sorted with the calculator pinned first and slow sections last, and de-duplicated by item ID.
4. The ↵ key goes through a local `NSEvent` monitor (`PanelViewModel.handleKey`) → `activate()` → the item's primary `ItemAction`. The resulting `ActionOutcome` dismisses the panel, pushes a sub-screen, shows a toast, or asks for confirmation.

## Where things live

| Concern | Location |
|---|---|
| `SearchProvider` protocol, engine, merging and ranking | `Glink/Search/SearchEngine.swift`, `RankingStore.swift` |
| Result model, actions, routes, toasts, confirm requests | `Glink/Search/SearchItem.swift` |
| Motion tokens (every animation) | `Glink/UI/DesignSystem/Motion.swift` |
| Theme and typography | `Glink/UI/DesignSystem/Theme.swift`, `Typography.swift` |
| Settings (UserDefaults, observable) | `Glink/App/AppSettings.swift`, panes in `Glink/UI/Settings/` |
| Permissions (Accessibility) | `Glink/System/PermissionsManager.swift` |
| On-device AI | `GlinkCore/OnDeviceAI.swift` (testable), `Glink/System/AIService.swift` (Foundation Models) |
| MCP security check | `GlinkCore/MCPConfigAnalyzer.swift` on top of `Packages/MCPShieldCore` (Tollgate) |
| MCP client, permissions, audit, injection | `Glink/MCP/*`, `GlinkCore/MCPToolSafety.swift`, `GlinkCore/InjectionDetector.swift` |
| Semantic search | `GlinkCore/SemanticSearch.swift`, `Glink/Semantic/*` |
| Suggestions | `GlinkCore/Suggestions.swift`, `Glink/Semantic/SemanticProvider.swift` (`SuggestionsEngine`) |
| Undo | `GlinkCore/UndoLog.swift`, `Glink/System/UndoCenter.swift` |
| Mascots | `Glink/UI/Mascots/Mascots.swift` |
| Persistence (SwiftData) | `Glink/Data/Models.swift`, `V2Models.swift`, `Glink/MCP/MCPModels.swift` |

Everything in `GlinkCore` is plain Foundation and is unit-tested. The app target holds AppKit, SwiftUI and system integration.

## Differences from glink.md

- **App lifecycle:** AppKit `main.swift` instead of a SwiftUI `App`. The panel, settings and onboarding are self-managed windows.
- **Panel entrance:** a Core Animation spring on the hosting layer instead of SwiftUI state. Animating SwiftUI state redrew the whole panel every frame.
- **Model-driven animations:** model state changes plainly, and views declare animations with `.motion(_:value:)`. Mutating `@Observable` state inside `withAnimation` led SwiftUI to re-render mid-mutation and miss updates.
- **AI:** v1 used Claude over the network. v2 is on-device only (Foundation Models), as `glink-v2-free-features.md` requires.
- **Grades:** the MCP check grades each server with Tollgate's 0–100 scoring and caps, plus A–F letters. The headline is the weakest server.

## Risks found (and what was done)

| Risk | Status |
|---|---|
| ObjC exceptions inside Swift tasks (e.g. a malformed `NSMetadataQuery` predicate) corrupted task state and crashed SwiftUI later | Fixed: query calls run outside task jobs; the predicate is validated |
| `repeatForever` animations driven by `.animation(value:)` never stopped (idle CPU 3–8%) | Fixed: endless animations live in views that only exist while needed |
| `withAnimation` + `@Observable` dropped view updates | Fixed: model-driven animations (see above) |
| Paste firing while the panel was still key | Fixed: paste waits for the exit animation |
| Accessibility trust resets with every ad-hoc build | Documented; use a stable signing identity for daily use |
| `XCUITest.typeText` adds ⌘ to keys on this Xcode | Tests type with `typeKey(_:modifierFlags: [])` |
| MCP servers are arbitrary programs | Security check before enabling; permission sheet for non-read-only tools; audit log; injection checks; processes terminated on disable and quit |
| Injection detection is heuristic | Two layers; measured on a labelled set (see README); flagged results never reach the AI without consent |
| Semantic indexing touches private folders | Off by default, folder-scoped, local only, Clear and Pause available; pauses while typing and on low battery |
