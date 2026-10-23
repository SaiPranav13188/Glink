import Foundation
import Testing
@testable import MCPShieldCore

/// One config that must fire each rule, and one that must not.
@Suite struct ConfigRulesTests {
    // CFG-001
    @Test func cfg001FiresOnPlainTextToken() {
        let f = ConfigRules.analyze(server("github", command: "docker", env: ["GITHUB_TOKEN": Fake.plainToken]))
        #expect(f.contains { $0.ruleID == "CFG-001" && $0.target == "github.env.GITHUB_TOKEN" })
    }
    @Test func cfg001SkipsPlaceholder() {
        #expect(!ruleIDs(server(command: "docker", env: ["GITHUB_TOKEN": "${GITHUB_TOKEN}"])).contains("CFG-001"))
    }

    @Test func cfg001FindsSecretsOutsideEnv() {
        let cases: [(ServerConfig, String)] = [
            (server("r", url: "https://x.example.com/mcp", headers: ["Authorization": "Bearer \(Fake.plainToken)"]), "r.headers.Authorization"),
            (server("r", url: "https://x.example.com/mcp", headers: ["X-API-Key": Fake.plainToken]), "r.headers.X-API-Key"),
            (server("r", url: "https://x.example.com/sse?api_key=\(Fake.plainToken)"), "r.url"),
            (server("c", command: "node", args: ["s.js", "--api-key", Fake.plainToken]), "c.args[2]"),
            (server("c", command: "node", args: ["s.js", "--token=\(Fake.plainToken)"]), "c.args[1]"),
            (server("d", command: "docker", args: ["run", "-e", "GITHUB_TOKEN=\(Fake.plainToken)", "img"]), "d.args[2]"),
            (server("p", command: "npx", env: ["DATABASE_URL": "postgresql://postgres:Sup3rS3cret@db.example.com/app"]), "p.env.DATABASE_URL"),
        ]
        for (s, target) in cases {
            #expect(ConfigRules.analyze(s).contains { $0.ruleID == "CFG-001" && $0.target == target }, "\(target)")
        }
    }
    @Test func cfg001SkipsNamesAndValuesThatAreNotSecrets() {
        let clean: [ServerConfig] = [
            server(command: "node", env: ["SSH_KEY_PATH": "/Users/dev/.ssh/id_ed25519", "PRIMARY_KEY_FIELD": "customer_identifier",
                                          "MAX_TOKENS": "4096", "AWS_ACCESS_KEY_ID_NAME": "production-default"]),
            server(command: "uvx", args: ["llm@1.0.0", "--api-key-env", "OPENAI_API_KEY", "--max-tokens", "4096", "--key-file", "/a/b.json"]),
            server(url: "https://x.example.com/mcp", headers: ["Authorization": "Bearer ${GITHUB_TOKEN}"]),
            server(command: "npx", env: ["SLACK_BOT_TOKEN": "xoxb-your-bot-token", "OPENAI_API_KEY": "sk-xxxxxxxxxxxxxxxxxxxx",
                                         "BRAVE_API_KEY": "YOUR_API_KEY_HERE", "GITHUB_TOKEN": "<YOUR_TOKEN>"]),
            server(command: "npx", args: ["pg@1.0.0", "postgresql://localhost:5432/dev", "postgres://u:<your-password>@h/db"]),
        ]
        for s in clean { #expect(!ruleIDs(s).contains("CFG-001"), "\(s)") }
    }

    // CFG-002
    @Test func cfg002FiresOnUnpinnedNpx() {
        #expect(ruleIDs(server(command: "npx", args: ["-y", "@modelcontextprotocol/server-memory"])).contains("CFG-002"))
        #expect(ruleIDs(server(command: "npx", args: ["-y", "some-server@latest"])).contains("CFG-002"))
    }
    @Test func cfg002SkipsPinnedNpx() {
        #expect(!ruleIDs(server(command: "npx", args: ["-y", "@modelcontextprotocol/server-memory@2025.4.25"])).contains("CFG-002"))
    }
    @Test func cfg002UnderstandsEachLauncher() {
        let pinned: [[String]] = [
            ["uvx", "mcp-server-git==0.6.2"], ["uvx", "--from", "mcp-server-git==0.6.2", "mcp-server-git"],
            ["uvx", "ruff-mcp@0.6.0"], ["pipx", "run", "some-mcp==1.0.0"],
            ["npx", "-y", "--package=@scope/tool@2.0.0", "tool-bin"], ["pnpm", "dlx", "srv@1.0.0"],
        ]
        let unpinned: [[String]] = [
            ["npx", "-y", "pkg@^1.2.0"], ["npx", "-y", "pkg@~1.4.0"], ["npx", "-y", "pkg@1.2"],
            ["bunx", "some-mcp"], ["pipx", "run", "mcp-server-x"], ["uvx", "pkg@latest"],
            ["bash", "-c", "npx -y risky-mcp"],
        ]
        for t in pinned { #expect(!ruleIDs(server(command: t[0], args: Array(t.dropFirst()))).contains("CFG-002"), "\(t)") }
        for t in unpinned { #expect(ruleIDs(server(command: t[0], args: Array(t.dropFirst()))).contains("CFG-002"), "\(t)") }
        #expect(!ruleIDs(server(command: "docker", args: ["run", "-i", "mcp/fetch"])).contains("CFG-002"))
    }

    // CFG-003
    @Test func cfg003FiresOnRemoteHTTP() {
        #expect(ruleIDs(server(url: "http://mcp.example.com/sse")).contains("CFG-003"))
    }
    @Test func cfg003SkipsHTTPSAndLocalhost() {
        #expect(!ruleIDs(server(url: "https://mcp.example.com/sse")).contains("CFG-003"))
        #expect(!ruleIDs(server(url: "http://localhost:3000/mcp")).contains("CFG-003"))
        #expect(!ruleIDs(server(url: "http://127.0.0.1:3000/mcp")).contains("CFG-003"))
    }

    @Test func cfg003ChecksURLsGivenToProxies() {
        #expect(ruleIDs(server(command: "npx", args: ["-y", "mcp-remote@0.1.18", "http://legacy.example.com/sse"])).contains("CFG-003"))
        #expect(ruleIDs(server(command: "npx", args: ["-y", "supergateway@2.1.0", "--sse=http://10.0.0.5/sse"])).contains("CFG-003"))
        #expect(!ruleIDs(server(command: "npx", args: ["-y", "mcp-remote@0.1.18", "http://127.0.0.1:8787/sse"])).contains("CFG-003"))
        #expect(!ruleIDs(server(command: "node", args: ["s.js", "--docs", "http://example.com"])).contains("CFG-003"))
    }

    // CFG-004
    @Test func cfg004FiresOnShellDashC() {
        #expect(ruleIDs(server(command: "bash", args: ["-c", "cd ~/srv && node index.js"])).contains("CFG-004"))
        #expect(ruleIDs(server(command: "/bin/zsh", args: ["-lc", "server"])).contains("CFG-004"))
    }
    @Test func cfg004SkipsDirectLaunch() {
        #expect(!ruleIDs(server(command: "node", args: ["index.js", "-c", "conf.json"])).contains("CFG-004"))
        #expect(!ruleIDs(server(command: "bash", args: ["run.sh"])).contains("CFG-004"))
    }

    // CFG-005
    @Test func cfg005FiresOnHomeFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ruleIDs(server("filesystem", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem@1.0.0", home])).contains("CFG-005"))
        #expect(ruleIDs(server("files", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem@1.0.0", "/"])).contains("CFG-005"))
    }
    @Test func cfg005SkipsProjectFolderAndNonFilesystemServers() {
        #expect(!ruleIDs(server("filesystem", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem@1.0.0", "/Users/me/projects/app"])).contains("CFG-005"))
        #expect(!ruleIDs(server("git", command: "uvx", args: ["mcp-server-git==0.6.2", "--repository", "~"])).contains("CFG-005"))
    }

    @Test func cfg005ChecksDockerMounts() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ruleIDs(server("db", command: "docker", args: ["run", "-v", "/:/host:ro", "img"])).contains("CFG-005"))
        #expect(ruleIDs(server("db", command: "docker", args: ["run", "--volume=\(home):/data", "img"])).contains("CFG-005"))
        #expect(ruleIDs(server("db", command: "docker", args: ["run", "--mount", "type=bind,src=\(home),dst=/p", "img"])).contains("CFG-005"))
        #expect(!ruleIDs(server("db", command: "docker", args: ["run", "-v", "\(home)/code/app:/data", "img"])).contains("CFG-005"))
    }

    // CFG-006
    @Test func cfg006FiresOnWorldWritableExecutable() throws {
        let dir = try tempDir()
        let exe = dir.appending(path: "server")
        try Data("#!/bin/sh\n".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: exe.path)
        #expect(ruleIDs(server(command: exe.path)).contains("CFG-006"))

        let script = dir.appending(path: "index.js")
        try Data("//".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: script.path)
        #expect(ruleIDs(server(command: "node", args: [script.path])).contains("CFG-006"))
    }
    @Test func cfg006SkipsOwnerOnlyPaths() throws {
        let dir = try tempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        let exe = dir.appending(path: "server")
        try Data("#!/bin/sh\n".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        #expect(!ruleIDs(server(command: exe.path)).contains("CFG-006"))
        #expect(!ruleIDs(server(command: "/usr/bin/python3", args: ["-m", "srv"])).contains("CFG-006"))
    }

    @Test func cleanServerHasNoFindings() {
        let s = server("memory", command: "npx", args: ["-y", "@modelcontextprotocol/server-memory@2025.4.25"],
                       env: ["MEMORY_FILE_PATH": "/Users/me/memory.json"])
        #expect(Scanner.scan(s).findings.isEmpty)
        #expect(Scanner.scan(s).score == 100)
    }
}
