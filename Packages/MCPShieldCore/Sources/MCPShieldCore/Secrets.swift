import Foundation

/// Never show a full secret. Redact everything.
public enum Secrets {
    public static func redact(_ s: String) -> String {
        s.count > 10 ? "\(s.prefix(6))...\(s.suffix(2))" : "..."
    }

    public struct Pattern: Sendable { public let name: String; public let regex: String; public let severity: Severity }

    // Order matters: a more specific pattern wins over a later one on the same text (Anthropic before OpenAI).
    public static let patterns: [Pattern] = [
        .init(name: "Google API key", regex: #"AIza[0-9A-Za-z_\-]{35}"#, severity: .critical),
        .init(name: "GitHub token", regex: #"gh[pousr]_[A-Za-z0-9]{30,}"#, severity: .critical),
        .init(name: "GitHub fine-grained token", regex: #"github_pat_[A-Za-z0-9_]{22,}"#, severity: .critical),
        .init(name: "Slack token", regex: #"xox[abposr]-\d{6,}-[0-9A-Za-z\-]{8,}"#, severity: .critical),
        .init(name: "AWS access key", regex: #"AKIA[0-9A-Z]{16}"#, severity: .critical),
        .init(name: "Private key block", regex: #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, severity: .critical),
        .init(name: "Anthropic key", regex: #"sk-ant-[A-Za-z0-9_\-]{20,}"#, severity: .critical),
        .init(name: "OpenAI key", regex: #"sk-(proj-)?[A-Za-z0-9_\-]{20,}"#, severity: .critical),
    ]

    private static let compiled: [(Pattern, NSRegularExpression)] =
        patterns.compactMap { p in (try? NSRegularExpression(pattern: p.regex)).map { (p, $0) } }

    /// Every known-secret match in `text`, without overlaps.
    public static func matches(in text: String) -> [(pattern: Pattern, value: String)] {
        let ns = text as NSString
        var taken: [NSRange] = []
        var out: [(Pattern, String)] = []
        for (p, re) in compiled {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            where !taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 })
                && !isPlaceholder(ns.substring(with: m.range)) {
                taken.append(m.range)
                out.append((p, ns.substring(with: m.range)))
            }
        }
        return out
    }

    static let placeholderWords: Set<String> = ["your", "xxx", "placeholder", "changeme", "here", "example",
                                                "dummy", "redacted", "replace", "sample", "todo"]

    /// Values copied from a README without being filled in: `<YOUR_TOKEN>`, `sk-xxxx...`, `xoxb-your-bot-token`.
    public static func isPlaceholder(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains("xxxx") || lower.contains("****") || lower.contains("...") { return true }
        if lower.contains("<") && lower.contains(">") { return true }
        return !Set(ToolRules.words(value)).isDisjoint(with: placeholderWords)
    }

    public static func scan(_ text: String, target: String) -> [Finding] {
        matches(in: text).map { p, value in
            Finding(ruleID: "SEC-001", title: "\(p.name) found", severity: p.severity,
                    category: .secrets, target: target,
                    fix: "Remove it, rotate or revoke the key, and load it from a safe place.",
                    evidence: redact(value))
        }
    }

    /// `text` with every known-secret match replaced by its redacted form.
    public static func redactMatches(in text: String) -> String {
        var out = text
        for (_, value) in matches(in: text) { out = out.replacingOccurrences(of: value, with: redact(value)) }
        return out
    }

    /// Scans every value in a server config (env, args, url, headers).
    public static func scan(_ s: ServerConfig) -> [Finding] {
        var out: [Finding] = []
        for (key, value) in s.env.sorted(by: { $0.key < $1.key }) { out += scan(value, target: "\(s.name).env.\(key)") }
        for (i, arg) in s.args.enumerated() { out += scan(arg, target: "\(s.name).args[\(i)]") }
        if let cmd = s.command { out += scan(cmd, target: "\(s.name).command") }
        if let url = s.url { out += scan(url, target: "\(s.name).url") }
        for (key, value) in s.headers.sorted(by: { $0.key < $1.key }) { out += scan(value, target: "\(s.name).headers.\(key)") }
        return out
    }
}
