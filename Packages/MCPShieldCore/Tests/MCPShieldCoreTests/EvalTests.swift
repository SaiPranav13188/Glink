import Foundation
import Testing
@testable import MCPShieldCore

/// Runs every config in EvalSet/ and prints precision and recall per rule (section 13).
@Suite struct EvalTests {
    static let evalDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "EvalSet")   // vendored into Glink at Packages/MCPShieldCore/EvalSet

    static let rules = ConfigRules.allRuleIDs + ["SEC-001"]

    /// Fake secrets only, filled in at run time so the repo holds no key-shaped strings.
    static let fakes: [String: String] = [
        "FAKE_GITHUB": "ghp_" + String(repeating: "FAKE0", count: 8),
        "FAKE_GITHUB_PAT": "github_pat_11FAKE0000_" + String(repeating: "FAKEfake", count: 7),
        "FAKE_AWS": "AKIA" + "FAKEFAKEFAKEFAKE",
        "FAKE_GOOGLE": "AIza" + String(repeating: "Fake_", count: 7),
        "FAKE_ANTHROPIC": "sk-ant-api03-" + String(repeating: "fakeFAKE", count: 5),
        "FAKE_OPENAI": "sk-proj-" + String(repeating: "FakeFake", count: 5),
        "FAKE_SLACK": "xoxb-000000000000-0000000000000-" + String(repeating: "FAKEfake", count: 3),
        "FAKE_HEX": "f4ke" + String(repeating: "0123456789abcdef", count: 2) + "f4ke",
        // JSON-escaped newlines, since it is pasted inside a JSON string.
        "FAKE_PRIVATE_KEY": #"-----BEGIN OPENSSH PRIVATE KEY-----\nFAKEFAKEFAKEFAKE\n-----END OPENSSH PRIVATE KEY-----"#,
    ]

    /// CFG-006 needs real files with real permissions; git does not keep those, so build them here.
    static func makeFixtures() throws -> URL {
        let fm = FileManager.default
        let root = try tempDir()
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        func file(_ rel: String, _ mode: Int, dirMode: Int = 0o755) throws {
            let url = root.appending(path: rel)
            let dir = url.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: dirMode], ofItemAtPath: dir.path)
            try Data("#!/bin/sh\n".utf8).write(to: url)
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        }
        try file("world-writable/server", 0o777)
        try file("owner-only/server", 0o755)
        try file("scripts/index.js", 0o666)
        try file("shared-dir/server.py", 0o644, dirMode: 0o775)
        return root
    }

    struct Counts { var tp = 0, fp = 0, fn = 0 }

    @Test func precisionAndRecallPerRule() throws {
        let table = try Self.evaluate(Self.evalDir)
        print("\n=== EVAL RESULTS ===\n" + table + "=== END EVAL ===")
    }

    /// Configs written after the rules were tuned on the main set, and never tuned on.
    @Test func heldOutSet() throws {
        let table = try Self.evaluate(Self.evalDir.appending(path: "holdout"), minimumConfigs: 15)
        print("\n=== HELD-OUT RESULTS ===\n" + table + "=== END HELD-OUT ===")
    }

    /// Runs every config in `dir/configs` against `dir/labels.json` and returns the precision/recall table.
    static func evaluate(_ dir: URL, minimumConfigs: Int = 30) throws -> String {
        let labelsData = try Data(contentsOf: dir.appending(path: "labels.json"))
        let labels = try JSONDecoder().decode([String: [String: [String]]].self, from: labelsData)
        #expect(labels.count >= minimumConfigs, "the plan asks for 30 or more configs")

        let fixtures = try makeFixtures()
        var subs = fakes
        subs["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        subs["FIXTURES"] = fixtures.path

        var counts: [String: Counts] = [:]
        var mistakes: [String] = []
        var serverCount = 0
        for (file, expectedByServer) in labels.sorted(by: { $0.key < $1.key }) {
            var text = try String(contentsOf: dir.appending(path: "configs/\(file)"), encoding: .utf8)
            for (k, v) in subs { text = text.replacingOccurrences(of: "{{\(k)}}", with: v) }
            let servers = ConfigDiscovery.parse(data: Data(text.utf8), label: "Eval", path: file)
            #expect(Set(servers.map(\.name)) == Set(expectedByServer.keys), "\(file): labels and servers differ")

            for s in servers {
                serverCount += 1
                let result = Scanner.scan(s)
                let fired = Set(result.findings.map(\.ruleID))
                let expected = Set(expectedByServer[s.name] ?? [])
                for rule in rules {
                    switch (fired.contains(rule), expected.contains(rule)) {
                    case (true, true): counts[rule, default: .init()].tp += 1
                    case (true, false): counts[rule, default: .init()].fp += 1; mistakes.append("FP \(rule) \(file) \(s.name)")
                    case (false, true): counts[rule, default: .init()].fn += 1; mistakes.append("FN \(rule) \(file) \(s.name)")
                    case (false, false): break
                    }
                }
                // No full fake secret may appear in any finding.
                let encoded = String(decoding: try JSONEncoder().encode(result.findings), as: UTF8.self)
                for (name, fake) in fakes where !name.hasSuffix("PRIVATE_KEY") {
                    #expect(!encoded.contains(fake), "\(file) \(s.name) leaked \(name)")
                }
            }
        }

        func pct(_ n: Int, _ d: Int) -> String { d == 0 ? "n/a" : String(format: "%.0f%%", 100.0 * Double(n) / Double(d)) }
        var table = "Evaluated \(labels.count) configs, \(serverCount) servers.\n\n"
        table += "| Rule | TP | FP | FN | Precision | Recall |\n|---|---|---|---|---|---|\n"
        var total = Counts()
        for rule in rules {
            let c = counts[rule] ?? .init()
            total.tp += c.tp; total.fp += c.fp; total.fn += c.fn
            table += "| \(rule) | \(c.tp) | \(c.fp) | \(c.fn) | \(pct(c.tp, c.tp + c.fp)) | \(pct(c.tp, c.tp + c.fn)) |\n"
        }
        table += "| **All** | \(total.tp) | \(total.fp) | \(total.fn) | \(pct(total.tp, total.tp + total.fp)) | \(pct(total.tp, total.tp + total.fn)) |\n"
        return table + "\nMistakes:\n" + mistakes.joined(separator: "\n") + "\n"
    }
}
