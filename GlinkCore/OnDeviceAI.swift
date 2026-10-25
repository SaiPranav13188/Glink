import Foundation

/// Why on-device AI can't run. Each case has a plain-English explanation for the inline card.
public enum AIUnavailableReason: Sendable, Equatable {
    case osTooOld
    case deviceNotEligible
    case appleIntelligenceOff
    case modelNotReady
    case disabledInSettings
    case other(String)

    public var title: String {
        switch self {
        case .osTooOld: "On-device AI needs macOS 26"
        case .deviceNotEligible: "This Mac can't run Apple's on-device model"
        case .appleIntelligenceOff: "Apple Intelligence is turned off"
        case .modelNotReady: "The on-device model is still downloading"
        case .disabledInSettings: "AI is turned off in Glink"
        case .other: "On-device AI isn't available"
        }
    }

    public var message: String {
        switch self {
        case .osTooOld: "Glink's AI runs entirely on your Mac using Apple's Foundation Models, which arrived in macOS 26."
        case .deviceNotEligible: "Apple's on-device model needs a Mac with Apple silicon."
        case .appleIntelligenceOff: "Turn on Apple Intelligence in System Settings, then try again."
        case .modelNotReady: "macOS is still downloading the model. This happens once; try again in a few minutes."
        case .disabledInSettings: "Turn AI back on in Glink Settings › AI."
        case .other(let detail): detail
        }
    }

    /// Whether System Settings is where the user fixes it.
    public var opensSystemSettings: Bool { self == .appleIntelligenceOff }
}

public enum AIAvailability: Sendable, Equatable {
    case available
    case unavailable(AIUnavailableReason)

    public var isAvailable: Bool { self == .available }
}

/// The model Glink talks to. Production uses Apple's Foundation Models; tests use a mock.
public protocol OnDeviceModel: Sendable {
    var availability: AIAvailability { get }
    /// Streams the response; every element is the full text generated so far.
    func streamResponse(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error>
}

public enum AIEngineError: Error, Equatable, LocalizedError {
    case unavailable(AIUnavailableReason)
    case emptyInput

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "\(reason.title). \(reason.message)"
        case .emptyInput: "There's no text to work with."
        }
    }
}

public struct AITurnText: Sendable, Equatable {
    public let prompt: String
    public let response: String
    public init(prompt: String, response: String) {
        self.prompt = prompt
        self.response = response
    }
}

/// Availability handling and prompt building for Glink's AI commands. Never sends anything off the Mac:
/// the only thing it talks to is the injected `OnDeviceModel`.
public struct AIEngine: Sendable {
    public static let instructions = """
    You are Glink, an assistant inside a macOS command bar. Answer directly and concisely. \
    Use short paragraphs or brief lists. Never add preambles like "Sure!".
    """

    let model: any OnDeviceModel
    let isEnabled: @Sendable () -> Bool

    public init(model: any OnDeviceModel, isEnabled: @escaping @Sendable () -> Bool = { true }) {
        self.model = model
        self.isEnabled = isEnabled
    }

    /// The setting wins over the model: a disabled feature is unavailable even on a capable Mac.
    public var availability: AIAvailability {
        guard isEnabled() else { return .unavailable(.disabledInSettings) }
        return model.availability
    }

    /// Builds the prompt, including earlier turns so follow-up questions have context.
    public static func prompt(instruction: String?, input: String, history: [AITurnText] = []) -> String {
        var parts: [String] = []
        for turn in history.suffix(4) {
            parts.append("Earlier question: \(turn.prompt)\nYour earlier answer: \(turn.response)")
        }
        if let instruction, !instruction.isEmpty {
            parts.append("\(instruction)\n\n<text>\n\(input)\n</text>")
        } else {
            parts.append(input)
        }
        return parts.joined(separator: "\n\n")
    }

    public func stream(instruction: String?, input: String, history: [AITurnText] = []) -> AsyncThrowingStream<String, Error> {
        if case .unavailable(let reason) = availability {
            return AsyncThrowingStream { $0.finish(throwing: AIEngineError.unavailable(reason)) }
        }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: AIEngineError.emptyInput) }
        }
        return model.streamResponse(instructions: Self.instructions,
                                    prompt: Self.prompt(instruction: instruction, input: input, history: history))
    }
}
