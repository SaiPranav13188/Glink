import Foundation

public struct SnippetContext: Sendable {
    public var date: Date
    public var clipboard: String?
    public var locale: Locale
    public var timeZone: TimeZone
    public var uuid: @Sendable () -> String

    public init(date: Date = Date(), clipboard: String? = nil, locale: Locale = .current,
                timeZone: TimeZone = .current, uuid: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.date = date
        self.clipboard = clipboard
        self.locale = locale
        self.timeZone = timeZone
        self.uuid = uuid
    }
}

public struct ExpandedSnippet: Sendable, Equatable {
    public let text: String
    /// When the template contains {cursor}: how many characters the caret should move left after pasting.
    public let cursorOffsetFromEnd: Int?
}

/// Expands placeholders in snippet templates.
///
/// Supported: `{date}`, `{time}`, `{datetime}`, `{weekday}`, `{year}`, `{date:<format>}`
/// (any DateFormatter pattern), `{clipboard}`, `{uuid}`, `{cursor}`.
/// Unknown placeholders are left untouched.
public enum SnippetExpander {
    public static let placeholders = ["{date}", "{time}", "{datetime}", "{weekday}", "{year}",
                                      "{date:yyyy-MM-dd}", "{clipboard}", "{uuid}", "{cursor}"]

    public static func expand(_ template: String, context: SnippetContext = SnippetContext()) -> ExpandedSnippet {
        var output = ""
        var cursorIndex: Int?
        var i = template.startIndex

        func formatted(_ dateStyle: DateFormatter.Style, _ timeStyle: DateFormatter.Style) -> String {
            let f = DateFormatter()
            f.locale = context.locale
            f.timeZone = context.timeZone
            f.dateStyle = dateStyle
            f.timeStyle = timeStyle
            return f.string(from: context.date)
        }
        func pattern(_ p: String) -> String {
            let f = DateFormatter()
            f.locale = context.locale
            f.timeZone = context.timeZone
            f.dateFormat = p
            return f.string(from: context.date)
        }

        while i < template.endIndex {
            let ch = template[i]
            if ch == "{", let close = template[i...].firstIndex(of: "}") {
                let name = String(template[template.index(after: i)..<close])
                var replacement: String?
                switch name.lowercased() {
                case "date": replacement = formatted(.medium, .none)
                case "time": replacement = formatted(.none, .short)
                case "datetime": replacement = formatted(.medium, .short)
                case "weekday": replacement = pattern("EEEE")
                case "year": replacement = pattern("yyyy")
                case "clipboard": replacement = context.clipboard ?? ""
                case "uuid": replacement = context.uuid()
                case "cursor":
                    if cursorIndex == nil { cursorIndex = output.count }
                    replacement = ""
                default:
                    if name.lowercased().hasPrefix("date:") {
                        let p = String(name.dropFirst(5))
                        if !p.isEmpty { replacement = pattern(p) }
                    }
                }
                if let replacement {
                    output += replacement
                    i = template.index(after: close)
                    continue
                }
            }
            output.append(ch)
            i = template.index(after: i)
        }
        let offset = cursorIndex.map { output.count - $0 }
        return ExpandedSnippet(text: output, cursorOffsetFromEnd: offset)
    }
}

/// Decides whether the characters typed so far end with a snippet keyword.
public enum SnippetTrigger {
    /// Returns the longest keyword that `typed` ends with, provided the keyword starts
    /// a "word" (start of buffer, or preceded by whitespace/punctuation) so "cat" inside "concat" never fires.
    public static func match(typed: String, keywords: some Collection<String>) -> String? {
        var best: String?
        for keyword in keywords where !keyword.isEmpty && typed.hasSuffix(keyword) {
            let prefix = typed.dropLast(keyword.count)
            if let before = prefix.last {
                let keywordStartsWithSymbol = keyword.first.map { !$0.isLetter && !$0.isNumber } ?? false
                guard keywordStartsWithSymbol || before.isWhitespace || before.isPunctuation || before.isSymbol else { continue }
            }
            if best == nil || keyword.count > best!.count { best = keyword }
        }
        return best
    }
}
