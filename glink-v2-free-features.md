# Glink v2 — Free Features + Cursor Prompts

Everything in this file can be built **without paying for anything**: no AI API keys, no cloud services, no subscriptions. All AI runs on the Mac using Apple's own frameworks.

Goal for v2: **"The private, secure AI launcher for Mac."**

---

## 1. What's free and what costs money

| Feature | Cost | Free tools used |
|---|---|---|
| On-device AI (rewrite, summarize, ask) | Free | Apple **Foundation Models** framework (macOS 26, Apple Silicon, Apple Intelligence on) |
| Safe MCP mode (scan, permissions, audit log) | Free | Official MCP Swift SDK, your Tollgate logic |
| Search your Mac by meaning | Free | Apple **NaturalLanguage** (`NLEmbedding`), **Vision** OCR, SQLite/SwiftData |
| Context-aware suggestions | Free | Local usage stats, simple scoring in Swift |
| Action preview + undo | Free | Plain Swift |
| Running Glink on your own Mac | Free | Xcode with a free Apple ID ("Personal Team" signing) |
| Sharing Glink on GitHub | Free | Unsigned/ad-hoc signed `.zip` in GitHub Releases |
| **Notarized download with no warnings** | **$99/year** | Apple Developer Program (only needed for smooth installs by other people) |

**Free sharing note:** without notarization, people who download Glink must go to **System Settings → Privacy & Security → Open Anyway** the first time. Put these steps in the README. Fine for a portfolio; upgrade to notarization later if you want.

**On-device AI note:** Foundation Models needs macOS 26 on an Apple Silicon Mac with Apple Intelligence turned on. Glink must check availability and hide AI features gracefully on other Macs.

---

## 2. How to use these prompts in Cursor

1. **Commit your code to git before each prompt**, so you can roll back if something breaks.
2. **One prompt per chat session.** Don't paste everything at once.
3. Keep `glink.md` (the original plan) in the project root so Claude can read it.
4. Each prompt asks Claude to **plan first, then build**. Read the plan and correct it before saying "go ahead."
5. After each phase: build in Xcode, test it yourself, then move to the next prompt.
6. If Claude gets something wrong, paste the exact Xcode error back to it.

Build in this order: **Prompt 0 → 1 → 2A → 2B → 2C → 2D → 3 → 4 → 5 → 6.**

---

## Prompt 0 — Understand the codebase (run first)

```
Read this whole Glink project and glink.md in the project root. Glink is my native macOS launcher (Swift 6, SwiftUI + AppKit, NSPanel, SearchProvider pattern, Motion.swift animation tokens).

Don't change any code yet. Give me:
1. A short map of the architecture as it actually exists (files, main types, how a search flows from hotkey to result).
2. Where the SearchProvider protocol, Motion tokens, Settings, and permissions handling live.
3. Anything in the code that differs from glink.md.
4. Any bugs, warnings, or risky code you notice.

I'm about to add v2 features (on-device AI, safe MCP mode, semantic search, suggestions, undo), so point out anything that would make those harder.
```

---

## Prompt 1 — Free on-device AI

```
Add on-device AI to Glink using Apple's Foundation Models framework. No cloud APIs, no API keys — everything must run locally and for free.

Plan first and show me the plan before writing code.

Requirements:
- Create an AIService that wraps Foundation Models (SystemLanguageModel / LanguageModelSession).
- Check SystemLanguageModel.default.availability. If unavailable (older macOS, Intel Mac, Apple Intelligence off), hide AI commands and show a friendly inline card explaining why. Gate code with `if #available(macOS 26, *)` so the app still builds and runs on macOS 14+.
- Add an AIProvider (SearchProvider) with these commands:
  - "Ask AI": type a question after the command, get an answer in the panel.
  - "Rewrite selected text" (more professional / shorter / fix grammar).
  - "Summarize clipboard".
- Stream responses into the panel word by word with a blinking caret (see animation #13 in glink.md). Use the existing Motion tokens.
- Show a small "On-device · Private" badge on every AI result.
- Add an "AI" section in Settings: on/off toggle, availability status.
- Never send text anywhere off the Mac.

Done when: I can open Glink, type "ask what is a closure in swift", and see a streamed on-device answer; on an unsupported Mac the AI commands are hidden with an explanation. Add unit tests for AIService availability handling (mock the model).
```

---

## Prompt 2A — MCP config scanner (Tollgate inside Glink)

```
Add an "MCP Config Check" feature to Glink. It scans MCP server configuration files on this Mac and gives each server a risk score. Everything runs locally.

Plan first and show me the plan before writing code.

Requirements:
- Find MCP config files in the common locations (e.g. Claude Desktop's claude_desktop_config.json, Cursor's mcp.json in ~/.cursor and project folders, VS Code settings). Make the list of locations easy to extend.
- Parse each server entry (command, args, env, url).
- Create a rule engine with rules like:
  - Secrets/API keys written in plain text in env or args (HIGH)
  - Server runs via npx/uvx with an unpinned package version (MEDIUM)
  - Command runs a shell (bash -c, sh -c) or has broad filesystem access like "/" or "~" (HIGH)
  - Remote server over http:// instead of https:// (HIGH)
  - Unknown or unverified publisher (LOW)
  Each rule: id, severity, title, plain-English explanation, how to fix.
- Score each server 0–100 and give an overall grade (A–F).
- Add an MCPCheckProvider command "Check MCP Security" that shows results in the panel: list of servers with grade badges; selecting one shows its findings.
- Animations: grade badges count up with .contentTransition(.numericText()); findings slide in with the existing stagger rules.
- Never display full secret values — mask them (show first 4 chars only).

Done when: running "Check MCP Security" lists my real MCP servers with grades and findings. Add unit tests for every rule using sample config JSON files in the test bundle.
```

---

## Prompt 2B — Glink as an MCP client

```
Make Glink an MCP client so tools from connected MCP servers appear as Glink commands.

Plan first and show me the plan before writing code.

Requirements:
- Use the official MCP Swift SDK (modelcontextprotocol/swift-sdk) via Swift Package Manager. Support stdio servers (launched with Process) first; HTTP servers can come later.
- Settings → "MCP Servers": add, remove, enable/disable servers. Before a server can be enabled, run the MCP Config Check rules on it and show its grade. If the grade is D or F, require the user to confirm with a clear warning.
- On connect, list the server's tools. Each tool becomes a searchable Glink command: title = tool name, subtitle = server name + description.
- Selecting a tool opens a small form generated from the tool's JSON input schema (text fields, toggles, number fields). Run the tool and show the result in the panel.
- Handle failures nicely: server crashes, timeouts (10s default), invalid output — toast with retry.
- Clean up: terminate server processes when Glink quits or a server is disabled.

Done when: I can add a local MCP server (e.g. the filesystem reference server), search for one of its tools in Glink, fill in the form, and see the result.
```

---

## Prompt 2C — Permission prompts + audit log

```
Add a permission and audit layer for every MCP tool call in Glink.

Plan first and show me the plan before writing code.

Requirements:
- Classify tools by risk using name/description/schema heuristics: read-only, writes data, deletes data, runs commands, network access. Let the user override the classification in Settings.
- Before any non-read-only tool call, show a permission sheet inside the panel: tool name, server, risk level, the exact arguments that will be sent. Buttons: Allow once / Always allow for this tool / Deny. The sheet slides up from the footer (animation #7 in glink.md).
- Store "always allow" decisions per server+tool; make them revocable in Settings.
- Audit log: record every tool call (timestamp, server, tool, arguments, result summary, allowed/denied, duration) in SwiftData. Mask secrets in arguments.
- Add a "MCP Activity" command that shows the audit log, searchable and filterable by server, with an "Export as JSON" action.

Done when: a write/delete tool always asks before running, denied calls never reach the server, and every call shows up in MCP Activity. Add unit tests for the risk classifier and permission decisions.
```

---

## Prompt 2D — Prompt-injection detection in tool results

```
Add prompt-injection detection for MCP tool outputs in Glink.

Plan first and show me the plan before writing code.

Requirements:
- Create an InjectionDetector that scans every tool result before it is shown or passed to the AI.
- Layer 1 (always on, fast): pattern rules for phrases like "ignore previous instructions", "you are now", "system prompt", hidden instructions in HTML comments, zero-width/invisible Unicode characters, base64 blobs with instructions, requests to call other tools or send data to URLs.
- Layer 2 (optional, if Foundation Models is available): ask the on-device model to classify suspicious results as safe / suspicious / malicious with a one-line reason. Only run it when Layer 1 finds something or the result is from an untrusted server.
- If a result is flagged: show a yellow/red warning banner above the result with the reason, highlight the suspicious text, and never pass it to the AI without the user's confirmation.
- Log detections in the MCP Activity audit log.
- Build a test set of at least 30 sample tool outputs (15 clean, 15 containing injections of different types) in the test bundle and write tests that report detection rate and false positives.

Done when: tests show the detection rate and false-positive rate, and a flagged result shows a clear warning in the panel. Print the detection rate and false-positive numbers in the test output so I can put them in my README.
```

---

## Prompt 3 — Search your Mac by meaning

```
Add semantic search to Glink so users can find files by meaning, not just by name. Everything must run on-device and for free.

Plan first and show me the plan before writing code.

Requirements:
- Indexing (background, low priority):
  - Folders: let the user choose folders in Settings (default: Documents, Desktop, Downloads). Respect macOS folder permission prompts.
  - Text from .txt, .md, .pdf (PDFKit), .docx if easy, and images/screenshots using Vision OCR (VNRecognizeTextRequest).
  - Split text into chunks (~500 characters with overlap).
  - Embed chunks with Apple's NaturalLanguage framework (NLEmbedding.sentenceEmbedding or NLContextualEmbedding). No external models or APIs.
  - Store chunks, vectors, file path, and modified date in SQLite or SwiftData.
  - Watch folders for changes (FSEvents / DispatchSource) and re-index only changed files.
- Search:
  - Add a "Semantic" section in results. Embed the query, rank chunks by cosine similarity, group by file, show the best matching snippet with the matched part highlighted.
  - Combine with normal name search (hybrid ranking) so exact name matches still win.
  - Results must appear in under 100 ms for an index of ~10,000 chunks; if slower, add a simple in-memory vector cache.
- UI: indexing progress in Settings and as a subtle progress ring in the footer; result rows show a small "matched by meaning" icon.
- Privacy: the index never leaves the Mac; add "Clear index" and "Pause indexing" in Settings.
- CPU: indexing must pause when on battery below 20% or when the user is actively typing in Glink.

Done when: typing "invoice from september" finds a PDF invoice even if the file is named "scan_0042.pdf", and searching text that appears inside a screenshot finds that screenshot. Add tests for chunking and ranking.
```

---

## Prompt 4 — Context-aware suggestions

```
Add context-aware suggestions to Glink's empty state (when the search field is empty).

Plan first and show me the plan before writing code.

Requirements:
- Record usage events locally: item id, time of day, day of week, frontmost app when Glink opened, and connected Wi-Fi network name if available without extra permissions (skip it otherwise).
- Scoring: for the current context, score each item by frequency + recency + time-of-day similarity + frontmost-app match. Keep the formula simple, documented, and in one file.
- Empty state shows a "Suggested" section with the top 5 items and a short reason under each ("You usually open this around 10 am", "Often used with Xcode").
- Settings: toggle suggestions on/off, "Reset learning" button.
- Animations: suggestions fade and slide in with the first-open stagger only.
- All data stays local.

Done when: after a few days of use, the Suggested section reflects my habits, and each suggestion explains why. Add unit tests for the scoring function with fake usage data.
```

---

## Prompt 5 — Action preview + undo

```
Add action previews and undo to Glink.

Plan first and show me the plan before writing code.

Requirements:
- Create an UndoCenter that records reversible actions:
  - Window moved/resized → restore previous frame.
  - File moved to Trash → restore from Trash (use FileManager.trashItem's resulting URL).
  - Clipboard replaced → restore previous clipboard contents.
  - Snippet expanded → remove the expanded text if possible.
  - AI rewrite applied → restore original text.
- After any reversible action, show a toast "Done · ⌘Z to undo" for 5 seconds. Pressing ⌘Z in Glink (or clicking Undo) reverses the last action. Toast slides up, shrinks its progress bar as time runs out.
- Before any destructive action (delete, overwrite, MCP write/delete tool), show a preview of exactly what will change, with Confirm / Cancel.
- Add a "Recent Actions" command listing the last 20 actions with an Undo button on each that is still reversible.

Done when: snapping a window, trashing a file, or applying an AI rewrite can all be undone from Glink. Add unit tests for UndoCenter.
```

---

## Prompt 6 — Free release on GitHub

```
Prepare Glink for a free public release on GitHub (no paid Apple Developer account).

Requirements:
- A build script (scripts/release.sh) that archives a Release build, ad-hoc signs it, and creates Glink.zip.
- A README.md with: one-line pitch ("The private, secure AI launcher for Mac"), GIF placeholders for each major feature, feature list, system requirements (macOS 14+, macOS 26 + Apple Silicon for AI), installation steps including System Settings → Privacy & Security → Open Anyway, permissions explained (Accessibility, folder access) and why each is needed, privacy section (everything local), architecture diagram in Mermaid, and the injection-detection test numbers from Prompt 2D.
- A CHANGELOG.md for v2.0.
- A GitHub Actions workflow that builds and runs tests on every push (macos runner).
- Check the whole app for leftover debug code, print statements, hardcoded paths, and TODOs, and list them for me.

Done when: I can run scripts/release.sh and upload Glink.zip to a GitHub Release, and the README is ready to publish.
```

---

## 3. After v2

- Record a 60–90 second demo video: launcher → on-device AI → MCP security check → permission prompt → injection warning → semantic search → undo.
- Write a portfolio post: **"Building a private, secure AI launcher for Mac"** with the injection-detection numbers and the hardest technical problems.
- Use the MCP security work in cold emails to AI startups.
