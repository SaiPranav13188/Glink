import AppKit
import Foundation
import GlinkCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI commands. All of them run on-device with Apple's Foundation Models.
enum AICommand: String, Hashable, CaseIterable, Identifiable {
    case ask, rewriteProfessional, makeShorter, fixGrammar, summarizeClipboard, explain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask AI"
        case .rewriteProfessional: "Rewrite Selected Text: More Professional"
        case .makeShorter: "Rewrite Selected Text: Shorter"
        case .fixGrammar: "Rewrite Selected Text: Fix Grammar"
        case .summarizeClipboard: "Summarize Clipboard"
        case .explain: "Explain Selected Text"
        }
    }

    var symbol: String {
        switch self {
        case .ask: "sparkles"
        case .rewriteProfessional: "briefcase"
        case .makeShorter: "arrow.down.right.and.arrow.up.left"
        case .fixGrammar: "textformat.abc"
        case .summarizeClipboard: "doc.on.clipboard"
        case .explain: "lightbulb"
        }
    }

    enum Source { case none, selection, clipboard }

    var source: Source {
        switch self {
        case .ask: .none
        case .summarizeClipboard: .clipboard
        default: .selection
        }
    }

    /// Whether the result is meant to replace the selected text (so "Replace Selection" is primary).
    var replacesSelection: Bool { [.rewriteProfessional, .fixGrammar, .makeShorter].contains(self) }

    var instruction: String? {
        switch self {
        case .ask: nil
        case .rewriteProfessional: "Rewrite the following text so it sounds clear and professional. Keep the meaning and language. Reply with only the rewritten text."
        case .makeShorter: "Make the following text shorter while keeping its meaning. Reply with only the shortened text."
        case .fixGrammar: "Fix spelling and grammar in the following text. Change nothing else. Reply with only the corrected text."
        case .summarizeClipboard: "Summarize the following text in a few concise bullet points."
        case .explain: "Explain the following text in simple terms. If it is code, explain what it does."
        }
    }
}

struct AIRequest: Hashable {
    let id = UUID()
    var command: AICommand
    var input: String
    /// Where the input came from, shown above the response ("Selected text in Notes").
    var sourceLabel: String?
}

/// Glink's AI: Apple's on-device Foundation Models. No API keys, no network.
@MainActor
enum AIService {
    static let engine = AIEngine(model: FoundationModelsBackend(), isEnabled: { UserDefaults.standard.object(forKey: "aiEnabled") as? Bool ?? true })

    static var availability: AIAvailability { engine.availability }

    static func openAppleIntelligenceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}

/// Bridges Foundation Models (macOS 26+) to GlinkCore's `OnDeviceModel`.
struct FoundationModelsBackend: OnDeviceModel {
    var availability: AIAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible): return .unavailable(.deviceNotEligible)
            case .unavailable(.appleIntelligenceNotEnabled): return .unavailable(.appleIntelligenceOff)
            case .unavailable(.modelNotReady): return .unavailable(.modelNotReady)
            case .unavailable(let other): return .unavailable(.other(String(describing: other)))
            }
        }
        #endif
        return .unavailable(.osTooOld)
    }

    func streamResponse(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let session = LanguageModelSession(instructions: instructions)
                        for try await snapshot in session.streamResponse(to: prompt) {
                            continuation.yield(snapshot.content)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        #endif
        return AsyncThrowingStream { $0.finish(throwing: AIEngineError.unavailable(.osTooOld)) }
    }
}
