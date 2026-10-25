# Changelog

## 2.0 — "The private, secure AI launcher for Mac"

Everything new in 2.0 runs on your Mac. No API keys, no cloud services.

### On-device AI
- Ask AI, rewrite selected text (more professional, shorter, fix grammar), summarize the clipboard and explain a selection, all with Apple's **Foundation Models**.
- Answers stream word by word with a blinking caret and carry an **On-device · Private** badge.
- On Macs that can't run the model, the commands are hidden and an inline card explains why. The Claude cloud integration from 1.0 has been removed.

### Safe MCP
- **Check MCP Security** uses Tollgate's rules engine and adds Glink's own rules, including the new unverified-publisher check. Servers get A–F grades that count up, and secrets are masked to their first 4 characters.
- **Glink is an MCP client.** It uses the official Swift SDK over stdio. Tools from your servers become Glink commands, with forms generated from their JSON schemas. Calls time out after 10 seconds, and server processes are cleaned up when you disable a server or quit.
- **Permissions.**
  - Tools are classified as read-only, network, writes, deletes or runs commands; you can override this.
  - Anything that isn't read-only asks first, showing the exact arguments: Allow once, Always allow or Deny.
  - Denied calls never reach the server.
- **MCP Activity.** Every call is logged (secrets masked), searchable, filterable by `server:` and exportable as JSON.
- **Prompt-injection detection.**
  - Fast pattern rules check every result for overrides, role changes, hidden HTML comments, invisible Unicode, base64 instructions, exfiltration and credential requests.
  - Results that are flagged, or that come from an untrusted server, get a second check by the on-device model.
  - Flagged results show a warning banner with the suspicious text highlighted, and never reach the AI without your confirmation.

### Search by meaning
- Indexes text, Markdown, PDFs (scanned pages via Vision OCR), Word, RTF and screenshots in folders you choose.
- Uses Apple's NaturalLanguage embeddings and hybrid ranking, so an exact name match still wins. Searching 10,000 chunks takes about 40 ms.
- Watches the folders for changes. Indexing pauses while you type and on low battery, with a progress ring in the footer, Pause and Clear.

### Context-aware suggestions
- The empty search field shows **Suggested** items with a reason, such as "You usually open this around 10 am" or "Often used with Xcode".
- Toggle and Reset learning in Settings.

### Undo and previews
- **⌘Z** undoes window snaps, files moved to Trash, clipboard changes, snippet expansions and AI rewrites.
- An undo toast with a draining bar appears after each one, and **Recent Actions** lists the last 20.
- Destructive actions preview exactly what will change first.

### Also
- Script commands, floating notes and menu bar mini mode.
- Playful mascots: a kitten, a puppy and trending and seasonal friends visit now and then. They respect Reduce Motion and can be turned off.
- Free release: `scripts/release.sh` builds an ad-hoc signed `Glink.zip`. CI builds and tests every push.

## 1.0
- Launcher, app and file search, calculator, clipboard history, window management, snippets, quicklinks, onboarding, settings, Sparkle updates, MCP Config Check.
