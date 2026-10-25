import Foundation

// MARK: - Tool risk

/// How much a tool can affect the Mac or the outside world. Ordered from harmless to riskiest.
public enum ToolRisk: Int, Sendable, Codable, CaseIterable, Comparable {
    case readOnly = 0, network, writes, deletes, runsCommands

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .readOnly: "Read-only"
        case .network: "Network access"
        case .writes: "Writes data"
        case .deletes: "Deletes data"
        case .runsCommands: "Runs commands"
        }
    }

    public var needsPermission: Bool { self != .readOnly }
}

/// Heuristic classifier: tool name, description and argument names → risk.
public enum ToolRiskClassifier {
    static let commandWords: Set<String> = ["exec", "execute", "run", "shell", "bash", "command", "cmd", "spawn",
                                            "terminal", "eval", "script", "process", "sudo", "install"]
    static let deleteWords: Set<String> = ["delete", "remove", "rm", "drop", "destroy", "purge", "erase", "wipe",
                                           "truncate", "unlink", "trash", "clear", "revoke"]
    static let writeWords: Set<String> = ["write", "create", "update", "edit", "modify", "set", "put", "post", "insert",
                                          "move", "rename", "copy", "upload", "save", "append", "patch", "send", "publish",
                                          "commit", "push", "merge", "add", "make", "apply", "replace", "change", "mkdir",
                                          "pay", "transfer", "book", "order", "submit", "deploy", "comment", "reply"]
    static let networkWords: Set<String> = ["fetch", "http", "https", "url", "request", "download", "browse", "web",
                                            "navigate", "scrape", "crawl", "api", "webhook", "email", "slack"]
    static let readWords: Set<String> = ["get", "list", "read", "find", "search", "fetch", "show", "describe", "view",
                                         "query", "count", "info", "status", "check", "inspect", "lookup", "stat"]

    /// Splits `delete_file`, `deleteFile`, `delete-file` and plain text into lowercase words.
    public static func words(_ text: String) -> [String] {
        var out: [String] = [], cur = ""
        for ch in text {
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase, let last = cur.last, last.isLowercase { out.append(cur.lowercased()); cur = "" }
                cur.append(ch)
            } else if !cur.isEmpty { out.append(cur.lowercased()); cur = "" }
        }
        if !cur.isEmpty { out.append(cur.lowercased()) }
        return out
    }

    /// The name decides first (it's the most deliberate signal); the description and argument names can
    /// only raise the risk, never lower it.
    /// The word plus simple stems ("deletes" → "delete", "created" → "create"), so descriptions match too.
    static func stems(_ word: String) -> [String] {
        var out = [word]
        for suffix in ["ing", "es", "ed", "s", "d"] where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
            out.append(String(word.dropLast(suffix.count)))
        }
        return out
    }

    public static func classify(name: String, description: String? = nil, argumentNames: [String] = []) -> ToolRisk {
        let nameWords = Set(words(name).flatMap(stems))
        let other = Set((words(description ?? "") + argumentNames.flatMap(words)).flatMap(stems))

        func risk(in w: Set<String>) -> ToolRisk? {
            if !w.isDisjoint(with: commandWords) { return .runsCommands }
            if !w.isDisjoint(with: deleteWords) { return .deletes }
            if !w.isDisjoint(with: writeWords) { return .writes }
            if !w.isDisjoint(with: networkWords) { return .network }
            return nil
        }

        let fromName = risk(in: nameWords)
        // A name that starts with a read verb ("get_…", "list_…") is read-only unless it says otherwise.
        if fromName == nil, let first = words(name).first, readWords.contains(first) {
            let fromArgs = risk(in: Set(argumentNames.flatMap(words)))
            return fromArgs == .runsCommands ? .runsCommands : .readOnly
        }
        let fromOther = risk(in: other)
        return [fromName, fromOther].compactMap { $0 }.max() ?? .readOnly
    }
}

// MARK: - Permission decisions

public enum ToolDecision: Sendable, Equatable {
    /// Run without asking (read-only, or the user said "always allow").
    case run
    /// Show the permission sheet first.
    case ask
}

/// Decides whether a tool call needs the user's permission. "Always allow" choices and risk
/// overrides are keyed per server + tool.
public struct PermissionPolicy: Sendable {
    public var alwaysAllowed: Set<String>
    public var riskOverrides: [String: ToolRisk]

    public init(alwaysAllowed: Set<String> = [], riskOverrides: [String: ToolRisk] = [:]) {
        self.alwaysAllowed = alwaysAllowed
        self.riskOverrides = riskOverrides
    }

    public static func key(server: String, tool: String) -> String { "\(server)::\(tool)" }

    public func risk(server: String, tool: String, classified: ToolRisk) -> ToolRisk {
        riskOverrides[Self.key(server: server, tool: tool)] ?? classified
    }

    public func decide(server: String, tool: String, classified: ToolRisk) -> ToolDecision {
        let risk = risk(server: server, tool: tool, classified: classified)
        guard risk.needsPermission else { return .run }
        return alwaysAllowed.contains(Self.key(server: server, tool: tool)) ? .run : .ask
    }

    public mutating func allowAlways(server: String, tool: String) { alwaysAllowed.insert(Self.key(server: server, tool: tool)) }
    public mutating func revoke(server: String, tool: String) { alwaysAllowed.remove(Self.key(server: server, tool: tool)) }
}

// MARK: - Masking arguments for the audit log

public enum ArgumentMasker {
    static let secretWords: Set<String> = ["key", "token", "secret", "password", "passwd", "pwd", "apikey", "auth",
                                           "authorization", "credential", "credentials", "cookie", "session"]

    /// Masks values under secret-looking keys and known key formats anywhere, to their first 4 characters.
    public static func mask(_ value: JSONValue, key: String? = nil) -> JSONValue {
        switch value {
        case .string(let s):
            if let key, !Set(ToolRiskClassifier.words(key)).isDisjoint(with: secretWords) { return .string(SecretMask.mask(s)) }
            return .string(SecretMask.apply(s, sensitive: []))
        case .object(let o):
            return .object(o.reduce(into: [:]) { $0[$1.key] = mask($1.value, key: $1.key) })
        case .array(let a):
            return .array(a.map { mask($0, key: key) })
        default:
            return value
        }
    }
}

// MARK: - JSON values (schema-driven forms, arguments)

public enum JSONValue: Sendable, Hashable, Codable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var object: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }

    /// Compact, stable JSON (sorted keys) for previews and the audit log.
    public var jsonText: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }
}

/// A form field generated from a tool's JSON input schema.
public struct ToolFormField: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case text, multiline, integer, number, toggle, choice([String]), json }
    public var id: String { name }
    public let name: String
    public let title: String
    public let help: String?
    public let kind: Kind
    public let required: Bool
    public let defaultValue: String?
}

public enum ToolForm {
    /// Builds fields from `{"type":"object","properties":{…},"required":[…]}`.
    public static func fields(from schema: JSONValue) -> [ToolFormField] {
        guard let props = schema.object?["properties"]?.object else { return [] }
        let required = Set(schema.object?["required"]?.array?.compactMap(\.string) ?? [])
        return props.keys.sorted { (required.contains($0) ? 0 : 1, $0) < (required.contains($1) ? 0 : 1, $1) }.map { name in
            let p = props[name]?.object ?? [:]
            let type = p["type"]?.string ?? p["type"]?.array?.compactMap(\.string).first { $0 != "null" } ?? "string"
            let kind: ToolFormField.Kind
            if let options = p["enum"]?.array?.compactMap(\.string), !options.isEmpty { kind = .choice(options) }
            else {
                switch type {
                case "integer": kind = .integer
                case "number": kind = .number
                case "boolean": kind = .toggle
                case "array", "object": kind = .json
                default:
                    let lname = name.lowercased()
                    kind = ["content", "text", "body", "code", "query", "message"].contains(lname) ? .multiline : .text
                }
            }
            let def: String? = switch p["default"] {
            case .string(let s): s
            case .number(let n): n == n.rounded() ? String(Int(n)) : String(n)
            case .bool(let b): b ? "true" : "false"
            default: nil
            }
            let title = p["title"]?.string ?? name.replacingOccurrences(of: "_", with: " ").capitalizedFirstLetter
            return ToolFormField(name: name, title: title, help: p["description"]?.string, kind: kind,
                                 required: required.contains(name), defaultValue: def)
        }
    }

    public enum FormError: Error, Equatable, LocalizedError {
        case missing(String), invalid(String)
        public var errorDescription: String? {
            switch self {
            case .missing(let f): "“\(f)” is required."
            case .invalid(let f): "“\(f)” isn't valid."
            }
        }
    }

    /// Turns the form's text values into tool arguments, validating required and typed fields.
    public static func arguments(fields: [ToolFormField], values: [String: String]) throws -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for f in fields {
            let raw = (values[f.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty {
                if f.kind == .toggle { out[f.name] = .bool(false); continue }
                if f.required { throw FormError.missing(f.title) }
                continue
            }
            switch f.kind {
            case .integer:
                guard let i = Int(raw) else { throw FormError.invalid(f.title) }
                out[f.name] = .number(Double(i))
            case .number:
                guard let d = Double(raw) else { throw FormError.invalid(f.title) }
                out[f.name] = .number(d)
            case .toggle:
                out[f.name] = .bool(raw == "true" || raw == "1" || raw == "yes")
            case .json:
                guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)) else {
                    // A bare value in a list field becomes a one-element list.
                    out[f.name] = .array([.string(raw)])
                    continue
                }
                out[f.name] = v
            default:
                out[f.name] = .string(raw)
            }
        }
        return out
    }
}

extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
