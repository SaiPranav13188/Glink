import Foundation
import GlinkCore
import SwiftData

/// An MCP server Glink connects to as a client (Settings › MCP Servers).
@Model
final class MCPServerEntry {
    @Attribute(.unique) var id: UUID
    var name: String
    var command: String
    var args: [String]
    /// KEY=VALUE lines.
    var envText: String
    var enabled: Bool
    /// Letter grade from the MCP security check when it was last enabled.
    var grade: String
    var createdAt: Date

    init(name: String, command: String, args: [String], envText: String = "") {
        id = UUID()
        self.name = name
        self.command = command
        self.args = args
        self.envText = envText
        enabled = false
        grade = "?"
        createdAt = Date()
    }

    var env: [String: String] {
        envText.split(whereSeparator: \.isNewline).reduce(into: [:]) { out, line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { out[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1] }
        }
    }

    /// Runs Glink's MCP security rules on this entry.
    var securityResult: MCPServerResult {
        var raw = MCPServerConfig(name: name, source: "Glink", configPath: "Glink settings")
        raw.command = command
        raw.args = args
        raw.env = env
        return MCPConfigAnalyzer.analyze(raw)
    }

    /// Servers graded C or below are treated as untrusted: their results also get the AI injection check.
    var isUntrusted: Bool { !["A", "B"].contains(grade) }
}

/// Per server + tool: "always allow" and a user override of the risk classification.
@Model
final class MCPToolPreference {
    @Attribute(.unique) var key: String
    var alwaysAllow: Bool
    /// ToolRisk raw value, or -1 for "use the automatic classification".
    var riskOverride: Int

    init(key: String) {
        self.key = key
        alwaysAllow = false
        riskOverride = -1
    }
}

/// One MCP tool call (or denied attempt). Arguments are stored with secrets masked.
@Model
final class MCPAuditRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var server: String
    var tool: String
    var argumentsJSON: String
    var resultSummary: String
    /// "allowed", "always-allowed", "auto (read-only)", "denied", "failed"
    var decision: String
    var durationMs: Int
    var risk: String
    /// Prompt-injection verdict for the result: Clean / Suspicious / Likely prompt injection.
    var injection: String
    var injectionReason: String

    init(server: String, tool: String, argumentsJSON: String, resultSummary: String, decision: String,
         durationMs: Int, risk: String, injection: String = "Clean", injectionReason: String = "") {
        id = UUID()
        timestamp = Date()
        self.server = server
        self.tool = tool
        self.argumentsJSON = argumentsJSON
        self.resultSummary = resultSummary
        self.decision = decision
        self.durationMs = durationMs
        self.risk = risk
        self.injection = injection
        self.injectionReason = injectionReason
    }
}
