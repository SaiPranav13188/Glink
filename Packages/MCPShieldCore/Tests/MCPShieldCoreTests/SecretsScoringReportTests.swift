import Foundation
import Testing
@testable import MCPShieldCore

@Suite struct SecretsTests {
    @Test func redactKeepsOnlyEnds() {
        #expect(Secrets.redact(Fake.github) == "ghp_FA...E0")
        #expect(Secrets.redact("short") == "...")
    }

    @Test(arguments: [
        (Fake.github, "GitHub token"), (Fake.aws, "AWS access key"), (Fake.google, "Google API key"),
        (Fake.anthropic, "Anthropic key"), (Fake.openAI, "OpenAI key"),
        (Fake.githubPAT, "GitHub fine-grained token"), (Fake.slack, "Slack token"),
        ("-----BEGIN RSA PRIVATE KEY-----\nabc", "Private key block"),
    ])
    func detectsEachPattern(secret: String, name: String) {
        let f = Secrets.scan("prefix \(secret) suffix", target: "t")
        #expect(f.count == 1)
        #expect(f.first?.title == "\(name) found")
        #expect(f.first?.severity == .critical)
    }

    @Test func anthropicKeyIsNotAlsoReportedAsOpenAI() {
        #expect(Secrets.scan(Fake.anthropic, target: "t").map(\.title) == ["Anthropic key found"])
    }

    @Test func placeholdersAreNotSecrets() {
        for p in ["sk-xxxxxxxxxxxxxxxxxxxxxxxx", "xoxb-your-bot-token", "<YOUR_TOKEN>", "YOUR_API_KEY_HERE"] {
            #expect(Secrets.isPlaceholder(p), "\(p)")
            #expect(Secrets.scan(p, target: "t").isEmpty, "\(p)")
        }
        for real in [Fake.github, Fake.openAI, Fake.slack, Fake.plainToken] { #expect(!Secrets.isPlaceholder(real)) }
    }

    @Test func ordinaryTextIsClean() {
        #expect(Secrets.scan("npx -y @modelcontextprotocol/server-filesystem /Users/me/Desktop", target: "t").isEmpty)
    }

    @Test func fullSecretNeverAppearsInAFinding() throws {
        let s = server("gh", command: "npx", args: ["--token", Fake.anthropic],
                       env: ["GITHUB_TOKEN": Fake.github, "API_KEY": Fake.plainToken])
        let findings = Scanner.scan(s).findings
        #expect(!findings.isEmpty)
        let encoded = String(decoding: try JSONEncoder().encode(findings), as: UTF8.self)
        for secret in [Fake.github, Fake.anthropic, Fake.plainToken] { #expect(!encoded.contains(secret)) }
    }
}

@Suite struct ScoringTests {
    func finding(_ sev: Severity, _ cat: MCPShieldCore.Category = .config) -> Finding {
        Finding(ruleID: "X", title: "x", severity: sev, category: cat, target: "t")
    }

    @Test func noFindingsScores100() {
        #expect(Scoring.score([]).total == 100)
    }

    @Test func criticalCapsAt59() {
        let (total, per) = Scoring.score([finding(.critical, .secrets)])
        #expect(per["secrets"] == 75)
        #expect(total == 59)   // would be 91 without the cap
    }

    @Test func highCapsAt84() {
        let (total, per) = Scoring.score([finding(.high)])
        #expect(per["config"] == 88)
        #expect(total == 84)   // would be 96 ("Good") without the cap
        #expect(Scoring.grade(total) == "Needs work")
    }

    @Test func weightsAndFloor() {
        // config 100-5-5-1 = 89 -> 0.30*89 + 35 + 25 + 10 = 96.7 -> 97
        #expect(Scoring.score([finding(.medium), finding(.medium), finding(.low)]).total == 97)
        let many = Array(repeating: finding(.high), count: 20)
        #expect(Scoring.score(many).perCategory["config"] == 0)
    }

    @Test func grades() {
        #expect(Scoring.grade(85) == "Good")
        #expect(Scoring.grade(60) == "Needs work")
        #expect(Scoring.grade(59) == "At risk")
    }
}

@Suite struct ReportTests {
    let secrets = [Fake.github, Fake.aws, Fake.google, Fake.anthropic, Fake.openAI, Fake.plainToken, "hunter2hunter2",
                   Fake.slack, "D0ckerPlainS3cret", "C0nnPassw0rd"]

    var leakyServers: [ServerConfig] {
        [
            server("everything", command: "bash",
                   args: ["-c", "OPENAI_KEY=\(Fake.openAI) node s.js", "--api-key", Fake.plainToken, "--token=\(Fake.anthropic)"],
                   env: ["GITHUB_TOKEN": Fake.github, "AWS_ACCESS_KEY_ID": Fake.aws, "DB_PASSWORD": "hunter2hunter2"]),
            server("docker", command: "docker",
                   args: ["run", "-e", "API_TOKEN=D0ckerPlainS3cret", "-e", "SLACK_BOT_TOKEN=\(Fake.slack)", "img",
                          "postgresql://app:C0nnPassw0rd@db.example.com/prod"]),
            server("remote", url: "https://user:hunter2hunter2@mcp.example.com/sse?key=\(Fake.google)",
                   headers: ["Authorization": "Bearer \(Fake.github)"]),
        ]
    }

    @Test func exportNeverContainsAFullSecret() throws {
        let text = String(decoding: try Report.json(for: Scanner.scan(leakyServers)), as: UTF8.self)
        for s in secrets { #expect(!text.contains(s), "leaked \(Secrets.redact(s))") }
        #expect(text.contains("\"GITHUB_TOKEN\""))   // keys are kept
        #expect(text.contains("\"score\""))
    }

    @Test func displayedCommandLineIsRedacted() {
        for s in leakyServers {
            let line = s.redactedCommandLine
            for secret in secrets { #expect(!line.contains(secret)) }
        }
    }

    @Test func exportIsValidJSONWithSummary() throws {
        let data = try Report.json(for: Scanner.scan(leakyServers))
        let doc = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(doc.object?["tool"]?.string == "Tollgate")
        #expect(doc.object?["summary"]?.object?["servers"] == .number(3))
        #expect(doc.object?["results"]?.array?.count == 3)
    }
}

@Suite struct ToolRulesTests {
    @Test func plansFourCases() {
        #expect(ToolRules.isWriteTool("delete_order"))
        #expect(!ToolRules.isWriteTool("read_file"))
        #expect(!ToolRules.touchesPII("occupied_slots"))
        #expect(ToolRules.touchesPII("get_customer_pan"))
    }

    @Test func wordSplitting() {
        #expect(ToolRules.words("delete_order") == ["delete", "order"])
        #expect(ToolRules.words("deleteOrder") == ["delete", "order"])
        #expect(ToolRules.words("send-Email v2") == ["send", "email", "v2"])
    }

    @Test func vagueVerbsAndReadPrefixes() {
        #expect(!ToolRules.isWriteTool("add_numbers"))        // "add" is not in the write list
        #expect(!ToolRules.isWriteTool("run_query"))
        #expect(!ToolRules.isWriteTool("get_update_status"))  // starts with a read verb
        #expect(ToolRules.isWriteTool("bulkDeleteUsers"))
    }
}
