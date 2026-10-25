import Foundation
import MCPShieldCore

/// MCP Config Check: Glink's discovery layer on top of Tollgate's rules engine (MCPShieldCore).
///
/// - Tollgate supplies the measured rules (CFG-001…006, SEC-001), per-server scoring with
///   critical/high caps, and secret redaction.
/// - Glink adds discovery for more clients (VS Code, Windsurf, Zed, Gemini CLI, Continue),
///   JSONC parsing, and a few rules Tollgate doesn't cover (GLK-001…006).

/// A raw server entry as found in a config file, before conversion to Tollgate's `ServerConfig`.
public struct MCPServerConfig: Sendable, Hashable {
    public var name: String
    public var source: String
    public var configPath: String
    public var command: String?
    public var args: [String] = []
    public var env: [String: String] = [:]
    public var url: String?
    public var headers: [String: String] = [:]
    public var autoApprove: [String] = []
    public var trust = false
    public var disabled = false

    public init(name: String, source: String, configPath: String) {
        self.name = name
        self.source = source
        self.configPath = configPath
    }

    var shieldConfig: ServerConfig {
        ServerConfig(name: name, source: source, sourcePath: configPath, command: command, args: args,
                     env: env, url: url, headers: headers)
    }
}

/// One config file that was looked at, with a note for the UI.
public struct MCPConfigFile: Sendable, Hashable, Identifiable {
    public enum State: Sendable, Hashable { case loaded(Int), invalidJSON(String), noServers }
    public var id: String { path }
    public let label: String
    public let path: String
    public let state: State
}

/// The scored result for one server.
public struct MCPServerResult: Sendable, Identifiable {
    public var id: String { "\(raw.source)::\(raw.configPath)::\(raw.name)" }
    public let raw: MCPServerConfig
    public let findings: [Finding]
    public let score: Int
    /// Tollgate's label: Good, Needs work, At risk.
    public var grade: String { Scoring.grade(score) }
    /// School-style letter for badges: A–F.
    public var letter: String { MCPGrade.letter(for: score) }
    /// Command line with secrets masked to their first 4 characters, safe to display.
    public var displayCommand: String {
        let r = Report.RedactedServer(raw.shieldConfig)
        let text = r.url ?? ([r.command ?? ""] + r.args).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return SecretMask.apply(text, sensitive: Report.sensitiveValues(in: [raw.shieldConfig]))
    }
    var scanResult: ScanResult { ScanResult(server: raw.shieldConfig, findings: findings, score: score, categoryScores: [:]) }
}

public struct MCPReport: Sendable {
    public let files: [MCPConfigFile]
    public let results: [MCPServerResult]

    public init(files: [MCPConfigFile], results: [MCPServerResult]) {
        self.files = files
        // Worst servers first.
        self.results = results.sorted { ($0.score, $0.raw.name) < ($1.score, $1.raw.name) }
    }

    public var findings: [Finding] { results.flatMap(\.findings) }
    /// The headline score: the weakest server, since one risky server is the risk.
    public var score: Int { results.map(\.score).min() ?? 100 }
    public var grade: String { Scoring.grade(score) }
    public var letter: String { MCPGrade.letter(for: score) }
    public func count(_ severity: Severity) -> Int { findings.filter { $0.severity == severity }.count }
}

/// Letter grades on top of Tollgate's 0–100 score. Tollgate caps any critical finding at 59 (F)
/// and any high finding at 84 (B at best), so one serious problem is never averaged away.
public enum MCPGrade {
    public static func letter(for score: Int) -> String {
        switch score {
        case 90...: "A"
        case 80..<90: "B"
        case 70..<80: "C"
        case 60..<70: "D"
        default: "F"
        }
    }
}

/// Never show a full secret: Glink shows only its first 4 characters.
public enum SecretMask {
    public static func mask(_ secret: String) -> String {
        secret.count <= 4 ? "••••" : String(secret.prefix(4)) + "••••"
    }

    /// Replaces every sensitive value, and Tollgate's `abcdef...yz` redactions of them, with the 4-character mask.
    public static func apply(_ text: String, sensitive: Set<String>) -> String {
        var out = text
        for value in sensitive.sorted(by: { $0.count > $1.count }) where value.count >= 4 {
            out = out.replacingOccurrences(of: value, with: mask(value))
            out = out.replacingOccurrences(of: Secrets.redact(value), with: mask(value))
        }
        // Known key formats that weren't in a recognized field.
        for (_, value) in Secrets.matches(in: out) { out = out.replacingOccurrences(of: value, with: mask(value)) }
        return out
    }
}

public enum MCPConfigAnalyzer {
    /// Locations checked, relative to the home folder. Claude Code projects are added dynamically.
    public static let knownLocations: [(label: String, path: String)] = [
        ("Claude Desktop", "Library/Application Support/Claude/claude_desktop_config.json"),
        ("Claude Code", ".claude.json"),
        ("Cursor", ".cursor/mcp.json"),
        ("Windsurf", ".codeium/windsurf/mcp_config.json"),
        ("VS Code", "Library/Application Support/Code/User/mcp.json"),
        ("VS Code", "Library/Application Support/Code/User/settings.json"),
        ("Cursor", "Library/Application Support/Cursor/User/settings.json"),
        ("Zed", ".config/zed/settings.json"),
        ("Gemini CLI", ".gemini/settings.json"),
        ("Continue", ".continue/config.json"),
        ("Home", ".mcp.json"),
    ]

    /// Config file names looked for inside an added folder (same set as Tollgate's "Add Config…").
    public static let projectConfigNames = [".mcp.json", "mcp.json", ".cursor/mcp.json", ".vscode/mcp.json", "claude_desktop_config.json"]

    public static let glinkRuleIDs = ["GLK-001", "GLK-002", "GLK-003", "GLK-004", "GLK-005", "GLK-006", "GLK-007"]

    /// Publishers whose MCP packages are well known. Anything else gets a low-severity heads-up.
    public static let knownPublishers: [String] = [
        "@modelcontextprotocol/", "@anthropic-ai/", "@github/", "@cloudflare/", "@playwright/", "@upstash/",
        "@supabase/", "@stripe/", "@notionhq/", "@sentry/", "@vercel/", "@microsoft/", "@azure/", "@google-cloud/",
        "@browserbasehq/", "@heroku/", "@shopify/", "@atlassian/", "@linear/", "@figma/",
        // Official Python reference servers (uvx / pipx)
        "mcp-server-fetch", "mcp-server-git", "mcp-server-time", "mcp-server-sqlite", "mcp-server-sentry",
        // Docker images
        "mcp/", "ghcr.io/github/", "docker.io/mcp/",
    ]

    /// The package a launcher (npx, uvx, docker…) runs, if any.
    static func launchedPackage(_ server: MCPServerConfig) -> String? {
        let name = ((server.command ?? "") as NSString).lastPathComponent.lowercased()
        let runners: Set<String> = ["npx", "bunx", "pnpx", "uvx", "pipx", "docker", "podman"]
        guard runners.contains(name) || ((name == "pnpm" || name == "yarn") && server.args.first == "dlx") else { return nil }
        let skip: Set<String> = ["-y", "--yes", "dlx", "run", "-i", "--rm", "-q", "--from"]
        return server.args.first { !skip.contains($0) && !$0.hasPrefix("-") && !$0.contains("=") }
    }

    // MARK: Scanning

    /// Read-only: finds configs, parses them, and scores every server.
    public static func scan(homeDirectory: String = NSHomeDirectory(), extraPaths: [(String, String)] = [],
                            fileManager: FileManager = .default) -> MCPReport {
        var files: [MCPConfigFile] = []
        var results: [MCPServerResult] = []
        var seen = Set<String>()

        func load(_ label: String, _ path: String) {
            let standardized = (path as NSString).standardizingPath
            guard seen.insert(standardized).inserted, fileManager.fileExists(atPath: path),
                  let data = fileManager.contents(atPath: path) else { return }
            do {
                let servers = try parseServers(from: data, path: path, source: label)
                files.append(MCPConfigFile(label: label, path: path, state: servers.isEmpty ? .noServers : .loaded(servers.count)))
                let perms = (try? fileManager.attributesOfItem(atPath: path)[.posixPermissions] as? Int) ?? nil
                results += servers.map { analyze($0, homeDirectory: homeDirectory, filePermissions: perms) }
            } catch {
                files.append(MCPConfigFile(label: label, path: path, state: .invalidJSON(error.localizedDescription)))
            }
        }

        for (label, rel) in knownLocations { load(label, (homeDirectory as NSString).appendingPathComponent(rel)) }

        // Claude Code also reads each known project's .mcp.json.
        let claudeJSON = (homeDirectory as NSString).appendingPathComponent(".claude.json")
        if let data = fileManager.contents(atPath: claudeJSON),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let projects = root["projects"] as? [String: Any] {
            for project in projects.keys.sorted() {
                load("Project \((project as NSString).lastPathComponent)", (project as NSString).appendingPathComponent(".mcp.json"))
            }
        }
        // Files or folders the user added. A folder is checked for the usual config names,
        // itself and one level down (so a folder of projects works).
        for (label, path) in extraPaths {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            guard isDir.boolValue else { load(label, path); continue }
            let subfolders = ((try? fileManager.contentsOfDirectory(atPath: path)) ?? []).sorted()
                .map { (path as NSString).appendingPathComponent($0) }
            for folder in [path] + subfolders {
                for name in projectConfigNames {
                    load("Added (\((folder as NSString).lastPathComponent))", (folder as NSString).appendingPathComponent(name))
                }
            }
        }
        return MCPReport(files: files, results: results)
    }

    /// Tollgate's rules plus Glink's, re-scored together with Tollgate's scoring.
    public static func analyze(_ server: MCPServerConfig, homeDirectory: String = NSHomeDirectory(),
                               filePermissions: Int? = nil) -> MCPServerResult {
        let shield = Scanner.scan(server.shieldConfig)
        let extra = glinkFindings(for: server, homeDirectory: homeDirectory, filePermissions: filePermissions,
                                  hasSecret: shield.findings.contains { $0.category == .secrets || $0.ruleID == "CFG-001" })
        let sensitive = Report.sensitiveValues(in: [server.shieldConfig])
        let findings = (shield.findings + extra)
            .map { f -> Finding in
                var f = f
                f.detail = SecretMask.apply(f.detail, sensitive: sensitive)
                f.evidence = f.evidence.map { SecretMask.apply($0, sensitive: sensitive) }
                return f
            }
            .sorted { ($0.severity.rank, $0.ruleID, $0.target) < ($1.severity.rank, $1.ruleID, $1.target) }
        return MCPServerResult(raw: server, findings: findings, score: Scoring.score(findings).total)
    }

    // MARK: Parsing (JSONC-aware, many client shapes)

    public static func parseServers(from data: Data, path: String, source: String = "Config") throws -> [MCPServerConfig] {
        let cleaned = stripJSONComments(String(decoding: data, as: UTF8.self))
        let object = try JSONSerialization.jsonObject(with: Data(cleaned.utf8), options: [.fragmentsAllowed])
        guard let root = object as? [String: Any] else { return [] }

        var servers: [MCPServerConfig] = []
        func collect(_ dict: Any?, prefix: String = "") {
            guard let dict = dict as? [String: Any] else { return }
            for (name, value) in dict.sorted(by: { $0.key < $1.key }) {
                guard let spec = value as? [String: Any] else { continue }
                servers.append(server(named: prefix + name, spec: spec, path: path, source: source))
            }
        }
        collect(root["mcpServers"])
        collect(root["servers"])                                  // VS Code mcp.json
        collect((root["mcp"] as? [String: Any])?["servers"])      // VS Code settings.json
        collect(root["mcp.servers"])
        collect(root["context_servers"])                          // Zed
        if let projects = root["projects"] as? [String: Any] {   // ~/.claude.json per-project servers
            for (project, value) in projects.sorted(by: { $0.key < $1.key }) {
                collect((value as? [String: Any])?["mcpServers"], prefix: "\((project as NSString).lastPathComponent) › ")
            }
        }
        return servers
    }

    static func server(named name: String, spec: [String: Any], path: String, source: String) -> MCPServerConfig {
        var s = MCPServerConfig(name: name, source: source, configPath: path)
        // Zed nests {"command": {"path": ..., "args": [...], "env": {...}}}
        let launch = (spec["command"] as? [String: Any]) ?? spec
        s.command = (launch["path"] as? String) ?? (spec["command"] as? String)
        s.args = (launch["args"] as? [Any])?.compactMap(scalar) ?? []
        s.env = stringMap(launch["env"])
        s.url = (spec["url"] as? String) ?? (spec["serverUrl"] as? String) ?? (spec["httpUrl"] as? String)
        s.headers = stringMap(spec["headers"])
        s.autoApprove = ((spec["autoApprove"] ?? spec["alwaysAllow"]) as? [Any])?.compactMap { $0 as? String } ?? []
        s.trust = (spec["trust"] as? Bool) ?? false
        s.disabled = (spec["disabled"] as? Bool) ?? false
        return s
    }

    static func scalar(_ any: Any) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    static func stringMap(_ any: Any?) -> [String: String] {
        (any as? [String: Any])?.compactMapValues(scalar) ?? [:]
    }

    /// Removes // and /* */ comments and trailing commas (JSONC, used by VS Code and Zed), leaving strings intact.
    public static func stripJSONComments(_ s: String) -> String {
        var out = ""
        var chars = Array(s)[...]
        var inString = false
        while let c = chars.first {
            chars = chars.dropFirst()
            if inString {
                out.append(c)
                if c == "\\", let n = chars.first { out.append(n); chars = chars.dropFirst() }
                else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true; out.append(c); continue }
            if c == "/", chars.first == "/" {
                while let n = chars.first, n != "\n" { chars = chars.dropFirst() }
                continue
            }
            if c == "/", chars.first == "*" {
                chars = chars.dropFirst()
                while !chars.isEmpty {
                    if chars.first == "*", chars.dropFirst().first == "/" { chars = chars.dropFirst(2); break }
                    chars = chars.dropFirst()
                }
                continue
            }
            if c == "," {
                let rest = chars.drop(while: { $0.isWhitespace })
                if let n = rest.first, n == "}" || n == "]" { continue }
            }
            out.append(c)
        }
        return out
    }

    // MARK: Glink rules (things Tollgate v1 doesn't check)

    public static func glinkFindings(for server: MCPServerConfig, homeDirectory: String = NSHomeDirectory(),
                                     filePermissions: Int? = nil, hasSecret: Bool = false) -> [Finding] {
        var out: [Finding] = []
        func add(_ rule: String, _ sev: Severity, _ cat: MCPShieldCore.Category, _ title: String, _ detail: String, _ fix: String) {
            out.append(Finding(ruleID: rule, title: title, severity: sev, category: cat, target: server.name, detail: detail, fix: fix))
        }
        let command = server.command ?? ""
        let commandName = (command as NSString).lastPathComponent.lowercased()

        // GLK-001: privilege escalation
        if commandName == "sudo" || server.args.contains("sudo") {
            add("GLK-001", .critical, .config, "Runs with sudo",
                "The server is launched with administrator privileges.",
                "Run MCP servers as your normal user and grant only the access they need.")
        }

        // GLK-002: Docker hardening
        if commandName == "docker" || commandName == "podman" {
            if server.args.contains("--privileged") {
                add("GLK-002", .critical, .config, "Privileged container",
                    "--privileged gives the container full access to this Mac's virtual machine and devices.",
                    "Remove --privileged and add only the capabilities the server needs.")
            }
            if server.args.contains(where: { $0.contains("docker.sock") }) {
                add("GLK-002", .critical, .config, "Docker socket mounted",
                    "Mounting docker.sock lets the server control every container.",
                    "Don't mount the Docker socket into MCP servers.")
            }
            if let i = server.args.firstIndex(of: "--network"), i + 1 < server.args.count, server.args[i + 1] == "host" {
                add("GLK-002", .medium, .config, "Host networking",
                    "--network host exposes every local service to the container.",
                    "Use the default network and publish only the ports you need.")
            }
        }

        // GLK-003: tools that run without asking
        if !server.autoApprove.isEmpty {
            let wildcard = server.autoApprove.contains("*")
            add("GLK-003", wildcard ? .high : .medium, .tools,
                wildcard ? "All tools auto-approved" : "Tools run without confirmation",
                wildcard ? "Every tool from this server runs without asking you."
                         : "\(server.autoApprove.count) tool\(server.autoApprove.count == 1 ? "" : "s") (\(server.autoApprove.prefix(3).joined(separator: ", "))) run without asking you.",
                "Only auto-approve read-only tools.")
        }

        // GLK-004: trusted server (Gemini CLI)
        if server.trust {
            add("GLK-004", .medium, .tools, "Server marked as trusted",
                "\"trust\": true skips every tool-call confirmation.",
                "Remove trust: true and approve tool calls individually.")
        }

        // GLK-005: executable in a folder any process can write to
        let riskyDirs = ["/tmp/", "/private/tmp/", "/var/tmp/", "\(homeDirectory)/Downloads/", "~/Downloads/"]
        if riskyDirs.contains(where: { command.hasPrefix($0) }) {
            add("GLK-005", .high, .config, "Runs a program from a temporary folder",
                "\(command) lives in a folder that other programs can write to.",
                "Move it somewhere protected, like /usr/local/bin or ~/.local/bin.")
        }

        // GLK-007: unknown or unverified publisher
        if let package = launchedPackage(server) {
            let lowered = package.lowercased()
            if !knownPublishers.contains(where: { lowered.hasPrefix($0) }) {
                add("GLK-007", .low, .config, "Unknown or unverified publisher",
                    "\(package) isn't from a publisher Glink recognizes. That's not necessarily bad, but it runs with your permissions.",
                    "Check the package's source and maintainer before trusting it, and pin a version you've reviewed.")
            }
        }

        // GLK-006: config holding a secret is readable by other accounts
        if hasSecret, let mode = filePermissions, mode & 0o004 != 0 {
            add("GLK-006", .medium, .secrets, "Config readable by other users",
                "This file contains a credential and every account on the Mac can read it.",
                "Run: chmod 600 \"\(server.configPath)\"")
        }
        return out
    }

    // MARK: Reports

    /// Markdown summary for "Copy Report". Secrets are already redacted in findings.
    public static func markdown(for report: MCPReport) -> String {
        var lines = ["# MCP Config Check", "",
                     "Lowest score: **\(report.score)/100 (\(report.grade))** · \(report.results.count) servers in \(report.files.count) files", ""]
        if report.results.isEmpty { lines.append("No MCP servers found.") }
        for r in report.results {
            lines.append("## \(r.raw.name) — \(r.score) (\(r.grade))")
            lines.append("_\(r.raw.source) · \(r.raw.configPath)_")
            if r.findings.isEmpty { lines.append("- No issues found.") }
            for f in r.findings {
                lines.append("- **[\(f.severity.rawValue.capitalized)] \(f.ruleID) \(f.title)**: \(f.detail)")
                if !f.fix.isEmpty { lines.append("  _Fix:_ \(f.fix)") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Tollgate's JSON export format (secrets redacted).
    public static func json(for report: MCPReport) throws -> Data {
        try Report.json(for: report.results.map(\.scanResult))
    }
}
