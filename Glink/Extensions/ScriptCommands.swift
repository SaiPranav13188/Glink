import AppKit
import GlinkCore
import SwiftUI

/// v2 script commands: executable scripts in ~/Library/Application Support/Glink/Scripts become
/// commands. Metadata lives in comments (Raycast's `@raycast.*` keys work too):
///
///     # @glink.title Say Hello
///     # @glink.mode compact            (silent | compact | fullOutput)
///     # @glink.icon 👋                  (emoji, or sf:symbol.name)
///     # @glink.argument1 Name          (optional: Tab or ↵ asks for one argument)
///     # @glink.description Greets you
struct ScriptCommand: Sendable, Hashable {
    enum Mode: String, Sendable { case silent, compact, fullOutput }
    let path: String
    let title: String
    let mode: Mode
    let icon: String?
    let argument: String?
    let description: String?

    static func parse(path: String, text: String) -> ScriptCommand? {
        var meta: [String: String] = [:]
        for line in text.split(separator: "\n").prefix(40) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("#") || t.hasPrefix("//") else { continue }
            for prefix in ["@glink.", "@raycast."] {
                guard let r = t.range(of: prefix) else { continue }
                let rest = t[r.upperBound...]
                guard let space = rest.firstIndex(of: " ") else { continue }
                meta[String(rest[..<space])] = rest[rest.index(after: space)...].trimmingCharacters(in: .whitespaces)
            }
        }
        guard let title = meta["title"], !title.isEmpty else { return nil }
        let argument = meta["argument1"].map { arg -> String in
            // Raycast style: { "type": "text", "placeholder": "Name" }
            if let r = arg.range(of: #""placeholder"\s*:\s*"([^"]+)""#, options: .regularExpression) {
                return String(arg[r]).components(separatedBy: "\"").dropLast().last ?? "Argument"
            }
            return arg
        }
        return ScriptCommand(path: path, title: title, mode: Mode(rawValue: meta["mode"] ?? "") ?? .compact,
                             icon: meta["icon"], argument: argument, description: meta["description"] ?? meta["packageName"])
    }
}

struct ScriptOutput: Hashable, Sendable {
    let title: String
    let output: String
    let exitCode: Int32
}

enum ScriptRunner {
    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Glink/Scripts", directoryHint: .isDirectory) }

    /// Runs a script off the main thread with a 30 s timeout. Only ever called on an explicit user action.
    static func run(_ script: ScriptCommand, argument: String?) async -> ScriptOutput {
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            let executable = FileManager.default.isExecutableFile(atPath: script.path)
            p.executableURL = URL(fileURLWithPath: executable ? script.path : "/bin/sh")
            p.arguments = (executable ? [] : [script.path]) + (argument.map { [$0] } ?? [])
            p.currentDirectoryURL = folder
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch {
                return ScriptOutput(title: script.title, output: error.localizedDescription, exitCode: -1)
            }
            let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            timeout.cancel()
            return ScriptOutput(title: script.title, output: String(decoding: data, as: UTF8.self), exitCode: p.terminationStatus)
        }.value
    }

    /// Creates the folder with two examples the first time it's opened.
    static func ensureFolder() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { return }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let examples: [(String, String)] = [
            ("hello.sh", """
            #!/bin/bash
            # @glink.title Say Hello
            # @glink.mode compact
            # @glink.icon 👋
            # @glink.argument1 Name
            # @glink.description Example script command

            echo "Hello, ${1:-world}!"
            """),
            ("disk-usage.sh", """
            #!/bin/bash
            # @glink.title Disk Usage
            # @glink.mode fullOutput
            # @glink.icon sf:internaldrive
            # @glink.description Free space on every volume

            df -h | grep -E "^/dev|Filesystem"
            """),
        ]
        for (name, text) in examples {
            let url = folder.appending(path: name)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}

@MainActor
final class ScriptCommandProvider: SearchProvider {
    let id = "scripts"
    let sectionTitle = "Script Commands"
    let sectionOrder = 6
    let limit = 5

    private var scripts: [ScriptCommand] = []
    private var lastScan = Date.distantPast

    private func rescanIfNeeded() {
        guard Date().timeIntervalSince(lastScan) > 3 else { return }
        lastScan = Date()
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: ScriptRunner.folder.path)) ?? []
        scripts = files.sorted().compactMap { name in
            let path = ScriptRunner.folder.appending(path: name).path
            guard !name.hasPrefix("."), let data = fm.contents(atPath: path), data.count < 200_000 else { return nil }
            return ScriptCommand.parse(path: path, text: String(decoding: data, as: UTF8.self))
        }
    }

    func results(for query: String) async -> [SearchItem] {
        rescanIfNeeded()
        let q = FuzzyMatcher.prepareQuery(query)
        return scripts.compactMap { s in
            guard let m = MatchTarget(title: s.title, keywords: ["script", s.description ?? ""]).match(q) else { return nil }
            return Self.item(for: s, score: m.score * 0.9, indices: m.matchedIndices)
        }
    }

    func item(withID id: String) -> SearchItem? {
        rescanIfNeeded()
        return scripts.first { "script:\($0.path)" == id }.map { Self.item(for: $0, score: 0, indices: []) }
    }

    static func item(for s: ScriptCommand, score: Double, indices: [Int]) -> SearchItem {
        let icon: ItemIcon = {
            if let i = s.icon, i.hasPrefix("sf:") { return .symbol(String(i.dropFirst(3)), tint: .gray) }
            return .symbol("terminal", tint: .gray)
        }()
        var item = SearchItem(id: "script:\(s.path)", title: (s.icon.flatMap { $0.hasPrefix("sf:") ? nil : $0 + " " } ?? "") + s.title,
                              subtitle: s.description, icon: icon, kind: .command, score: score, matchedIndices: indices,
                              accessory: "Script")
        item.actions = ScriptActions.make(for: s, argument: nil)
        if let placeholder = s.argument {
            item.argumentPlaceholder = placeholder
            item.requiresArgument = true
            item.runWithArgument = { arg in await ScriptActions.run(s, argument: arg) }
        }
        return item
    }
}

@MainActor
enum ScriptActions {
    static func make(for s: ScriptCommand, argument: String?) -> [ItemAction] {
        [
            ItemAction(id: "run", title: "Run Script", symbol: "play.fill", shortcut: .returnKey) { await run(s, argument: argument) },
            ItemAction(id: "edit", title: "Open in Editor", symbol: "pencil", shortcut: KeyHint(.command, "e")) {
                NSWorkspace.shared.open([URL(fileURLWithPath: s.path)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                        configuration: NSWorkspace.OpenConfiguration())
                return .dismiss
            },
            ItemAction(id: "reveal", title: "Show in Finder", symbol: "folder", shortcut: .cmdReturn) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.path)])
                return .dismiss
            },
        ]
    }

    static func run(_ s: ScriptCommand, argument: String?) async -> ActionOutcome {
        let result = await ScriptRunner.run(s, argument: argument)
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode != 0 {
            return .push(.scriptOutput(result))
        }
        switch s.mode {
        case .silent: return .dismissWithHUD("Ran \(s.title)")
        case .compact:
            let last = trimmed.split(separator: "\n").last.map(String.init) ?? "Ran \(s.title)"
            return .dismissWithHUD(String(last.prefix(80)))
        case .fullOutput: return .push(.scriptOutput(result))
        }
    }

    static func outputActions(_ o: ScriptOutput) -> [ItemAction] {
        [ItemAction(id: "copy", title: "Copy Output", symbol: "doc.on.doc", shortcut: .returnKey) {
            Paster.copy(o.output)
            return .dismissWithHUD("Copied to Clipboard")
        }]
    }
}

/// Full output of a script (fullOutput mode, or any script that exits with an error).
struct ScriptOutputView: View {
    let output: ScriptOutput
    let filter: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: output.exitCode == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill").accessibilityHidden(true)
                    .foregroundStyle(output.exitCode == 0 ? Color.green : Color.red)
                Text(output.exitCode == 0 ? "Finished" : "Exited with code \(output.exitCode)")
                    .font(.system(size: 12, weight: .medium))
            }
            ScrollView {
                Text(lines.isEmpty ? "(no output)" : lines)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(16)
    }

    private var lines: String {
        guard !filter.isEmpty else { return output.output }
        return output.output.split(separator: "\n").filter { $0.localizedCaseInsensitiveContains(filter) }.joined(separator: "\n")
    }
}
