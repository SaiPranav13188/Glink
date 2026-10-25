import Foundation

/// Layer 1 of prompt-injection detection: fast pattern rules over MCP tool output.
/// Runs on every result before it's shown or handed to the on-device AI.
public enum InjectionDetector {
    public enum Verdict: Int, Sendable, Comparable, Codable {
        case clean = 0, suspicious, malicious
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        public var title: String {
            switch self {
            case .clean: "Clean"
            case .suspicious: "Suspicious"
            case .malicious: "Likely prompt injection"
            }
        }
    }

    public struct Match: Sendable, Equatable {
        public let rule: String
        public let reason: String
        public let severity: Verdict
        /// The matched text (as it appears in the result) for highlighting.
        public let snippet: String
    }

    public struct Report: Sendable, Equatable {
        public let matches: [Match]
        public var verdict: Verdict { matches.map(\.severity).max() ?? .clean }
        public var isFlagged: Bool { verdict != .clean }
        public var summary: String {
            guard let top = matches.max(by: { $0.severity < $1.severity }) else { return "No injection patterns found." }
            return top.reason + (matches.count > 1 ? " (+\(matches.count - 1) more)" : "")
        }
    }

    struct Rule {
        let id: String
        let severity: Verdict
        let reason: String
        let regex: NSRegularExpression
    }

    private static func rule(_ id: String, _ severity: Verdict, _ reason: String, _ pattern: String) -> Rule {
        Rule(id: id, severity: severity, reason: reason,
             regex: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]))
    }

    static let rules: [Rule] = [
        rule("INJ-001", .malicious, "Tries to override earlier instructions",
             #"\b(ignore|disregard|forget|override|bypass)\b[^.\n]{0,40}\b(previous|prior|above|earlier|all|your|the|any)\b[^.\n]{0,30}\b(instructions?|prompts?|rules|guidelines|directions|context|messages?)"#),
        rule("INJ-002", .malicious, "Tries to give the assistant a new role",
             #"\b(you are now|from now on,? you (are|will|must)|act as (an?|the) (unrestricted|jailbroken|developer|admin|dan)|pretend (to be|you are)|new (role|persona|identity)\s*:)"#),
        rule("INJ-003", .suspicious, "Talks about the system prompt or hidden instructions",
             #"\b(system prompt|system message|hidden instructions?|developer (mode|message)|reveal (your|the) (prompt|instructions))\b"#),
        rule("INJ-004", .malicious, "Hidden instructions inside an HTML comment",
             #"<!--(?:(?!-->).){0,400}?\b(ignore|instruction|assistant|ai|model|you must|do not tell|system)\b(?:(?!-->).){0,400}?-->"#),
        rule("INJ-005", .malicious, "Asks to send data to a URL or email",
             #"\b(send|post|upload|forward|exfiltrate|leak|transmit|email)\b[^\n]{0,80}?\b(to|at|into)\s+(https?://|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})"#),
        rule("INJ-006", .malicious, "Asks the assistant to call other tools or run commands",
             #"\b(call|invoke|use|run|execute)\b[^.\n]{0,25}\b(the )?(tool|function|command|shell|terminal)\b[^.\n]{0,40}\b(now|immediately|without (asking|confirmation|telling))"#),
        rule("INJ-007", .suspicious, "Asks to keep something secret from the user",
             #"\b(do not|don'?t|never)\b[^.\n]{0,15}\b(tell|inform|mention|reveal|show)\b[^.\n]{0,15}\b(the )?(user|human|operator)\b"#),
        rule("INJ-008", .suspicious, "Mentions credentials together with an action",
             #"\b(api[_ -]?keys?|passwords?|secrets?|tokens?|ssh keys?|credentials?)\b[^\n]{0,40}?\b(send|share|print|output|paste|include|reveal|cat)\b|\b(send|share|print|output|paste|include|reveal|cat)\b[^\n]{0,40}?(api[_ -]?keys?|passwords?|ssh keys?|credentials|\.env\b|id_rsa)"#),
        rule("INJ-009", .malicious, "Fake conversation markers that impersonate the system or assistant",
             #"(^|\n)\s*(###\s*)?(system|assistant)\s*:|<\|im_start\|>|\[INST\]|<\/?(system|instructions?)>"#),
    ]

    /// Zero-width and bidi-control characters used to hide text.
    static let invisible: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}",
                                                  "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
                                                  "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{E0001}"]
    static let base64Blob = try! NSRegularExpression(pattern: #"[A-Za-z0-9+/]{40,}={0,2}"#)

    public static func scan(_ text: String) -> Report {
        var matches: [Match] = []
        let range = NSRange(text.startIndex..., in: text)
        for rule in rules {
            for m in rule.regex.matches(in: text, range: range).prefix(3) {
                guard let r = Range(m.range, in: text) else { continue }
                matches.append(Match(rule: rule.id, reason: rule.reason, severity: rule.severity,
                                     snippet: String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }

        // Invisible characters, including Unicode "tag" characters that can smuggle ASCII.
        let hidden = text.unicodeScalars.filter { invisible.contains($0) || (0xE0000...0xE007F).contains($0.value) }
        if hidden.count >= 2 {
            let decodedTags = String(String.UnicodeScalarView(text.unicodeScalars.compactMap {
                (0xE0020...0xE007E).contains($0.value) ? Unicode.Scalar($0.value - 0xE0000) : nil
            }))
            let nested = decodedTags.isEmpty ? [] : scan(decodedTags).matches
            matches.append(Match(rule: "INJ-010", reason: nested.isEmpty ? "Contains invisible characters that can hide text"
                                     : "Hides instructions in invisible characters",
                                 severity: nested.isEmpty ? .suspicious : .malicious,
                                 snippet: "\(hidden.count) invisible characters"))
        }

        // Base64 blobs that decode to instructions.
        for m in base64Blob.matches(in: text, range: range).prefix(5) {
            guard let r = Range(m.range, in: text) else { continue }
            let blob = String(text[r])
            guard let data = Data(base64Encoded: blob.padding(toLength: (blob.count + 3) / 4 * 4, withPad: "=", startingAt: 0)),
                  let decoded = String(data: data, encoding: .utf8) else { continue }
            let nested = scan(decoded).matches
            if !nested.isEmpty {
                matches.append(Match(rule: "INJ-011", reason: "Base64 text that decodes to instructions (\(nested[0].reason.lowercased()))",
                                     severity: .malicious, snippet: String(blob.prefix(40)) + "…"))
            }
        }
        return Report(matches: matches)
    }
}
