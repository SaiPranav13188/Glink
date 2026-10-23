# Glink

A keyboard-first command bar for the Mac, built from scratch in Swift. Press **⌥ Space**, type a few letters, and launch apps, find files, do math, reuse your clipboard, snap windows, expand snippets, ask AI, or audit your MCP server configs. You never have to touch the mouse.

> macOS 14 Sonoma or later · Liquid Glass on macOS 26 · Swift 6 · SwiftUI + AppKit · SwiftData

## Features

| | |
|---|---|
| **Command panel** | Floating, non-activating glass panel. It opens on the screen under the mouse, about 20% from the top, and grows or shrinks with its results. |
| **App search** | Fuzzy matching (`xc` → Xcode, `vsc` → Visual Studio Code) with matched letters highlighted and real app icons. |
| **File search** | Spotlight index (`NSMetadataQuery`). File results stream in after the instant results, and each keystroke cancels the previous query. |
| **Calculator** | Inline math (`2^10`, `20% of 150`, `sqrt(16)+1`, `5!`) and unit conversion (`10 km to mi`, `72f in c`, `1.5 gb as mb`). The digits roll as the answer changes. |
| **Actions (⌘K)** | Open, Show in Finder, Quick Look (⌘Y), Copy Path, Move to Trash, Quit App… with a searchable list and keyboard shortcuts. |
| **Clipboard history** | Text, links, colors, images and files. Pin, delete, and paste into any app. Password-manager items and apps you exclude are skipped. Image previews zoom out of their row thumbnails. |
| **Window management** | Halves, thirds, quarters, maximize, center, next display. A preview outline glides to the target before the window moves. |
| **Snippets** | Type a keyword like `;date` in any app to expand it. Supports `{date}`, `{date:yyyy-MM-dd}`, `{time}`, `{clipboard}`, `{uuid}` and `{cursor}`. |
| **Quicklinks** | `gh apple/swift` opens GitHub; select a quicklink and press **Tab** to type its query. |
| **Ranking** | Frequently and recently used items rise to the top; a **Recent** section appears on an empty query. |
| **AI commands** | Ask AI, Summarize, Rewrite, Explain, Fix Grammar, Make Shorter. These work on the selected text, or on the clipboard as a fallback. Responses stream in word by word with a caret. Uses your own Anthropic API key, stored in the Keychain. |
| **MCP Config Check** | Runs **Tollgate's rules engine** (vendored in `Packages/MCPShieldCore`, with its labelled eval set) on every MCP server Glink finds: Claude Desktop, Claude Code (and its projects), Cursor, VS Code, Windsurf, Zed, Gemini CLI, Continue, plus anything added with **Add Config…**. Each server gets a 0–100 score and a grade (Good, Needs work, At risk), with a fix for every finding. Secrets are always redacted. Glink adds six rules Tollgate doesn't cover (GLK-001…006: `sudo`, privileged Docker or the Docker socket, auto-approved tools, `trust: true`, programs in temporary folders, world-readable configs that hold secrets). Copy the report as Markdown or export Tollgate's JSON. |
| **Script commands** (v2) | Executable scripts in `~/Library/Application Support/Glink/Scripts` become commands. Set them up with `# @glink.title`, `mode` (silent, compact or fullOutput), `icon` and `argument1` comments; Raycast's `@raycast.*` keys work too. "Open Script Commands Folder" creates two examples. |
| **Floating notes** (v2) | An always-on-top glass notes window that autosaves to `Notes.md`. |
| **Menu bar mini mode** (v2) | Turn it on in Settings › General › Extras: clicking the menu bar icon then opens a compact search popover, and right-clicking still shows the menu. |
| **Auto-updates** | Sparkle 2 with EdDSA-signed updates and gentle reminders (a found update doesn't steal focus). Only copies installed in an Applications folder check for updates. |
| **Onboarding & Settings** | A 4-step animated welcome (hotkey recorder with a live keyboard, permission cards, "try it"). Settings has General, Appearance (with a live preview), Clipboard, Snippets, Quicklinks, AI, Privacy, Advanced and About. |

## Build & run

### SwiftPM (no Xcode project needed)

```sh
scripts/build-app.sh          # → build/Glink.app (ad-hoc signed)
open build/Glink.app
swift test                    # 28 unit tests (Swift Testing)
```

`UNIVERSAL=1` builds arm64 + x86_64. `SIGN_IDENTITY="Developer ID Application: …"` signs with hardened runtime.

### Xcode

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen   # once
xcodegen generate
open Glink.xcodeproj    # scheme "Glink": app, unit tests, UI tests
```

### Launch arguments (demos, screenshots, UI tests)

```sh
build/Glink.app/Contents/MacOS/Glink --open "10 km to mi"
build/Glink.app/Contents/MacOS/Glink --route clipboard   # or: mcp, snippets
```

## Permissions

Everything works without permissions except the features below. Each one asks only when you use it, with an inline card explaining why.

| Permission | Used for |
|---|---|
| **Accessibility** | Window snapping, pasting into the frontmost app, reading selected text for AI, and snippet expansion (listen-only event tap). |
| **Automation → System Events** | Only the "Toggle System Appearance" command. |

> **Ad-hoc builds:** macOS ties Accessibility trust to the code signature. After rebuilding an ad-hoc signed app, remove Glink from *Privacy & Security → Accessibility* and add it again, or sign with a Developer ID identity.

## Keyboard

| Key | Action |
|---|---|
| ⌥ Space | Toggle panel (configurable) |
| ↑ ↓ / ⌃N ⌃P | Move selection · ⌘↑ ⌘↓ jump to first/last |
| ↵ | Run primary action |
| ⌘K | Actions for the selected item |
| ⌘1–9 | Run result 1–9 (hold ⌘ to see badges) |
| Tab | Enter a command's argument, or autocomplete |
| Esc | Clear text → leave argument → go back → close |
| ⌫ on empty field | Leave argument / go back |
| ⌘, | Settings |

## Architecture

```
Hotkey ─► PanelController ─► CommandPanel (NSPanel, pre-built & hidden)
                                   │
                         PanelRootView (SwiftUI) ◄── PanelViewModel (@Observable)
                                                          │
                                   SearchEngine ──► [SearchProvider] (all run on every keystroke)
                                                     Calculator · Apps · Commands · Quicklinks
                                                     Window · AI · MCP · Snippets · Clipboard
                                                     Files (slow → streams in last)
```

- **`GlinkCore/`**: pure logic with no AppKit, unit-tested: fuzzy matcher (DP alignment with word-boundary/camelCase bonuses), calculator & unit converter, snippet expander/trigger, ranking score, and the MCP rules engine.
- **`Glink/Panel/`**: the panel window, controller, view model, and the sub-screen models (clipboard, AI, MCP, snippets).
- **`Glink/Providers/`**: one file per result source, all behind the `SearchProvider` protocol.
- **`Glink/System/`**: clipboard monitor, AX window manager + snap preview, CGEventTap text expander, Keychain, AI streaming client, permissions.
- **`Glink/UI/DesignSystem/`**: `Motion.swift` (every animation token), `Theme.swift`, `Typography.swift`.

### Motion

All animation goes through `Motion` tokens (`snappy`, `smooth`, `bouncy`, `gentle`, `panelIn`, `panelOut`). Model state changes plainly, and views declare their animations with `.motion(_:value:)`. This honors **Reduce Motion** and the in-app *Animation level* (Full / Reduced / Off); Reduced swaps movement for short cross-fades. Nothing in the panel runs longer than 350 ms, and typing never waits for an animation.

Highlights: a spring entrance and quick exit, a selection highlight that slides between rows (`matchedGeometryEffect`), a first-open row cascade, an animated panel height, the ⌘K sheet sliding up while the list dims, rolling calculator digits, toasts that bounce in, the magnifier morphing into a spinner while files load, a shimmer skeleton (only after 120 ms), a shake on invalid input, AI text streaming with a caret, a window-snap preview, clipboard image zoom, onboarding push transitions, permission cards that turn green with a drawn checkmark, and trackpad haptics at list ends and on snaps.

## Testing

- `swift test` runs 28 Swift Testing unit tests (matcher, calculator and units, snippets, ranking, MCP discovery and Glink rules).
- `cd Packages/MCPShieldCore && swift test` runs Tollgate's 45 tests, including the precision/recall eval.
- `GlinkUITests` (Xcode, scheme **Glink**) drives the real panel. It checks suggestions, app search, the calculator, no-results fallbacks, arrow-key selection, ⌘K actions, Clipboard History and back, Esc behavior, script commands and floating notes. It also runs `performAccessibilityAudit()` on the root panel, the ⌘K menu, MCP Config Check and Clipboard History. UI tests launch Glink with `--ephemeral` (an in-memory store with no clipboard capture), so they never touch your real data. They need an unlocked session; macOS asks once for Touch ID or your password to enable UI automation.

## Performance

Measured on the release build with `Glink --ephemeral --benchmark`:

| Budget | Target | Measured |
|---|---|---|
| Hotkey → panel drawn | < 50 ms | 11.5 ms median (16 ms max) |
| Keystroke → results | < 30 ms | 0.4–1.6 ms median (files stream in after) |
| Cold launch | < 1 s | ~760 ms |
| Idle memory (footprint) | < 80 MB | 26 MB idle, 42–52 MB in use |
| Idle CPU | ~0% | 0.0–0.1% |

`Glink --animation-benchmark` drives the panel like a person would (open, type, arrow keys, ⌘K, close) for Instruments' **Animation Hitches** and **Time Profiler** templates. The work done for this:

- The open/close spring runs as a Core Animation spring on the hosting layer, not as SwiftUI state.
- Result lists are lazy, and rows are `Equatable`, so moving the selection re-renders only two rows.
- The list doesn't animate while the panel is springing in.
- The panel's shadow is cast by a plain shape instead of a compositing group.
- App search builds full results only for the best matches.

On a busy development machine, the script logged 18 hitches with animations on and 13 with them off. Most are therefore environmental; re-measure on a quiet Mac before claiming zero.

## Release

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="glink-notary" scripts/make-dmg.sh
```

This builds a universal app, signs it with hardened runtime, creates the DMG, notarizes and staples it. It requires an Apple Developer Program membership. Glink ships outside the Mac App Store because the Accessibility API and event taps don't work in the sandbox.

## Privacy

All data stays on your Mac: clipboard history, snippets and usage counts are in `~/Library/Application Support/Glink`, and the API key is in the Keychain. There are no analytics. The snippet expander keeps only the last 64 typed characters in memory and never logs them. AI requests send only the text you select or type, and only when you run an AI command.

## Release checklist

1. Create the GitHub repo `SaiPranav13188/Glink`. The update feed URL in `Info.plist` points at its latest release.
2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Glink/Resources/Info.plist`.
3. Run `SIGN_IDENTITY=… NOTARY_PROFILE=… scripts/make-dmg.sh`. It builds, signs, notarizes and staples, writes `appcast.xml`, and prints the `gh release create` command to publish.

The Sparkle EdDSA private key is in the login Keychain (account `glink`). Back it up, because you can't ship updates to existing installs without it.

---

Built by B. Sai Pranav.
