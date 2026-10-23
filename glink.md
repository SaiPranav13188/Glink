# Glink — A Native macOS Launcher

### Full Project Plan (Raycast-style, built from scratch in Swift)

> **Name:** Glink
> **Platform:** macOS 14 Sonoma and later, with Liquid Glass on macOS 26
> **Stack:** Swift 6, SwiftUI + AppKit, SwiftData
> **Author:** B. Sai Pranav

---

## 1. Vision

Glink is a keyboard-first command bar for the Mac. Press one shortcut, type a few letters, and launch apps, find files, reuse clipboard history, snap windows, expand snippets, or run an AI command, without touching the mouse.

**The experience goal:** it should feel like Apple built it. Instant, calm, physically believable motion, and zero friction.

### Goals
- Feel **instant**: the panel appears in under one frame of input delay, and results update on every keystroke.
- Feel **native and realistic**: real macOS materials, SF Symbols, system fonts, and spring-based motion that behaves like physical objects.
- Be **friendly for first-time users**: guided onboarding, clear permission explanations, and helpful empty states.
- Be **deep under the hood**: global hotkeys, the Accessibility API, event taps, and fast search, to build real macOS systems skill.

### Non-goals (for v1)
- A public extension store.
- Windows or iOS versions.
- Competing with Raycast feature-for-feature.

### Differentiator
One feature Raycast doesn't focus on: **MCP Config Check**, a command that scans MCP server configs on the Mac and flags risky settings, reusing the logic from Tollgate.

---

## 2. Core UX Principles

1. **Speed beats decoration.** Every animation must finish fast and never block input. The user can type the moment the panel starts appearing.
2. **Keyboard first, mouse friendly.** Everything works from the keyboard; everything is also clickable and hoverable.
3. **Motion explains change.** Animation shows where things came from and where they went. Never animate just to show off.
4. **One clear focus.** Exactly one selected row at a time, always visible.
5. **Never a dead end.** Every empty or error state tells the user what to do next.
6. **Respect the system.** Follow Light/Dark mode, accent color, Reduce Motion, Reduce Transparency, Increase Contrast, and text size.
7. **Ask for permissions only when needed**, and always explain why in plain words.

---

## 3. Feature Scope

### v1.0 — MVP
| Feature | Description |
|---|---|
| Global hotkey | Default ⌥ Space, user-configurable |
| Command panel | Floating, centered, glass-style search window |
| App search | Fuzzy search across installed apps with icons |
| File search | Spotlight-index search for files and folders |
| Calculator | Inline math and unit conversion as you type |
| Actions panel | ⌘K opens actions for the selected item (Open, Reveal in Finder, Copy Path, Quick Look) |
| Clipboard history | Searchable history of text, images, links, and files |
| Window management | Snap windows left, right, maximize, center, thirds |
| Settings | Hotkey, appearance, history length, excluded apps |
| Onboarding | 4-step welcome flow with animated previews |

### v1.1
| Feature | Description |
|---|---|
| Snippets | Keyword-triggered text expansion with placeholders like `{date}` |
| Quicklinks | Saved URLs with a query, e.g. `gh <repo>` |
| Ranking by usage | Frequently used items rise to the top |
| AI command | Rewrite, summarize, or explain selected text with an LLM (user's own API key) |
| MCP Config Check | Scan local MCP configs and show a risk score |

### v2.0 (stretch)
- Simple extension system (script commands in Shell, Python, or JS)
- Floating notes
- Menu bar mini mode
- Multi-monitor awareness (panel opens on the active screen)

---

## 4. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Language | Swift 6 | Strict concurrency, modern safety |
| UI | SwiftUI | Fast to build, rich animation APIs |
| Windowing | AppKit `NSPanel` | Fine control over floating, focus, and level |
| Storage | SwiftData | Clipboard history, snippets, usage stats |
| Secrets | Keychain | AI API keys |
| Hotkeys | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Reliable global shortcuts + recorder UI |
| Launch at login | `SMAppService` | Modern, Apple-supported |
| Updates | Sparkle | Standard for apps outside the App Store |
| Testing | Swift Testing + XCTest UI tests | Unit and UI coverage |
| Profiling | Instruments | Time Profiler, Allocations, Animation Hitches |

### Distribution note
Window management and text expansion need the **Accessibility API** and **event taps**, which don't work in the App Store sandbox. Like Raycast, Glink ships **outside the Mac App Store** as a signed, notarized DMG. This requires an Apple Developer Program membership.

---

## 5. Architecture

### High-level flow

```
Hotkey pressed
   → PanelController shows NSPanel (pre-built, hidden, so it appears instantly)
   → User types → SearchViewModel debounces nothing (runs every keystroke)
   → SearchEngine queries all Providers in parallel
   → Results merged, ranked, and published to the UI
   → User hits Enter → selected Item's primary Action runs
   → Panel hides with exit animation
```

### Provider pattern

Every source of results implements one protocol, which keeps features independent:

```swift
protocol SearchProvider: Sendable {
    var id: String { get }
    func results(for query: String) async -> [SearchItem]
}

struct SearchItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: ItemIcon
    let kind: ItemKind           // app, file, clipboard, command, calc...
    let score: Double
    let actions: [ItemAction]    // first one is the primary action
}
```

Providers: `AppProvider`, `FileProvider`, `CalculatorProvider`, `ClipboardProvider`, `WindowCommandProvider`, `SnippetProvider`, `AIProvider`, `MCPCheckProvider`.

### Folder structure

```
Glink/
├── App/
│   ├── GlinkApp.swift              # @main, menu bar item, LSUIElement
│   └── AppDelegate.swift
├── Panel/
│   ├── CommandPanel.swift          # NSPanel subclass
│   ├── PanelController.swift       # show/hide, positioning, focus
│   └── PanelRootView.swift
├── Search/
│   ├── SearchEngine.swift          # runs providers, merges, ranks
│   ├── FuzzyMatcher.swift
│   └── RankingStore.swift          # usage frequency + recency
├── Providers/
│   ├── AppProvider.swift
│   ├── FileProvider.swift
│   ├── CalculatorProvider.swift
│   ├── ClipboardProvider.swift
│   ├── WindowCommandProvider.swift
│   ├── SnippetProvider.swift
│   ├── AIProvider.swift
│   └── MCPCheckProvider.swift
├── System/
│   ├── HotkeyManager.swift
│   ├── ClipboardMonitor.swift      # NSPasteboard watcher
│   ├── WindowManager.swift         # AXUIElement wrapper
│   ├── TextExpander.swift          # CGEventTap
│   └── PermissionsManager.swift
├── UI/
│   ├── Components/                 # SearchField, ResultRow, ActionPanel, Toast...
│   ├── Onboarding/
│   ├── Settings/
│   └── DesignSystem/
│       ├── Motion.swift            # all animation tokens
│       ├── Theme.swift             # colors, spacing, radii
│       └── Typography.swift
├── Data/
│   └── Models.swift                # SwiftData models
└── Tests/
```

---

## 6. UI/UX Design Specification

### 6.1 The command panel

| Property | Value |
|---|---|
| Size | 750 × 474 pt (grows/shrinks height with results, max 474) |
| Position | Horizontally centered, ~20% from top of the active screen |
| Corner radius | 16 pt (continuous) |
| Material | `.glassEffect()` on macOS 26; `NSVisualEffectView` `.hudWindow` on macOS 14–15 |
| Shadow | Soft, large radius (30 pt), low opacity (0.25 dark / 0.15 light) |
| Border | 0.5 pt inner stroke, white 10–15% opacity, for a realistic edge highlight |

**Layout (top to bottom):**
1. **Search field** — 56 pt tall, 22 pt system font, left magnifying-glass symbol, placeholder "Search apps, files, and commands…"
2. **Divider** — hairline
3. **Results list** — rows grouped by section ("Applications", "Files", "Clipboard", "Commands")
4. **Footer bar** — 40 pt; left: current context icon + name; right: hints like `↵ Open` and `⌘K Actions`

### 6.2 Result rows

| Property | Value |
|---|---|
| Height | 44 pt |
| Icon | 24 × 24 pt (real app icons via `NSWorkspace.shared.icon(forFile:)`) |
| Title | 14 pt, primary color |
| Subtitle | 12 pt, secondary color |
| Accessory | Right-aligned type label ("Application", "Folder") and shortcut hint |
| Selection | Rounded 8 pt highlight using the system accent color at ~18% opacity |
| Hover | Subtle 6% fill; moving the mouse does **not** steal keyboard selection until it actually moves |

### 6.3 Typography and spacing
- Font: SF Pro (system). Monospaced digits for calculator and counts.
- Spacing scale: 4, 8, 12, 16, 24, 32 pt.
- Text supports Dynamic Type–style scaling via a "Text size" setting.

### 6.4 Color
- Use semantic system colors only (`.primary`, `.secondary`, `Color.accentColor`) so Light, Dark, and Increase Contrast work automatically.
- Section headers: 11 pt semibold, secondary color, uppercase tracking +0.5.

### 6.5 Keyboard map
| Key | Action |
|---|---|
| ⌥ Space | Toggle panel |
| ↑ / ↓ | Move selection |
| ↵ | Run primary action |
| ⌘K | Open actions panel |
| ⌘1–9 | Jump to result |
| Esc | Clear text → go back → close panel |
| ⌘, | Settings |
| Tab | Autocomplete / enter command arguments |

### 6.6 States
| State | What the user sees |
|---|---|
| Empty query | "Recent" and "Suggestions" sections, never a blank panel |
| No results | Friendly message + actions: "Search the web for '…'", "Search files" |
| Loading | Skeleton rows with shimmer (only if results take > 120 ms) |
| Permission missing | Inline card explaining why, with an "Open System Settings" button |
| Error | Toast at bottom with retry |

---

## 7. Animation & Motion System

Motion is a key feature of Glink, so it lives in one central file with reusable tokens. **Rule:** animations make the app feel physical and alive, but they must never make the user wait.

### 7.1 Motion tokens

```swift
import SwiftUI

enum Motion {
    // Springs feel physical; prefer them over easing curves.
    static let snappy   = Animation.spring(response: 0.24, dampingFraction: 0.86)
    static let smooth   = Animation.spring(response: 0.35, dampingFraction: 0.90)
    static let bouncy   = Animation.spring(response: 0.40, dampingFraction: 0.70)
    static let gentle   = Animation.easeOut(duration: 0.18)

    // Panel
    static let panelIn  = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let panelOut = Animation.easeIn(duration: 0.12)

    // Stagger delay between list rows on first appearance
    static let staggerStep: Double = 0.018
    static let staggerMaxRows = 8
}
```

### 7.2 Reduce Motion support (required)

```swift
struct MotionAware: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeInOut(duration: 0.1) : animation, value: value)
    }
}
```

When Reduce Motion is on: replace scale/slide/bounce with short cross-fades. Keep everything functional.

### 7.3 Animation catalog

| # | Moment | Animation | Spec |
|---|---|---|---|
| 1 | **Panel appears** | Scale 0.96 → 1.0 + opacity 0 → 1 + slight 6 pt drop | `Motion.panelIn` |
| 2 | **Panel hides** | Scale 1.0 → 0.98 + fade out | `Motion.panelOut` (fast, 120 ms) |
| 3 | **Selection highlight** | Highlight **slides** between rows instead of jumping | `matchedGeometryEffect`, `Motion.snappy` |
| 4 | **Results change while typing** | Rows insert/remove with fade + 4 pt vertical move; existing rows glide to new positions | `.transition(.opacity.combined(with: .offset(y: 4)))`, `Motion.smooth` |
| 5 | **First open stagger** | Rows cascade in, 18 ms apart, max 8 rows | Only on panel open, never while typing |
| 6 | **Panel height** | Panel smoothly resizes as result count changes | Animate frame height, `Motion.smooth` |
| 7 | **Actions panel (⌘K)** | Slides up from footer + fade, list behind dims slightly | `.move(edge: .bottom)` + opacity, `Motion.snappy` |
| 8 | **Calculator result** | Digits roll as the answer changes | `.contentTransition(.numericText())` |
| 9 | **Copy feedback** | Checkmark symbol bounces + "Copied" toast slides up | `.symbolEffect(.bounce, value:)` + toast spring |
| 10 | **Section headers** | Fade in when a section first gets results | `Motion.gentle` |
| 11 | **Search icon** | Magnifying glass morphs to a spinner when loading, back when done | `.contentTransition(.symbolEffect(.replace))` |
| 12 | **Loading skeleton** | Soft shimmer sweep across placeholder rows | `PhaseAnimator` / repeating gradient offset |
| 13 | **AI response** | Text streams in word by word with a blinking caret | Incremental text + caret opacity animation |
| 14 | **Window snapping** | Preview overlay of the target area appears, then the window moves | Overlay window with `Motion.smooth` |
| 15 | **Clipboard image preview** | Thumbnail zooms from row into a detail pane | `matchedGeometryEffect` between row and preview |
| 16 | **Error / invalid input** | Search field gives a short horizontal shake | `KeyframeAnimator` (3 quick offsets) |
| 17 | **Onboarding** | Each step slides horizontally; illustrations animate with keyframes | `.transition(.push(from: .trailing))` |
| 18 | **Permission granted** | Card turns green with checkmark draw-on animation | `.symbolEffect(.bounce)` + color transition |
| 19 | **Hover** | Row background fades in at 6% | `Motion.gentle` |
| 20 | **Trackpad haptic** | Light tap when snapping a window or reaching list ends | `NSHapticFeedbackManager` `.alignment` |

### 7.4 Key implementation examples

**Sliding selection highlight**

```swift
struct ResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            ItemIconView(icon: item.icon).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14))
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
    }
}
// In the list: .animation(Motion.snappy, value: selectedID)
```

**Panel entrance**

```swift
struct PanelRootView: View {
    @State private var isShown = false

    var body: some View {
        content
            .scaleEffect(isShown ? 1 : 0.96)
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : -6)
            .onAppear { withAnimation(Motion.panelIn) { isShown = true } }
    }
}
```

**Shake on invalid input**

```swift
.keyframeAnimator(initialValue: 0.0, trigger: shakeTrigger) { view, x in
    view.offset(x: x)
} keyframes: { _ in
    KeyframeTrack {
        SpringKeyframe(8, duration: 0.06)
        SpringKeyframe(-6, duration: 0.06)
        SpringKeyframe(3, duration: 0.06)
        SpringKeyframe(0, duration: 0.08)
    }
}
```

### 7.5 Motion rules
- Typing must **never** wait for an animation. Input is accepted from the first frame.
- Max duration for anything in the main panel: **350 ms**. Most should be under 250 ms.
- Stagger only on open, never on every keystroke (it would feel laggy).
- Animate **position, opacity, and scale**. Avoid animating blur radius on large areas (expensive).
- Check every animation in Instruments' **Animation Hitches** tool. Target zero hitches at 120 Hz on ProMotion displays.

---

## 8. Onboarding Flow (user-friendly first launch)

| Step | Screen | Content |
|---|---|---|
| 1 | **Welcome** | App icon animates in, one-line pitch, "Get Started" |
| 2 | **Choose your hotkey** | Live recorder; an animated keyboard highlights the chosen keys |
| 3 | **Permissions** | Cards for Accessibility (window snapping, snippets). Each card says *why* in one sentence and can be skipped |
| 4 | **Try it** | "Press ⌥ Space now" with a pulsing hint; completes when the user actually opens the panel |

Rules:
- Never request a permission before explaining it.
- Every permission is optional; features that need it show an inline "Enable" card later.
- Onboarding can be reopened from Settings.

---

## 9. Settings Window

Native `Settings` scene with a sidebar:

- **General:** hotkey, launch at login, panel position, text size
- **Appearance:** theme (System/Light/Dark), window style (Glass/Solid), animation level (Full / Reduced / Off)
- **Clipboard:** history length, ignored apps, clear history
- **Snippets:** list editor with live preview of expansion
- **AI:** API key (stored in Keychain), default model, test connection
- **Advanced:** reset ranking, export/import settings, debug logs

Settings changes apply live, with a subtle preview animation where relevant (e.g. changing window style morphs a preview panel).

---

## 10. System Integrations — Implementation Notes

| Feature | API | Notes |
|---|---|---|
| Floating panel | `NSPanel` with `.nonactivatingPanel`, `level = .floating`, override `canBecomeKey` → `true` | Pre-create at launch and keep hidden so it shows instantly |
| Global hotkey | KeyboardShortcuts package | Recorder view for Settings |
| App list | Scan `/Applications`, `/System/Applications`, `~/Applications`; watch for changes | Cache icons in memory |
| File search | `NSMetadataQuery` | Limit results; cancel previous query on each keystroke |
| Open items | `NSWorkspace.shared.open(_:)` | |
| Clipboard | Poll `NSPasteboard.general.changeCount` every ~0.5 s | **Skip** items marked `org.nspasteboard.ConcealedType` (password managers) |
| Window control | `AXUIElementCreateApplication`, `kAXFocusedWindowAttribute`, set `kAXPositionAttribute` / `kAXSizeAttribute` | Check `AXIsProcessTrustedWithOptions` first |
| Text expansion | `CGEvent.tapCreate` keyboard listener | Needs Accessibility permission; never log keystrokes |
| Launch at login | `SMAppService.mainApp.register()` | |
| Haptics | `NSHapticFeedbackManager.defaultPerformer` | Trackpads only |

---

## 11. Performance Budgets

| Metric | Target |
|---|---|
| Hotkey → panel visible | < 50 ms |
| Keystroke → results updated | < 30 ms for apps/commands; files stream in progressively |
| Idle CPU | ~0% |
| Idle memory | < 80 MB |
| Animation hitches | 0 in normal use |
| Cold launch | < 1 s |

Measure with Instruments every phase, not just at the end.

---

## 12. Privacy & Security

- All data stays **local** by default. No analytics in v1.
- Clipboard history ignores password-manager items and user-excluded apps.
- Text expander never stores or logs what the user types.
- AI requests only send text the user explicitly selects, and only when they run an AI command.
- API keys live in the **Keychain**, never in plain files.
- A "Privacy" page in Settings explains exactly what is stored and where.

---

## 13. Roadmap (10 weeks)

| Week | Focus | Done when… |
|---|---|---|
| 1 | Project setup, `NSPanel`, global hotkey, menu bar icon | ⌥ Space shows/hides an empty glass panel with entrance animation |
| 2 | Search field, result list, keyboard navigation, `Motion.swift` | Arrow keys move a **sliding** highlight; Esc behavior correct |
| 3 | App provider + fuzzy matcher + icons | Typing "xc" finds Xcode instantly; unit tests for matcher |
| 4 | File provider, calculator, empty/no-result states | Files stream in; calculator digits roll; no blank states anywhere |
| 5 | Actions panel (⌘K), toasts, copy feedback | All item actions work; animations polished |
| 6 | Clipboard history (with image previews) | History persists, searchable, password items skipped |
| 7 | Window management + snap preview + permissions flow | Windows snap with preview overlay; permission card works |
| 8 | Onboarding + Settings | New user goes from install to first search in < 60 seconds |
| 9 | Snippets, ranking by usage, AI command, MCP Config Check | Differentiator feature working end to end |
| 10 | Polish: Reduce Motion, accessibility audit, performance, signing, notarization, DMG | Passes Accessibility Inspector audit; zero hitches; notarized build |

---

## 14. Testing Plan

- **Unit tests (Swift Testing):** fuzzy matcher scores, ranking, calculator parsing, snippet placeholder expansion, MCP config rules.
- **UI tests (XCTest):** open panel, search, navigate, run action; include `performAccessibilityAudit()` so accessibility issues fail the build.
- **Manual checklist** each release: Light/Dark, Reduce Motion, Reduce Transparency, Increase Contrast, multiple monitors, full-screen apps, external keyboard.
- **Performance:** Time Profiler for search, Allocations for memory, Animation Hitches for motion.
- **Real users:** give a build to 3–5 friends for a week; watch them use it without helping.

---

## 15. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Too many animations make it feel slow | Strict motion rules (Section 7.5), "Animation level" setting, test on older Macs |
| Accessibility permission confuses users | Clear onboarding cards, features degrade gracefully without it |
| Scope creep | Ship v1.0 first; v1.1/v2 features wait |
| Panel focus bugs with full-screen apps | Test early (week 1–2), use `.canJoinAllSpaces` + `.fullScreenAuxiliary` collection behavior |
| Clipboard privacy concerns | Concealed-type filtering, exclusions, one-click clear |

---

## 16. Portfolio Deliverables

1. **GitHub repo** with a strong README: GIF demos of the animations, architecture diagram, setup steps.
2. **Notarized DMG** in GitHub Releases so anyone can install it.
3. **Write-up on the portfolio site:** "Building a Raycast-style launcher in Swift — the hardest problems I solved" (instant panel, sliding selection, Accessibility API, performance numbers).
4. **Demo video** (60–90 seconds) showing onboarding → search → clipboard → window snap → MCP Config Check.

---

## 17. Next Step

Start Week 1: create the Xcode project (macOS App, SwiftUI lifecycle), set `LSUIElement = YES`, add the KeyboardShortcuts package, build `CommandPanel` + `PanelController`, and get ⌥ Space showing an animated glass panel.
