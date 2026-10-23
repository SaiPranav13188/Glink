import Foundation

/// Finds MCP server configs on this Mac. Read-only: it never writes to any file.
public enum ConfigDiscovery {
    /// What happened when one config file was read. Shown as a note in the UI.
    public struct FileStatus: Identifiable, Hashable, Sendable {
        public enum State: Hashable, Sendable { case loaded(Int), missing, unreadable, invalidJSON, noServers }
        public var id: String { "\(label)::\(path)" }
        public let label: String
        public let path: String
        public let state: State

        public var note: String {
            switch state {
            case .loaded(let n): return n == 1 ? "1 server" : "\(n) servers"
            case .missing: return "Not found"
            case .unreadable: return "Could not read the file"
            case .invalidJSON: return "Not valid JSON, skipped"
            case .noServers: return "No MCP servers in this file"
            }
        }
    }

    public struct Discovery: Sendable {
        public var servers: [ServerConfig] = []
        public var files: [FileStatus] = []
        public init() {}
    }

    public static func candidatePaths() -> [(label: String, url: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("Claude Desktop", home.appending(path: "Library/Application Support/Claude/claude_desktop_config.json")),
            ("Cursor", home.appending(path: ".cursor/mcp.json")),
            ("Claude Code", home.appending(path: ".claude.json")),
        ]
    }

    /// Scans the standard locations plus any extra files or folders the user added.
    public static func discover(extra: [URL] = []) -> Discovery {
        var d = Discovery()
        var seen = Set<String>()
        func add(_ label: String, _ url: URL) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            let (servers, status) = loadWithStatus(label: label, url: url)
            d.servers += servers
            d.files.append(status)
        }

        for (label, url) in candidatePaths() { add(label, url) }

        // Claude Code keeps per-project servers inside ~/.claude.json and in each project's .mcp.json.
        let claudeJSON = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
        if let root = readJSON(claudeJSON), let projects = root.object?["projects"]?.object {
            for (projectPath, value) in projects.sorted(by: { $0.key < $1.key }) {
                let servers = parseServers(value.object?["mcpServers"], label: "Claude Code (\(lastComponent(projectPath)))",
                                           path: claudeJSON.path)
                d.servers += servers
                let mcp = URL(fileURLWithPath: projectPath).appending(path: ".mcp.json")
                if FileManager.default.fileExists(atPath: mcp.path) { add("Project \(lastComponent(projectPath))", mcp) }
            }
        }

        for url in extra {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let names = [".mcp.json", "mcp.json", ".cursor/mcp.json", ".vscode/mcp.json", "claude_desktop_config.json"]
                let found = names.map { url.appending(path: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
                if found.isEmpty {
                    d.files.append(FileStatus(label: "Added folder", path: url.path, state: .noServers))
                }
                for f in found { add("Added (\(url.lastPathComponent))", f) }
            } else {
                add("Added (\(url.lastPathComponent))", url)
            }
        }
        return d
    }

    /// The plan's simple form: servers from one file, or [] if anything is wrong.
    public static func load(label: String, url: URL) -> [ServerConfig] {
        loadWithStatus(label: label, url: url).servers
    }

    public static func loadWithStatus(label: String, url: URL) -> (servers: [ServerConfig], status: FileStatus) {
        func status(_ s: FileStatus.State) -> FileStatus { FileStatus(label: label, path: url.path, state: s) }
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], status(.missing)) }
        guard let data = try? Data(contentsOf: url) else { return ([], status(.unreadable)) }
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return ([], status(.invalidJSON)) }
        // Most clients use "mcpServers"; VS Code uses "servers".
        let block = root.object?["mcpServers"] ?? root.object?["servers"]
        let servers = parseServers(block, label: label, path: url.path)
        return (servers, status(servers.isEmpty ? .noServers : .loaded(servers.count)))
    }

    /// Parses a config file's text directly. Used by tests and the evaluation set.
    public static func parse(data: Data, label: String, path: String) -> [ServerConfig] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return parseServers(root.object?["mcpServers"] ?? root.object?["servers"], label: label, path: path)
    }

    static func parseServers(_ block: JSONValue?, label: String, path: String) -> [ServerConfig] {
        guard let servers = block?.object else { return [] }
        return servers.map { name, value in
            let o = value.object ?? [:]
            return ServerConfig(
                name: name, source: label, sourcePath: path,
                command: o["command"]?.string,
                args: o["args"]?.array?.compactMap { $0.scalarText } ?? [],
                env: (o["env"]?.object ?? [:]).compactMapValues { $0.scalarText },
                url: o["url"]?.string ?? o["serverUrl"]?.string,
                headers: (o["headers"]?.object ?? [:]).compactMapValues { $0.scalarText })
        }.sorted { $0.name < $1.name }
    }

    private static func readJSON(_ url: URL) -> JSONValue? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func lastComponent(_ path: String) -> String { (path as NSString).lastPathComponent }
}
