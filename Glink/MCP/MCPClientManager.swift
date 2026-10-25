import Foundation
import GlinkCore
import MCP
import Observation
import SwiftData
import System

/// Glink as an MCP client: launches enabled stdio servers, lists their tools, and calls them.
@MainActor @Observable
final class MCPClientManager {
    static let shared = MCPClientManager()

    enum State: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    struct ToolInfo: Identifiable, Hashable {
        var id: String { "\(serverID.uuidString)::\(name)" }
        let serverID: UUID
        let serverName: String
        let name: String
        let description: String?
        let schema: JSONValue
        let classifiedRisk: ToolRisk
    }

    private(set) var states: [UUID: State] = [:]
    private(set) var tools: [UUID: [ToolInfo]] = [:]
    @ObservationIgnored private var connections: [UUID: Connection] = [:]

    static let callTimeout: Double = 10

    @MainActor final class Connection {
        let process: Process
        let client: Client
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        var stderrTail = ""
        init(process: Process, client: Client) {
            self.process = process
            self.client = client
        }
    }

    var allTools: [ToolInfo] { tools.values.flatMap { $0 }.sorted { $0.name < $1.name } }

    func state(of id: UUID) -> State { states[id] ?? .disconnected }

    // MARK: Lifecycle

    func connectEnabledServers() {
        let entries = (try? DataStore.shared.context.fetch(FetchDescriptor<MCPServerEntry>())) ?? []
        for entry in entries where entry.enabled { Task { await connect(entry) } }
    }

    func connect(_ entry: MCPServerEntry) async {
        disconnect(entry.id)
        let id = entry.id, name = entry.name
        states[id] = .connecting

        let process = Process()
        // GUI apps get a minimal PATH; servers launched with npx/uvx need the usual tool folders.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                       NSHomeDirectory() + "/.local/bin", env["PATH"] ?? ""].joined(separator: ":")
        for (k, v) in entry.env { env[k] = v }
        process.environment = env
        if entry.command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: entry.command)
            process.arguments = entry.args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [entry.command] + entry.args
        }

        let client = Client(name: "Glink", version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0")
        let conn = Connection(process: process, client: client)
        process.standardInput = conn.stdin
        process.standardOutput = conn.stdout
        process.standardError = conn.stderr
        conn.stderr.fileHandleForReading.readabilityHandler = { [weak conn] h in
            let text = String(decoding: h.availableData, as: UTF8.self)
            Task { @MainActor in
                guard let conn else { return }
                conn.stderrTail = String((conn.stderrTail + text).suffix(2000))
            }
        }
        process.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self, self.connections[id]?.process === p else { return }
                self.connections[id] = nil
                self.tools[id] = nil
                let detail = conn.stderrTail.split(separator: "\n").last.map(String.init) ?? "exit code \(p.terminationStatus)"
                self.states[id] = .failed("\(name) stopped: \(detail)")
            }
        }

        do {
            try process.run()
            connections[id] = conn
            let transport = StdioTransport(
                input: FileDescriptor(rawValue: conn.stdout.fileHandleForReading.fileDescriptor),
                output: FileDescriptor(rawValue: conn.stdin.fileHandleForWriting.fileDescriptor))
            try await Self.withTimeout(20) { _ = try await client.connect(transport: transport) }
            let (list, _) = try await Self.withTimeout(Self.callTimeout) { try await client.listTools() }
            tools[id] = list.map { tool in
                let schema = (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(tool.inputSchema))) ?? .object([:])
                let argNames = schema.object?["properties"]?.object.map { Array($0.keys) } ?? []
                return ToolInfo(serverID: id, serverName: name, name: tool.name, description: tool.description, schema: schema,
                                classifiedRisk: ToolRiskClassifier.classify(name: tool.name, description: tool.description,
                                                                           argumentNames: argNames))
            }
            states[id] = .connected
        } catch {
            let detail = conn.stderrTail.split(separator: "\n").last.map(String.init)
            disconnect(id)
            states[id] = .failed(detail ?? error.localizedDescription)
        }
    }

    func disconnect(_ id: UUID) {
        guard let conn = connections.removeValue(forKey: id) else { states[id] = .disconnected; return }
        conn.stderr.fileHandleForReading.readabilityHandler = nil
        let client = conn.client
        Task { await client.disconnect() }
        if conn.process.isRunning { conn.process.terminate() }
        tools[id] = nil
        states[id] = .disconnected
    }

    /// Terminates every server process (Glink quitting).
    func disconnectAll() {
        for id in Array(connections.keys) { disconnect(id) }
    }

    // MARK: Calling tools

    struct CallResult {
        let text: String
        let isError: Bool
    }

    enum CallError: LocalizedError {
        case notConnected(String), timedOut(Double), server(String)
        var errorDescription: String? {
            switch self {
            case .notConnected(let s): "\(s) isn't connected."
            case .timedOut(let t): "The tool didn't answer within \(Int(t)) seconds."
            case .server(let m): m
            }
        }
    }

    func call(_ tool: ToolInfo, arguments: [String: JSONValue]) async throws -> CallResult {
        guard let conn = connections[tool.serverID] else { throw CallError.notConnected(tool.serverName) }
        let data = try JSONEncoder().encode(arguments)
        let args = try JSONDecoder().decode([String: Value].self, from: data)
        let client = conn.client
        do {
            let (content, isError) = try await Self.withTimeout(Self.callTimeout) {
                try await client.callTool(name: tool.name, arguments: args)
            }
            let text = content.map { item -> String in
                switch item {
                case .text(let text, _, _): text
                case .image(_, let mime, _, _): "[image \(mime)]"
                case .audio(_, let mime, _, _): "[audio \(mime)]"
                case .resource(let resource, _, _): String(describing: resource)
                case .resourceLink(let uri, let name, _, _, _, _): "[\(name)](\(uri))"
                }
            }.joined(separator: "\n")
            return CallResult(text: text, isError: isError ?? false)
        } catch is TimeoutError {
            throw CallError.timedOut(Self.callTimeout)
        } catch let error as CallError {
            throw error
        } catch {
            throw CallError.server(error.localizedDescription)
        }
    }

    struct TimeoutError: Error {}

    static func withTimeout<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimeoutError() }
            return first
        }
    }

    // MARK: Permissions (persisted per server + tool)

    var policy: PermissionPolicy {
        let prefs = (try? DataStore.shared.context.fetch(FetchDescriptor<MCPToolPreference>())) ?? []
        var p = PermissionPolicy()
        for pref in prefs {
            if pref.alwaysAllow { p.alwaysAllowed.insert(pref.key) }
            if pref.riskOverride >= 0, let r = ToolRisk(rawValue: pref.riskOverride) { p.riskOverrides[pref.key] = r }
        }
        return p
    }

    func preference(server: String, tool: String) -> MCPToolPreference {
        let key = PermissionPolicy.key(server: server, tool: tool)
        let ctx = DataStore.shared.context
        if let existing = try? ctx.fetch(FetchDescriptor<MCPToolPreference>(predicate: #Predicate { $0.key == key })).first {
            return existing
        }
        let pref = MCPToolPreference(key: key)
        ctx.insert(pref)
        return pref
    }

    // MARK: Audit log

    func audit(_ tool: ToolInfo, arguments: [String: JSONValue], summary: String, decision: String, durationMs: Int,
               risk: ToolRisk, injection: InjectionDetector.Report? = nil, aiReason: String? = nil) {
        let masked = ArgumentMasker.mask(.object(arguments)).jsonText
        let record = MCPAuditRecord(server: tool.serverName, tool: tool.name, argumentsJSON: masked,
                                    resultSummary: String(SecretMask.apply(summary, sensitive: []).prefix(400)),
                                    decision: decision, durationMs: durationMs, risk: risk.title,
                                    injection: injection?.verdict.title ?? "Clean",
                                    injectionReason: [injection?.isFlagged == true ? injection?.summary : nil, aiReason]
                                        .compactMap { $0 }.joined(separator: " · "))
        DataStore.shared.context.insert(record)
        DataStore.shared.save()
    }
}
