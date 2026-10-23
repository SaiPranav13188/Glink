import Foundation

public struct CalculatorResult: Sendable, Equatable {
    public let value: Double
    /// Display string for the answer, e.g. "1,234.5" or "6.2137 mi".
    public let formatted: String
    /// Unit symbol of the answer when this was a conversion.
    public let unit: String?
    /// Short human description of the input, e.g. "10 km → mi".
    public let inputDescription: String
    /// Name of the answer's unit or kind, e.g. "Miles" or "Result".
    public let resultLabel: String
}

public enum CalculatorError: Error, Equatable {
    case invalid
}

public enum Calculator {
    /// Evaluates math or a unit conversion. Returns nil when the input doesn't look like math,
    /// so typing an ordinary search term never shows a calculator row.
    public static func evaluate(_ raw: String, locale: Locale = .current) -> CalculatorResult? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.count < 200 else { return nil }
        if let conversion = UnitConverter.convert(input, locale: locale) { return conversion }

        guard let expression = try? ExpressionParser.parse(input), expression.isNontrivial else { return nil }
        guard let value = try? expression.evaluate(), value.isFinite else { return nil }
        return CalculatorResult(
            value: value,
            formatted: format(value, locale: locale),
            unit: nil,
            inputDescription: input,
            resultLabel: "Result"
        )
    }

    public static func format(_ value: Double, locale: Locale = .current, maxSignificantDigits: Int = 12) -> String {
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            let f = NumberFormatter()
            f.locale = locale
            f.numberStyle = .scientific
            f.maximumFractionDigits = 6
            return f.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.maximumSignificantDigits = maxSignificantDigits
        f.usesSignificantDigits = true
        f.roundingMode = .halfEven
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Expression parser (recursive descent)

indirect enum Expr: Sendable {
    case number(Double)
    case percent(Expr)
    case unary(Character, Expr)
    case binary(Character, Expr, Expr)
    case call(String, [Expr])
    case constant(String)
    case factorial(Expr)

    /// True when the expression does real work — a bare number or constant isn't worth a calculator row.
    var isNontrivial: Bool {
        switch self {
        case .number, .constant: return false
        case .unary(_, let e): return e.isNontrivial
        default: return true
        }
    }

    func evaluate() throws -> Double {
        switch self {
        case .number(let v): return v
        case .constant(let name):
            switch name {
            case "pi", "π": return .pi
            case "e": return M_E
            case "tau", "τ": return 2 * .pi
            case "phi", "φ": return (1 + sqrt(5)) / 2
            default: throw CalculatorError.invalid
            }
        case .percent(let e): return try e.evaluate() / 100
        case .factorial(let e):
            let v = try e.evaluate()
            guard v >= 0, v <= 170, v == v.rounded() else { throw CalculatorError.invalid }
            return (0..<Int(v)).reduce(1.0) { $0 * Double($1 + 1) }
        case .unary(let op, let e):
            let v = try e.evaluate()
            return op == "-" ? -v : v
        case .binary(let op, let l, let r):
            let a = try l.evaluate()
            // "200 + 10%" means 200 + (10% of 200), like most calculators.
            if case .percent(let inner) = r, op == "+" || op == "-" {
                let p = try inner.evaluate() / 100
                return op == "+" ? a + a * p : a - a * p
            }
            let b = try r.evaluate()
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/":
                guard b != 0 else { throw CalculatorError.invalid }
                return a / b
            case "^": return pow(a, b)
            case "o": // "of" — 20% of 150
                return a * b
            case "m", "%": // modulo
                guard b != 0 else { throw CalculatorError.invalid }
                return a.truncatingRemainder(dividingBy: b)
            default: throw CalculatorError.invalid
            }
        case .call(let name, let args):
            let v = try args.map { try $0.evaluate() }
            func one() throws -> Double {
                guard v.count == 1 else { throw CalculatorError.invalid }
                return v[0]
            }
            switch name {
            case "sqrt": let x = try one(); guard x >= 0 else { throw CalculatorError.invalid }; return sqrt(x)
            case "cbrt": return cbrt(try one())
            case "sin": return sin(try one())
            case "cos": return cos(try one())
            case "tan": return tan(try one())
            case "asin": return asin(try one())
            case "acos": return acos(try one())
            case "atan": return atan(try one())
            case "ln": let x = try one(); guard x > 0 else { throw CalculatorError.invalid }; return log(x)
            case "log":
                if v.count == 2 { return log(v[1]) / log(v[0]) }
                let x = try one(); guard x > 0 else { throw CalculatorError.invalid }; return log10(x)
            case "log2": return log2(try one())
            case "abs": return abs(try one())
            case "round": return (try one()).rounded()
            case "floor": return floor(try one())
            case "ceil": return ceil(try one())
            case "exp": return exp(try one())
            case "min": guard !v.isEmpty else { throw CalculatorError.invalid }; return v.min()!
            case "max": guard !v.isEmpty else { throw CalculatorError.invalid }; return v.max()!
            default: throw CalculatorError.invalid
            }
        }
    }
}

struct ExpressionParser {
    enum Token: Equatable {
        case number(Double)
        case ident(String)
        case op(Character)
        case lparen, rparen, comma
    }

    static let functions: Set<String> = ["sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "log2",
                                          "abs", "round", "floor", "ceil", "exp", "min", "max"]
    static let constants: Set<String> = ["pi", "π", "e", "tau", "τ", "phi", "φ"]

    var tokens: [Token]
    var pos = 0

    static func parse(_ s: String) throws -> Expr {
        var p = ExpressionParser(tokens: try tokenize(s))
        guard !p.tokens.isEmpty else { throw CalculatorError.invalid }
        let e = try p.parseExpression()
        guard p.pos == p.tokens.count else { throw CalculatorError.invalid }
        return e
    }

    static func tokenize(_ s: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(s.lowercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || c == "." {
                var j = i
                var text = ""
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "," || chars[j] == "_" {
                    // Allow "1,000" grouping only when followed by exactly three digits.
                    if chars[j] == "," {
                        let next = chars[min(j + 1, chars.count - 1)..<min(j + 4, chars.count)]
                        guard next.count == 3, next.allSatisfy(\.isNumber),
                              j + 4 >= chars.count || !chars[j + 4].isNumber else { break }
                        j += 1; continue
                    }
                    if chars[j] != "_" { text.append(chars[j]) }
                    j += 1
                }
                // Scientific notation: 1e5, 2.5e-3
                if j < chars.count, chars[j] == "e", j + 1 < chars.count,
                   chars[j + 1].isNumber || ((chars[j + 1] == "-" || chars[j + 1] == "+") && j + 2 < chars.count && chars[j + 2].isNumber) {
                    text.append("e"); j += 1
                    if chars[j] == "-" || chars[j] == "+" { text.append(chars[j]); j += 1 }
                    while j < chars.count, chars[j].isNumber { text.append(chars[j]); j += 1 }
                }
                guard let v = Double(text) else { throw CalculatorError.invalid }
                tokens.append(.number(v))
                i = j
                continue
            }
            if c.isLetter || c == "π" || c == "τ" || c == "φ" {
                var j = i
                var text = ""
                while j < chars.count, chars[j].isLetter || (chars[j].isNumber && !text.isEmpty) {
                    text.append(chars[j]); j += 1
                }
                switch text {
                case "x": tokens.append(.op("*"))
                case "of": tokens.append(.op("o"))
                case "mod": tokens.append(.op("m"))
                default: tokens.append(.ident(text))
                }
                i = j
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^", "%", "!": tokens.append(.op(c))
            case "×", "·": tokens.append(.op("*"))
            case "÷": tokens.append(.op("/"))
            case "−": tokens.append(.op("-"))
            case "(", "[": tokens.append(.lparen)
            case ")", "]": tokens.append(.rparen)
            case ",": tokens.append(.comma)
            default: throw CalculatorError.invalid
            }
            i += 1
        }
        // "**" → "^"
        var merged: [Token] = []
        for t in tokens {
            if t == .op("*"), merged.last == .op("*") { merged[merged.count - 1] = .op("^") } else { merged.append(t) }
        }
        return merged
    }

    var peek: Token? { pos < tokens.count ? tokens[pos] : nil }
    mutating func next() -> Token? { defer { pos += 1 }; return peek }

    // expression := term (('+'|'-') term)*
    mutating func parseExpression() throws -> Expr {
        var lhs = try parseTerm()
        while let t = peek, case .op(let o) = t, o == "+" || o == "-" {
            pos += 1
            lhs = .binary(o, lhs, try parseTerm())
        }
        return lhs
    }

    // term := factor (('*'|'/'|mod|of) factor | implicit-multiplication)*
    mutating func parseTerm() throws -> Expr {
        var lhs = try parseUnary()
        while let t = peek {
            if case .op(let o) = t, o == "*" || o == "/" || o == "m" || o == "o" || o == "%" {
                // A "%" that reaches here is followed by an operand, so it's modulo (postfix % is handled in parsePostfix).
                pos += 1
                lhs = .binary(o, lhs, try parseUnary())
            } else if t == .lparen || isIdentStart(t) || isNumber(t) {
                // Implicit multiplication: 2pi, 3(4+1), (2)(3)
                lhs = .binary("*", lhs, try parseUnary())
            } else {
                break
            }
        }
        return lhs
    }

    func isIdentStart(_ t: Token) -> Bool { if case .ident = t { return true }; return false }
    func isNumber(_ t: Token) -> Bool { if case .number = t { return true }; return false }

    mutating func parseUnary() throws -> Expr {
        if let t = peek, case .op(let o) = t, o == "-" || o == "+" {
            pos += 1
            return .unary(o, try parseUnary())
        }
        return try parsePower()
    }

    // power := postfix ('^' unary)?   (right-associative)
    mutating func parsePower() throws -> Expr {
        let base = try parsePostfix()
        if let t = peek, t == .op("^") {
            pos += 1
            return .binary("^", base, try parseUnary())
        }
        return base
    }

    mutating func parsePostfix() throws -> Expr {
        var e = try parsePrimary()
        while let t = peek {
            if t == .op("!") { pos += 1; e = .factorial(e); continue }
            if t == .op("%") {
                // Postfix percent when not followed by an operand ("10%" / "10% + 2").
                let after = pos + 1 < tokens.count ? tokens[pos + 1] : nil
                let operandFollows: Bool = {
                    guard let after else { return false }
                    if case .number = after { return true }
                    if case .ident = after { return true }
                    return after == .lparen
                }()
                if operandFollows { break }
                pos += 1
                e = .percent(e)
                continue
            }
            break
        }
        return e
    }

    mutating func parsePrimary() throws -> Expr {
        guard let t = next() else { throw CalculatorError.invalid }
        switch t {
        case .number(let v): return .number(v)
        case .lparen:
            let e = try parseExpression()
            guard next() == .rparen else { throw CalculatorError.invalid }
            return e
        case .ident(let name):
            if Self.constants.contains(name) { return .constant(name) }
            guard Self.functions.contains(name) else { throw CalculatorError.invalid }
            if peek == .lparen {
                pos += 1
                var args: [Expr] = []
                if peek != .rparen {
                    args.append(try parseExpression())
                    while peek == .comma { pos += 1; args.append(try parseExpression()) }
                }
                guard next() == .rparen else { throw CalculatorError.invalid }
                return .call(name, args)
            }
            // "sqrt 16"
            return .call(name, [try parseUnary()])
        default:
            throw CalculatorError.invalid
        }
    }
}
