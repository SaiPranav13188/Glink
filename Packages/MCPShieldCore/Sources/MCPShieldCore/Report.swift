import Foundation

/// JSON export. No full secret may ever appear in the output.
public enum Report {
    public static let toolName = "Tollgate"
    public static let version = "1.1.0"

    /// A server config with every value that could hold a secret redacted.
    public struct RedactedServer: Codable, Sendable {
        public let name: String
        public let source: String
        public let sourcePath: String
        public let command: String?
        public let args: [String]
        public let env: [String: String]       // keys kept, values always redacted
        public let url: String?
        public let headers: [String: String]   // keys kept, values always redacted

        public init(_ s: ServerConfig) {
            name = s.name; source = s.source; sourcePath = s.sourcePath
            command = s.command.map(Secrets.redactMatches)
            args = Report.redactArgs(s.args)
            env = s.env.mapValues(Secrets.redact)
            url = s.url.map(Report.redactURL)
            headers = s.headers.mapValues(Secrets.redact)
        }
    }

    public struct Entry: Codable, Sendable {
        public let server: RedactedServer
        public let score: Int
        public let grade: String
        public let categoryScores: [String: Int]
        public let findings: [Finding]
    }

    public struct Summary: Codable, Sendable {
        public let servers: Int
        public let findings: Int
        public let bySeverity: [String: Int]
        public let lowestScore: Int?
    }

    public struct Document: Codable, Sendable {
        public let tool: String
        public let version: String
        public let generatedAt: Date
        public let note: String
        public let summary: Summary
        public let results: [Entry]
    }

    public static func document(for results: [ScanResult], at date: Date = Date()) -> Document {
        let all = results.flatMap(\.findings)
        var bySev: [String: Int] = [:]
        for f in all { bySev[f.severity.rawValue, default: 0] += 1 }
        return Document(
            tool: toolName, version: version, generatedAt: date,
            note: "Secrets are redacted. Tools and privacy are not checked in v1 and count as 100.",
            summary: Summary(servers: results.count, findings: all.count, bySeverity: bySev,
                             lowestScore: results.map(\.score).min()),
            results: results.map { r in
                Entry(server: RedactedServer(r.server), score: r.score, grade: Scoring.grade(r.score),
                      categoryScores: r.categoryScores, findings: r.findings)
            })
    }

    /// Pretty JSON for the results, with a final sweep that removes any secret that slipped through.
    public static func json(for results: [ScanResult], at date: Date = Date()) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        var text = String(decoding: try enc.encode(document(for: results, at: date)), as: UTF8.self)
        for secret in sensitiveValues(in: results.map(\.server)) where text.contains(secret) {
            text = text.replacingOccurrences(of: secret, with: Secrets.redact(secret))
        }
        return Data(text.utf8)
    }

    /// Values that must never appear in full in any output.
    public static func sensitiveValues(in servers: [ServerConfig]) -> Set<String> {
        var out = Set<String>()
        for s in servers {
            let texts = Array(s.env.values) + Array(s.headers.values) + s.args + [s.command, s.url].compactMap { $0 }
            for t in texts { for m in Secrets.matches(in: t) { out.insert(m.value) } }
            for (k, v) in s.env where looksSecretKey(k) && v.count >= 8 { out.insert(v) }
            for t in texts { if let pw = ConfigRules.connectionPassword(t) { out.insert(pw) } }
            for v in s.headers.values where v.count >= 8 { out.insert(v) }
            for (i, a) in s.args.enumerated() {
                if let (_, value) = splitFlag(a), looksSecretKey(a), value.count >= 8 { out.insert(value) }
                if looksSecretFlag(a), i + 1 < s.args.count, s.args[i + 1].count >= 8 { out.insert(s.args[i + 1]) }
            }
        }
        return out
    }

    // MARK: Helpers

    static func looksSecretKey(_ k: String) -> Bool {
        k.range(of: "(KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTH|CREDENTIAL)", options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func looksSecretFlag(_ a: String) -> Bool { a.hasPrefix("-") && !a.contains("=") && looksSecretKey(a) }
    /// `--flag=value`, or docker's `NAME=value`.
    static func splitFlag(_ a: String) -> (String, String)? {
        guard let eq = a.firstIndex(of: "="), !a[..<eq].contains("/"), !a[..<eq].contains(":") else { return nil }
        return (String(a[..<eq]), String(a[a.index(after: eq)...]))
    }

    /// `--api-key sk-...` and `--token=...` keep the flag but lose the value.
    static func redactArgs(_ args: [String]) -> [String] {
        var out: [String] = []
        for (i, a) in args.enumerated() {
            if i > 0, looksSecretFlag(args[i - 1]) { out.append(Secrets.redact(a)); continue }
            if let (flag, value) = splitFlag(a), looksSecretKey(flag) { out.append("\(flag)=\(Secrets.redact(value))"); continue }
            out.append(a.contains("://") ? redactURL(a) : Secrets.redactMatches(in: a))
        }
        return out
    }

    /// Drops passwords and query values from a URL: `https://user:pw@h/p?key=abc` -> `https://user:...@h/p?key=...`.
    static func redactURL(_ url: String) -> String {
        guard var c = URLComponents(string: url) else { return Secrets.redactMatches(in: url) }
        if c.password != nil { c.password = "..." }
        if let items = c.queryItems, !items.isEmpty { c.queryItems = items.map { URLQueryItem(name: $0.name, value: "...") } }
        return Secrets.redactMatches(in: c.string ?? url)
    }
}

public extension ServerConfig {
    /// The launch command for display, with secrets redacted.
    var redactedCommandLine: String {
        if let url { return Report.redactURL(url) }
        return ([command.map(Secrets.redactMatches) ?? ""] + Report.redactArgs(args)).joined(separator: " ")
    }
}
