import Foundation

/// Converts inputs like "10 km to mi", "72f in c", "1.5 gb as mb".
public enum UnitConverter {
    enum Dimension: String, Sendable {
        case length, mass, volume, time, data, speed, area, temperature, angle
    }

    struct UnitDef: Sendable {
        let symbol: String
        let name: String
        let dimension: Dimension
        /// Multiply by this to reach the dimension's base unit (ignored for temperature).
        let factor: Double
    }

    static let units: [UnitDef] = [
        // Length (base: metre)
        .init(symbol: "mm", name: "Millimeters", dimension: .length, factor: 0.001),
        .init(symbol: "cm", name: "Centimeters", dimension: .length, factor: 0.01),
        .init(symbol: "m", name: "Meters", dimension: .length, factor: 1),
        .init(symbol: "km", name: "Kilometers", dimension: .length, factor: 1000),
        .init(symbol: "in", name: "Inches", dimension: .length, factor: 0.0254),
        .init(symbol: "ft", name: "Feet", dimension: .length, factor: 0.3048),
        .init(symbol: "yd", name: "Yards", dimension: .length, factor: 0.9144),
        .init(symbol: "mi", name: "Miles", dimension: .length, factor: 1609.344),
        .init(symbol: "nmi", name: "Nautical Miles", dimension: .length, factor: 1852),
        // Mass (base: kilogram)
        .init(symbol: "mg", name: "Milligrams", dimension: .mass, factor: 1e-6),
        .init(symbol: "g", name: "Grams", dimension: .mass, factor: 0.001),
        .init(symbol: "kg", name: "Kilograms", dimension: .mass, factor: 1),
        .init(symbol: "t", name: "Tonnes", dimension: .mass, factor: 1000),
        .init(symbol: "oz", name: "Ounces", dimension: .mass, factor: 0.028349523125),
        .init(symbol: "lb", name: "Pounds", dimension: .mass, factor: 0.45359237),
        .init(symbol: "st", name: "Stone", dimension: .mass, factor: 6.35029318),
        // Volume (base: litre)
        .init(symbol: "ml", name: "Milliliters", dimension: .volume, factor: 0.001),
        .init(symbol: "cl", name: "Centiliters", dimension: .volume, factor: 0.01),
        .init(symbol: "l", name: "Liters", dimension: .volume, factor: 1),
        .init(symbol: "m³", name: "Cubic Meters", dimension: .volume, factor: 1000),
        .init(symbol: "tsp", name: "Teaspoons", dimension: .volume, factor: 0.00492892159375),
        .init(symbol: "tbsp", name: "Tablespoons", dimension: .volume, factor: 0.01478676478125),
        .init(symbol: "fl oz", name: "Fluid Ounces", dimension: .volume, factor: 0.0295735295625),
        .init(symbol: "cup", name: "Cups", dimension: .volume, factor: 0.2365882365),
        .init(symbol: "pt", name: "Pints", dimension: .volume, factor: 0.473176473),
        .init(symbol: "qt", name: "Quarts", dimension: .volume, factor: 0.946352946),
        .init(symbol: "gal", name: "Gallons", dimension: .volume, factor: 3.785411784),
        // Time (base: second)
        .init(symbol: "ms", name: "Milliseconds", dimension: .time, factor: 0.001),
        .init(symbol: "s", name: "Seconds", dimension: .time, factor: 1),
        .init(symbol: "min", name: "Minutes", dimension: .time, factor: 60),
        .init(symbol: "h", name: "Hours", dimension: .time, factor: 3600),
        .init(symbol: "d", name: "Days", dimension: .time, factor: 86400),
        .init(symbol: "wk", name: "Weeks", dimension: .time, factor: 604_800),
        .init(symbol: "mo", name: "Months", dimension: .time, factor: 2_629_746),
        .init(symbol: "yr", name: "Years", dimension: .time, factor: 31_556_952),
        // Data (base: byte)
        .init(symbol: "bit", name: "Bits", dimension: .data, factor: 0.125),
        .init(symbol: "B", name: "Bytes", dimension: .data, factor: 1),
        .init(symbol: "KB", name: "Kilobytes", dimension: .data, factor: 1e3),
        .init(symbol: "MB", name: "Megabytes", dimension: .data, factor: 1e6),
        .init(symbol: "GB", name: "Gigabytes", dimension: .data, factor: 1e9),
        .init(symbol: "TB", name: "Terabytes", dimension: .data, factor: 1e12),
        .init(symbol: "KiB", name: "Kibibytes", dimension: .data, factor: 1024),
        .init(symbol: "MiB", name: "Mebibytes", dimension: .data, factor: 1_048_576),
        .init(symbol: "GiB", name: "Gibibytes", dimension: .data, factor: 1_073_741_824),
        .init(symbol: "TiB", name: "Tebibytes", dimension: .data, factor: 1_099_511_627_776),
        // Speed (base: m/s)
        .init(symbol: "m/s", name: "Meters per Second", dimension: .speed, factor: 1),
        .init(symbol: "km/h", name: "Kilometers per Hour", dimension: .speed, factor: 1 / 3.6),
        .init(symbol: "mph", name: "Miles per Hour", dimension: .speed, factor: 0.44704),
        .init(symbol: "kn", name: "Knots", dimension: .speed, factor: 1852.0 / 3600.0),
        .init(symbol: "ft/s", name: "Feet per Second", dimension: .speed, factor: 0.3048),
        // Area (base: m²)
        .init(symbol: "m²", name: "Square Meters", dimension: .area, factor: 1),
        .init(symbol: "km²", name: "Square Kilometers", dimension: .area, factor: 1e6),
        .init(symbol: "ft²", name: "Square Feet", dimension: .area, factor: 0.09290304),
        .init(symbol: "mi²", name: "Square Miles", dimension: .area, factor: 2_589_988.110336),
        .init(symbol: "ac", name: "Acres", dimension: .area, factor: 4046.8564224),
        .init(symbol: "ha", name: "Hectares", dimension: .area, factor: 10_000),
        // Temperature (special-cased)
        .init(symbol: "°C", name: "Celsius", dimension: .temperature, factor: 1),
        .init(symbol: "°F", name: "Fahrenheit", dimension: .temperature, factor: 1),
        .init(symbol: "K", name: "Kelvin", dimension: .temperature, factor: 1),
        // Angle (base: radian)
        .init(symbol: "°", name: "Degrees", dimension: .angle, factor: .pi / 180),
        .init(symbol: "rad", name: "Radians", dimension: .angle, factor: 1),
    ]

    /// Lower-cased aliases → unit symbol.
    static let aliases: [String: String] = {
        var map: [String: String] = [:]
        func add(_ symbol: String, _ names: [String]) { for n in names { map[n] = symbol } }
        add("mm", ["mm", "millimeter", "millimeters", "millimetre", "millimetres"])
        add("cm", ["cm", "centimeter", "centimeters", "centimetre", "centimetres"])
        add("m", ["m", "meter", "meters", "metre", "metres"])
        add("km", ["km", "kilometer", "kilometers", "kilometre", "kilometres", "kms"])
        add("in", ["in", "inch", "inches", "\""])
        add("ft", ["ft", "foot", "feet", "'"])
        add("yd", ["yd", "yard", "yards", "yds"])
        add("mi", ["mi", "mile", "miles"])
        add("nmi", ["nmi", "nautical mile", "nautical miles"])
        add("mg", ["mg", "milligram", "milligrams"])
        add("g", ["g", "gram", "grams", "gr"])
        add("kg", ["kg", "kilo", "kilos", "kilogram", "kilograms", "kgs"])
        add("t", ["tonne", "tonnes", "ton", "tons", "metric ton"])
        add("oz", ["oz", "ounce", "ounces"])
        add("lb", ["lb", "lbs", "pound", "pounds"])
        add("st", ["stone", "stones"])
        add("ml", ["ml", "milliliter", "milliliters", "millilitre", "millilitres"])
        add("cl", ["cl", "centiliter", "centiliters"])
        add("l", ["l", "liter", "liters", "litre", "litres"])
        add("m³", ["m3", "m³", "cubic meter", "cubic meters"])
        add("tsp", ["tsp", "teaspoon", "teaspoons"])
        add("tbsp", ["tbsp", "tablespoon", "tablespoons"])
        add("fl oz", ["fl oz", "floz", "fluid ounce", "fluid ounces"])
        add("cup", ["cup", "cups"])
        add("pt", ["pt", "pint", "pints"])
        add("qt", ["qt", "quart", "quarts"])
        add("gal", ["gal", "gallon", "gallons"])
        add("ms", ["ms", "millisecond", "milliseconds"])
        add("s", ["s", "sec", "secs", "second", "seconds"])
        add("min", ["min", "mins", "minute", "minutes"])
        add("h", ["h", "hr", "hrs", "hour", "hours"])
        add("d", ["day", "days"])
        add("wk", ["wk", "week", "weeks"])
        add("mo", ["month", "months"])
        add("yr", ["yr", "yrs", "year", "years"])
        add("bit", ["bit", "bits"])
        add("B", ["b", "byte", "bytes"])
        add("KB", ["kb", "kilobyte", "kilobytes"])
        add("MB", ["mb", "megabyte", "megabytes"])
        add("GB", ["gb", "gigabyte", "gigabytes"])
        add("TB", ["tb", "terabyte", "terabytes"])
        add("KiB", ["kib", "kibibyte", "kibibytes"])
        add("MiB", ["mib", "mebibyte", "mebibytes"])
        add("GiB", ["gib", "gibibyte", "gibibytes"])
        add("TiB", ["tib", "tebibyte", "tebibytes"])
        add("m/s", ["m/s", "mps", "meters per second"])
        add("km/h", ["km/h", "kmh", "kph", "kmph", "kilometers per hour"])
        add("mph", ["mph", "miles per hour"])
        add("kn", ["kn", "knot", "knots", "kt"])
        add("ft/s", ["ft/s", "fps", "feet per second"])
        add("m²", ["m2", "m²", "sqm", "square meter", "square meters"])
        add("km²", ["km2", "km²", "square kilometer", "square kilometers"])
        add("ft²", ["ft2", "ft²", "sqft", "sq ft", "square foot", "square feet"])
        add("mi²", ["mi2", "mi²", "sqmi", "square mile", "square miles"])
        add("ac", ["ac", "acre", "acres"])
        add("ha", ["ha", "hectare", "hectares"])
        add("°C", ["c", "°c", "celsius", "centigrade", "degc"])
        add("°F", ["f", "°f", "fahrenheit", "degf"])
        add("K", ["k", "kelvin"])
        add("°", ["deg", "degree", "degrees", "°"])
        add("rad", ["rad", "rads", "radian", "radians"])
        return map
    }()

    static func unit(named raw: String) -> UnitDef? {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard let symbol = aliases[key] else { return nil }
        return units.first { $0.symbol == symbol }
    }

    static let connectors = [" to ", " in ", " as ", " into ", " → ", " -> ", " = "]

    public static func convert(_ input: String, locale: Locale = .current) -> CalculatorResult? {
        let lower = input.lowercased()
        // Split on the last connector so "1 in to cm" works.
        var best: Range<String.Index>?
        for c in connectors {
            if let r = lower.range(of: c, options: .backwards), r.lowerBound > (best?.lowerBound ?? lower.startIndex) || best == nil {
                best = r
            }
        }
        guard let best else { return nil }
        let leftRaw = lower[..<best.lowerBound], rightRaw = lower[best.upperBound...]
        guard let target = unit(named: String(rightRaw)) else { return nil }

        // Left side: "<expression> <unit>", unit may be glued: "10km", "72°f".
        let left = leftRaw.trimmingCharacters(in: .whitespaces)
        guard let (amountText, source) = splitAmountAndUnit(left) else { return nil }
        guard source.dimension == target.dimension else { return nil }

        let amount: Double
        if let v = Double(amountText.replacingOccurrences(of: ",", with: "")) {
            amount = v
        } else if let e = try? ExpressionParser.parse(amountText), let v = try? e.evaluate() {
            amount = v
        } else {
            return nil
        }

        let value: Double
        if source.dimension == .temperature {
            value = convertTemperature(amount, from: source.symbol, to: target.symbol)
        } else {
            value = amount * source.factor / target.factor
        }
        guard value.isFinite else { return nil }
        // Conversions read better rounded (6.2137 mi, not 6.21371192237 mi).
        let rounded = abs(value) >= 1 ? (value * 10_000).rounded() / 10_000 : value
        let formattedNumber = Calculator.format(rounded, locale: locale, maxSignificantDigits: abs(value) >= 1 ? 12 : 4)
        return CalculatorResult(
            value: value,
            formatted: "\(formattedNumber) \(target.symbol)",
            unit: target.symbol,
            inputDescription: "\(Calculator.format(amount, locale: locale)) \(source.symbol) → \(target.symbol)",
            resultLabel: target.name
        )
    }

    static func splitAmountAndUnit(_ s: String) -> (String, UnitDef)? {
        // Try the longest unit suffix first so "fl oz" beats "oz".
        let chars = Array(s)
        for cut in 0..<chars.count {
            let amount = String(chars[..<cut]).trimmingCharacters(in: .whitespaces)
            let unitText = String(chars[cut...]).trimmingCharacters(in: .whitespaces)
            guard !amount.isEmpty, !unitText.isEmpty else { continue }
            guard let last = amount.last, last.isNumber || last == ")" || last == "." else { continue }
            if let u = unit(named: unitText) { return (amount, u) }
        }
        return nil
    }

    static func convertTemperature(_ v: Double, from: String, to: String) -> Double {
        let celsius: Double
        switch from {
        case "°F": celsius = (v - 32) * 5 / 9
        case "K": celsius = v - 273.15
        default: celsius = v
        }
        switch to {
        case "°F": return celsius * 9 / 5 + 32
        case "K": return celsius + 273.15
        default: return celsius
        }
    }
}
