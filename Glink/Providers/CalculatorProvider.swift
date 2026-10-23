import AppKit
import GlinkCore

/// Inline math and unit conversion as you type.
@MainActor
final class CalculatorProvider: SearchProvider {
    let id = "calculator"
    let sectionTitle = "Calculator"
    let sectionOrder = 0
    let limit = 1

    func results(for query: String) async -> [SearchItem] {
        guard let result = Calculator.evaluate(query) else { return [] }
        let answer = result.formatted
        let plain = result.unit == nil ? Calculator.format(result.value, locale: Locale(identifier: "en_US_POSIX"))
                                                     .replacingOccurrences(of: ",", with: "")
                                       : answer
        // A stable ID keeps the row alive while typing, so its digits roll instead of the row being replaced.
        return [SearchItem(
            id: "calculator",
            title: answer,
            subtitle: result.inputDescription,
            icon: .symbol("equal", tint: .orange),
            kind: .calculator,
            score: 10,
            accessory: result.resultLabel,
            actions: [
                ItemAction(id: "copy", title: "Copy Answer", symbol: "doc.on.doc", shortcut: .returnKey) {
                    Paster.copy(plain)
                    return .dismissWithHUD("Copied to Clipboard")
                },
                ItemAction(id: "paste", title: "Paste Answer", symbol: "doc.on.clipboard", shortcut: .cmdReturn) {
                    Paster.paste(plain)
                    return .dismiss
                },
                ItemAction(id: "copyFull", title: "Copy Full Equation", symbol: "equal.square",
                           shortcut: KeyHint([.command, .shift], "c")) {
                    Paster.copy("\(query) = \(answer)")
                    return .toast(.success("Copied Equation"))
                },
            ],
            calculation: CalculationPayload(input: result.inputDescription, result: answer, resultLabel: result.resultLabel)
        )]
    }
}
