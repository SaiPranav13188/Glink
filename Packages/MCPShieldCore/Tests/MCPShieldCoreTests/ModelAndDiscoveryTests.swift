import Foundation
import Testing
@testable import MCPShieldCore

@Suite struct JSONValueTests {
    @Test func decodesMixedJSON() throws {
        let json = #"{"a": "x", "b": 2, "c": true, "d": [1, "y"], "e": null, "f": {"g": "h"}}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(v.object?["a"]?.string == "x")
        #expect(v.object?["b"] == .number(2))
        #expect(v.object?["c"] == .bool(true))
        #expect(v.object?["d"]?.array?.count == 2)
        #expect(v.object?["e"] == .null)
        #expect(v.object?["f"]?.object?["g"]?.string == "h")
    }

    @Test func roundTrips() throws {
        let v = JSONValue.object(["k": .array([.string("s"), .number(1.5), .bool(false), .null])])
        let back = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(v))
        #expect(back == v)
    }

    @Test func severityRankAndPenalty() {
        #expect(Severity.critical.rank == 0)
        #expect(Severity.info.rank == 4)
        #expect(Severity.critical.penalty == 25)
    }
}

@Suite struct ConfigDiscoveryTests {
    let sample = #"""
    {
      "mcpServers": {
        "filesystem": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"] },
        "remote": { "url": "https://example.com/mcp", "headers": { "Authorization": "Bearer x" } },
        "numbers": { "command": "node", "args": ["s.js"], "env": { "PORT": 8080, "DEBUG": true } }
      }
    }
    """#

    @Test func parsesServersSortedByName() {
        let servers = ConfigDiscovery.parse(data: Data(sample.utf8), label: "Claude Desktop", path: "/x.json")
        #expect(servers.map(\.name) == ["filesystem", "numbers", "remote"])
        #expect(servers[0].command == "npx")
        #expect(servers[0].args.last == "/tmp")
        #expect(servers[1].env == ["PORT": "8080", "DEBUG": "true"])
        #expect(servers[2].url == "https://example.com/mcp")
        #expect(servers[2].headers["Authorization"] == "Bearer x")
        #expect(servers.allSatisfy { $0.source == "Claude Desktop" })
    }

    @Test func readsVSCodeServersKey() {
        let json = #"{"servers": {"a": {"command": "uvx", "args": ["x==1.0"]}}}"#
        #expect(ConfigDiscovery.parse(data: Data(json.utf8), label: "VS Code", path: "/x").count == 1)
    }

    @Test func missingAndBrokenFilesAreSkippedWithANote() throws {
        let dir = try tempDir()
        let missing = ConfigDiscovery.loadWithStatus(label: "M", url: dir.appending(path: "nope.json"))
        #expect(missing.servers.isEmpty && missing.status.state == .missing)

        let broken = dir.appending(path: "broken.json")
        try Data("{ not json".utf8).write(to: broken)
        let b = ConfigDiscovery.loadWithStatus(label: "B", url: broken)
        #expect(b.servers.isEmpty && b.status.state == .invalidJSON)

        let empty = dir.appending(path: "empty.json")
        try Data(#"{"other": 1}"#.utf8).write(to: empty)
        #expect(ConfigDiscovery.loadWithStatus(label: "E", url: empty).status.state == .noServers)
    }

    @Test func addedFolderFindsMcpJson() throws {
        let dir = try tempDir()
        try Data(sample.utf8).write(to: dir.appending(path: ".mcp.json"))
        let d = ConfigDiscovery.discover(extra: [dir])
        #expect(d.servers.filter { $0.sourcePath.hasPrefix(dir.path) }.count == 3)
    }

    @Test func discoveryNeverWritesTheFile() throws {
        let dir = try tempDir()
        let file = dir.appending(path: "mcp.json")
        try Data(sample.utf8).write(to: file)
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        _ = ConfigDiscovery.discover(extra: [file])
        let after = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        #expect(before == after)
        #expect(try Data(contentsOf: file) == Data(sample.utf8))
    }
}
