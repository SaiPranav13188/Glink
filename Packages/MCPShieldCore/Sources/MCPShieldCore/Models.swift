import Foundation

public enum Severity: String, Codable, CaseIterable, Sendable {
    case critical, high, medium, low, info
    public var penalty: Int {
        switch self {
        case .critical: return 25
        case .high: return 12
        case .medium: return 5
        case .low: return 1
        case .info: return 0
        }
    }
    public var rank: Int { Severity.allCases.firstIndex(of: self)! }   // 0 = most severe
}

public enum Category: String, Codable, CaseIterable, Sendable { case config, secrets, tools, privacy }

public struct Finding: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public let ruleID: String
    public let title: String
    public let severity: Severity
    public let category: Category
    public let target: String          // e.g. "filesystem" or "filesystem.env.GITHUB_TOKEN"
    public var detail: String = ""
    public var fix: String = ""
    public var evidence: String? = nil // ALWAYS redacted for secrets

    public init(ruleID: String, title: String, severity: Severity, category: Category, target: String,
                detail: String = "", fix: String = "", evidence: String? = nil) {
        self.ruleID = ruleID; self.title = title; self.severity = severity; self.category = category
        self.target = target; self.detail = detail; self.fix = fix; self.evidence = evidence
    }
}

public struct ServerConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(source)::\(sourcePath)::\(name)" }
    public let name: String
    public let source: String          // e.g. "Claude Desktop", "Cursor"
    public let sourcePath: String
    public var command: String?
    public var args: [String] = []
    public var env: [String: String] = [:]
    public var url: String?            // remote server
    public var headers: [String: String] = [:]   // remote server HTTP headers

    public init(name: String, source: String, sourcePath: String, command: String? = nil, args: [String] = [],
                env: [String: String] = [:], url: String? = nil, headers: [String: String] = [:]) {
        self.name = name; self.source = source; self.sourcePath = sourcePath
        self.command = command; self.args = args; self.env = env; self.url = url; self.headers = headers
    }
}

public struct ScanResult: Identifiable, Codable, Sendable {
    public var id: String { server.id }
    public let server: ServerConfig
    public var findings: [Finding]
    public var score: Int
    public var categoryScores: [String: Int]

    public init(server: ServerConfig, findings: [Finding], score: Int, categoryScores: [String: Int]) {
        self.server = server; self.findings = findings; self.score = score; self.categoryScores = categoryScores
    }
}
