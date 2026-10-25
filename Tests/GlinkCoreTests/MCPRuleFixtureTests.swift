import Foundation
import MCPShieldCore
import Testing
@testable import GlinkCore

/// One test per rule, each driven by a sample config in Fixtures/mcp.
@Suite("MCP rules (fixtures)")
struct MCPRuleFixtureTests {
    /// Built at run time so the repo holds no key-shaped strings.
    static let fakeGitHub = "ghp_" + String(repeating: "FAKE0", count: 8)

    func scan(_ fixture: String, permissions: Int? = nil) throws -> [MCPServerResult] {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures/mcp"))
        let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "{{FAKE_GITHUB}}", with: Self.fakeGitHub)
        return try MCPConfigAnalyzer.parseServers(from: Data(text.utf8), path: url.path, source: "Fixture")
            .map { MCPConfigAnalyzer.analyze($0, homeDirectory: "/Users/test", filePermissions: permissions) }
    }

    func server(_ results: [MCPServerResult], _ name: String) throws -> MCPServerResult {
        try #require(results.first { $0.raw.name == name })
    }

    func rules(_ r: MCPServerResult) -> Set<String> { Set(r.findings.map(\.ruleID)) }

    @Test("SEC-001 known key format → critical, F, masked to 4 characters")
    func knownKeyFormat() throws {
        let gh = try server(scan("plaintext-secret"), "github")
        #expect(gh.findings.contains { $0.ruleID == "SEC-001" && $0.severity == .critical })
        #expect(gh.letter == "F")
        let shown = gh.findings.map { $0.detail + ($0.evidence ?? "") }.joined() + gh.displayCommand
        #expect(!shown.contains(Self.fakeGitHub))
        #expect(!shown.contains(String(Self.fakeGitHub.prefix(6))))   // only the first 4 characters ever appear
    }

    @Test("CFG-001 literal secret in env → high") func literalSecret() throws {
        let s = try server(scan("literal-api-key"), "search")
        #expect(s.findings.contains { $0.ruleID == "CFG-001" && $0.severity == .high })
    }

    @Test("CFG-002 unpinned npx/uvx package → medium") func unpinned() throws {
        let r = try scan("unpinned")
        for name in ["fetcher", "latest"] {
            #expect(try server(r, name).findings.contains { $0.ruleID == "CFG-002" && $0.severity == .medium })
        }
    }

    @Test("CFG-003 plain http (not localhost) → high") func plainHTTP() throws {
        let r = try scan("plain-http")
        #expect(try rules(server(r, "remote")).contains("CFG-003"))
        #expect(try server(r, "local").findings.isEmpty)
    }

    @Test("CFG-004 shell launch → flagged") func shell() throws {
        #expect(try rules(server(scan("shell"), "wrapped")).contains("CFG-004"))
    }

    @Test("CFG-005 broad filesystem access → high") func broadFilesystem() throws {
        let r = try scan("broad-filesystem")
        for name in ["fs-root", "fs-home"] {
            #expect(try server(r, name).findings.contains { $0.ruleID == "CFG-005" && $0.severity == .high })
        }
    }

    @Test("CFG-006 executable others can modify") func writableExecutable() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appending(path: "server")
        try Data("#!/bin/sh\n".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: exe.path)
        var s = MCPServerConfig(name: "ww", source: "Fixture", configPath: "/cfg.json")
        s.command = exe.path
        #expect(rules(MCPConfigAnalyzer.analyze(s)).contains("CFG-006"))
    }

    @Test("GLK-001…005 sudo, docker, auto-approve, trust, temp binary") func glinkRules() throws {
        let r = try scan("glink-rules")
        #expect(try rules(server(r, "root")).contains("GLK-001"))
        #expect(try server(r, "dock").findings.filter { $0.ruleID == "GLK-002" }.count == 2)   // privileged + socket
        #expect(try server(r, "auto").findings.contains { $0.ruleID == "GLK-003" && $0.severity == .high })
        #expect(try rules(server(r, "trusted")).contains("GLK-004"))
        #expect(try rules(server(r, "tmp")).contains("GLK-005"))
    }

    @Test("GLK-006 secret in a world-readable config") func worldReadable() throws {
        #expect(try rules(server(scan("plaintext-secret", permissions: 0o644), "github")).contains("GLK-006"))
        #expect(try !rules(server(scan("plaintext-secret", permissions: 0o600), "github")).contains("GLK-006"))
    }

    @Test("GLK-007 unknown or unverified publisher → low") func unknownPublisher() throws {
        let r = try scan("unknown-publisher")
        #expect(try server(r, "weather").findings.contains { $0.ruleID == "GLK-007" && $0.severity == .low })
        #expect(try !rules(server(r, "official")).contains("GLK-007"))
    }

    @Test("A clean config scores 100, grade A") func clean() throws {
        let r = try scan("clean")
        for s in r {
            #expect(s.findings.isEmpty, "\(s.raw.name): \(s.findings.map(\.ruleID))")
            #expect(s.score == 100 && s.letter == "A")
        }
    }

    @Test func letterGrades() {
        #expect([100, 90, 89, 80, 79, 70, 69, 60, 59, 0].map(MCPGrade.letter) == ["A", "A", "B", "B", "C", "C", "D", "D", "F", "F"])
    }

    @Test func maskShowsFirstFourOnly() {
        #expect(SecretMask.mask("sk-ant-api03-abcdef") == "sk-a••••")
        #expect(SecretMask.mask("abc") == "••••")
    }
}
