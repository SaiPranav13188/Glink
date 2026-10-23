import Foundation
import Testing
@testable import GlinkCore

@Suite("Fuzzy matcher")
struct FuzzyMatcherTests {
    func score(_ q: String, _ c: String) -> Double? { FuzzyMatcher.match(q, in: c)?.score }

    @Test func matchesSubsequence() {
        #expect(score("xc", "Xcode") != nil)
        #expect(score("vsc", "Visual Studio Code") != nil)
        #expect(score("zz", "Xcode") == nil)
        #expect(score("edocx", "Xcode") == nil)
    }

    @Test func prefersPrefixOverMidWord() throws {
        let xcode = try #require(score("xc", "Xcode"))
        let excel = try #require(score("xc", "Microsoft Excel"))
        #expect(xcode > excel)
    }

    @Test func prefersWordBoundaries() throws {
        let acronym = try #require(score("vsc", "Visual Studio Code"))
        let scattered = try #require(score("vsc", "Movies Scanner"))
        #expect(acronym > scattered)
    }

    @Test func exactMatchWins() throws {
        let exact = try #require(score("notes", "Notes"))
        let longer = try #require(score("notes", "Notes Helper"))
        #expect(exact > longer)
    }

    @Test func caseAndDiacriticInsensitive() {
        #expect(score("cafe", "Café") != nil)
        #expect(score("SAFARI", "Safari") != nil)
    }

    @Test func returnsMatchedIndices() throws {
        let m = try #require(FuzzyMatcher.match("ss", in: "System Settings"))
        #expect(m.matchedIndices == [0, 7])
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatcher.match("", in: "Anything")?.score == 0)
    }
}

@Suite("Calculator")
struct CalculatorTests {
    let en = Locale(identifier: "en_US")
    func value(_ s: String) -> Double? { Calculator.evaluate(s, locale: en)?.value }

    @Test func arithmetic() {
        #expect(value("2+3*4") == 14)
        #expect(value("(2+3)*4") == 20)
        #expect(value("2^10") == 1024)
        #expect(value("2^3^2") == 512)       // right-associative
        #expect(value("-3 + 5") == 2)
        #expect(value("10 / 4") == 2.5)
        #expect(value("7 mod 3") == 1)
        #expect(value("5!") == 120)
        #expect(value("1,000 * 3") == 3000)
    }

    @Test func implicitMultiplicationAndFunctions() throws {
        #expect(value("2(3+4)") == 14)
        #expect(value("sqrt(16) + 1") == 5)
        #expect(value("max(3, 9, 4) * 2") == 18)
        let twoPi = try #require(value("2pi"))
        #expect(abs(twoPi - 2 * .pi) < 1e-12)
    }

    @Test func percentages() {
        #expect(value("20% of 150") == 30)
        #expect(value("200 + 10%") == 220)
        #expect(value("200 - 25%") == 150)
        #expect(value("50%") == 0.5)
    }

    @Test func ignoresPlainSearchText() {
        #expect(Calculator.evaluate("safari") == nil)
        #expect(Calculator.evaluate("42") == nil)
        #expect(Calculator.evaluate("pi") == nil)
        #expect(Calculator.evaluate("e") == nil)
        #expect(Calculator.evaluate("photos in finder") == nil)
        #expect(Calculator.evaluate("1/0") == nil)
    }

    @Test func formatting() {
        #expect(Calculator.format(1234567.5, locale: en) == "1,234,567.5")
        #expect(Calculator.format(0.1 + 0.2, locale: en) == "0.3")
    }

    /// Typing happens one character at a time; every partial input must return quickly.
    @Test(.timeLimit(.minutes(1))) func everyPrefixEvaluates() {
        for input in ["10 km to mi", "20% of 150", "sqrt(16) + 1", "1,000 * 3", "5kg to lbs", "2^3^2", "12 in to cm"] {
            for end in input.indices {
                _ = Calculator.evaluate(String(input[...end]), locale: en)
            }
        }
    }

    @Test func unitConversions() throws {
        let km = try #require(Calculator.evaluate("10 km to mi", locale: en))
        #expect(abs(km.value - 6.21371192) < 1e-6)
        #expect(km.unit == "mi")

        let temp = try #require(Calculator.evaluate("212f in c", locale: en))
        #expect(abs(temp.value - 100) < 1e-9)

        let data = try #require(Calculator.evaluate("1.5 gb as mb", locale: en))
        #expect(data.value == 1500)

        let inches = try #require(Calculator.evaluate("12 in to cm", locale: en))
        #expect(abs(inches.value - 30.48) < 1e-9)

        let glued = try #require(Calculator.evaluate("5kg to lbs", locale: en))
        #expect(abs(glued.value - 11.0231131) < 1e-6)

        #expect(Calculator.evaluate("10 km to kg") == nil)   // dimension mismatch
    }
}

@Suite("Snippets")
struct SnippetTests {
    let context = SnippetContext(
        date: Date(timeIntervalSince1970: 1_700_000_000), // 2023-11-14 22:13:20 UTC
        clipboard: "pasted",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(identifier: "UTC")!,
        uuid: { "UUID-1" }
    )

    @Test func expandsPlaceholders() {
        let r = SnippetExpander.expand("Today is {date:yyyy-MM-dd} ({weekday}), id {uuid}, clip: {clipboard}", context: context)
        #expect(r.text == "Today is 2023-11-14 (Tuesday), id UUID-1, clip: pasted")
        #expect(r.cursorOffsetFromEnd == nil)
    }

    @Test func cursorPlaceholder() {
        let r = SnippetExpander.expand("<b>{cursor}</b>", context: context)
        #expect(r.text == "<b></b>")
        #expect(r.cursorOffsetFromEnd == 4)
    }

    @Test func unknownPlaceholdersAreKept() {
        #expect(SnippetExpander.expand("{nope} {", context: context).text == "{nope} {")
    }

    @Test func triggerRequiresWordBoundary() {
        #expect(SnippetTrigger.match(typed: "hello ;sig", keywords: [";sig"]) == ";sig")
        #expect(SnippetTrigger.match(typed: "addr", keywords: ["addr"]) == "addr")
        #expect(SnippetTrigger.match(typed: "my addr", keywords: ["addr"]) == "addr")
        #expect(SnippetTrigger.match(typed: "readdr", keywords: ["addr"]) == nil)
        #expect(SnippetTrigger.match(typed: "x;email", keywords: [";e", ";email"]) == ";email")
    }
}

@Suite("Ranking")
struct RankingTests {
    @Test func moreUseRanksHigher() {
        let now = Date()
        #expect(RankingScore.boost(count: 0, lastUsed: now, now: now) == 0)
        #expect(RankingScore.boost(count: 20, lastUsed: now, now: now) > RankingScore.boost(count: 2, lastUsed: now, now: now))
    }

    @Test func recencyDecays() {
        let now = Date()
        let recent = RankingScore.boost(count: 3, lastUsed: now, now: now)
        let old = RankingScore.boost(count: 3, lastUsed: now.addingTimeInterval(-7 * 86400), now: now)
        #expect(recent > old)
        #expect(RankingScore.boost(count: 10_000, lastUsed: now, now: now) <= 0.7)
    }
}

@Suite("MCP Config Check")
struct MCPConfigTests {
    let home = "/Users/test"
    // Built at run time so the repo holds no key-shaped strings (same approach as Tollgate's eval set).
    let fakeGitHub = "ghp_" + String(repeating: "FAKE0", count: 8)

    func results(_ json: String, permissions: Int? = nil) throws -> [MCPServerResult] {
        let servers = try MCPConfigAnalyzer.parseServers(from: Data(json.utf8), path: "/cfg.json")
        return servers.map { MCPConfigAnalyzer.analyze($0, homeDirectory: home, filePermissions: permissions) }
    }

    func rules(_ r: [MCPServerResult]) -> Set<String> { Set(r.flatMap(\.findings).map(\.ruleID)) }

    @Test func parsesClaudeDesktopShape() throws {
        let servers = try MCPConfigAnalyzer.parseServers(from: Data("""
        {"mcpServers": {"fs": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/test/Projects"]}}}
        """.utf8), path: "/cfg.json")
        #expect(servers.map(\.name) == ["fs"])
        #expect(servers[0].args.count == 3)
    }

    @Test func parsesJSONCWithCommentsAndTrailingCommas() throws {
        let servers = try MCPConfigAnalyzer.parseServers(from: Data("""
        {
          // VS Code style
          "servers": { "gh": { "url": "https://api.example.com/mcp", /* inline */ }, },
          "theme": "http://not-a-comment",
        }
        """.utf8), path: "/settings.json")
        #expect(servers.map(\.name) == ["gh"])
    }

    @Test func parsesZedNestedCommand() throws {
        let servers = try MCPConfigAnalyzer.parseServers(from: Data("""
        {"context_servers": {"pg": {"command": {"path": "uvx", "args": ["mcp-postgres"], "env": {}}}}}
        """.utf8), path: "/zed.json")
        #expect(servers.first?.command == "uvx")
        #expect(servers.first?.args == ["mcp-postgres"])
    }

    @Test func tollgateFlagsKnownKeyAndCapsScore() throws {
        let r = try results("""
        {"mcpServers": {"gh": {"command": "npx", "args": ["@modelcontextprotocol/server-github@1.2.0"],
          "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": "\(fakeGitHub)"}}}}
        """, permissions: 0o644)
        let findings = r[0].findings
        #expect(findings.contains { $0.ruleID == "SEC-001" && $0.severity == .critical })
        #expect(r[0].score <= 59)                               // Tollgate's critical cap
        #expect(rules(r).contains("GLK-006"))                   // secret + world-readable file
        #expect(!rules(r).contains("CFG-002"))                  // pinned version
        // No finding may contain the full secret.
        #expect(!findings.contains { $0.detail.contains(fakeGitHub) || ($0.evidence ?? "").contains(fakeGitHub) })
    }

    @Test func referencesAreNotSecrets() throws {
        let r = try results("""
        {"mcpServers": {"gh": {"command": "/usr/local/bin/gh-mcp", "env": {"GITHUB_TOKEN": "${GITHUB_TOKEN}", "API_KEY": "<YOUR_API_KEY>"}}}}
        """)
        #expect(r[0].findings.isEmpty)
        #expect(r[0].score == 100)
    }

    @Test func tollgateFlagsUnpinnedHTTPShellAndWideAccess() throws {
        let r = try results("""
        {"mcpServers": {
          "pkg": {"command": "npx", "args": ["-y", "some-mcp@latest"]},
          "remote": {"url": "http://mcp.example.com/sse"},
          "local": {"url": "http://localhost:3000/mcp"},
          "sh": {"command": "bash", "args": ["-c", "node server.js"]},
          "fs": {"command": "npx", "args": ["@modelcontextprotocol/server-filesystem@1.0.0", "~"]}
        }}
        """)
        func ids(_ name: String) -> Set<String> { Set(r.first { $0.raw.name == name }!.findings.map(\.ruleID)) }
        #expect(ids("pkg").contains("CFG-002"))
        #expect(ids("remote").contains("CFG-003"))
        #expect(ids("local").isEmpty)
        #expect(ids("sh").contains("CFG-004"))
        #expect(ids("fs").contains("CFG-005"))
    }

    @Test func glinkRulesCoverWhatTollgateDoesNot() throws {
        let r = try results("""
        {"mcpServers": {
          "root": {"command": "sudo", "args": ["/opt/bin/server"]},
          "dock": {"command": "docker", "args": ["run", "--privileged", "-v", "/var/run/docker.sock:/var/run/docker.sock", "img"]},
          "auto": {"command": "/bin/tool", "autoApprove": ["*"]},
          "gem": {"command": "/bin/tool2", "trust": true},
          "tmp": {"command": "/tmp/server"}
        }}
        """)
        #expect(rules(r).isSuperset(of: ["GLK-001", "GLK-002", "GLK-003", "GLK-004", "GLK-005"]))
        #expect(r.first { $0.raw.name == "auto" }!.findings.contains { $0.ruleID == "GLK-003" && $0.severity == .high })
    }

    @Test func reportHeadlineIsWeakestServer() throws {
        let r = try results("""
        {"mcpServers": {"good": {"command": "/bin/ok"}, "bad": {"command": "sudo", "args": ["x"]}}}
        """)
        let report = MCPReport(files: [], results: r)
        #expect(report.results.first?.raw.name == "bad")       // worst first
        #expect(report.score == report.results.map(\.score).min())
        #expect(report.grade == "At risk")
        #expect(MCPConfigAnalyzer.markdown(for: report).contains("GLK-001"))
        #expect(MCPReport(files: [], results: []).score == 100)
    }
}
