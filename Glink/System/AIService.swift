import Foundation

enum AICommand: String, Hashable, CaseIterable, Identifiable {
    case ask, summarize, rewrite, explain, fixGrammar, makeShorter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask AI"
        case .summarize: "Summarize Selection"
        case .rewrite: "Rewrite Selection"
        case .explain: "Explain Selection"
        case .fixGrammar: "Fix Spelling and Grammar"
        case .makeShorter: "Make Shorter"
        }
    }

    var symbol: String {
        switch self {
        case .ask: "sparkles"
        case .summarize: "text.badge.star"
        case .rewrite: "pencil.line"
        case .explain: "lightbulb"
        case .fixGrammar: "textformat.abc"
        case .makeShorter: "arrow.down.right.and.arrow.up.left"
        }
    }

    var usesSelection: Bool { self != .ask }

    /// Whether the result is meant to replace the selected text (so "Paste" is the primary action).
    var replacesSelection: Bool { [.rewrite, .fixGrammar, .makeShorter].contains(self) }

    var instruction: String {
        switch self {
        case .ask: ""
        case .summarize: "Summarize the following text in a few concise bullet points."
        case .rewrite: "Rewrite the following text so it is clearer and reads well. Keep the meaning, language and tone. Reply with only the rewritten text."
        case .explain: "Explain the following text in simple terms. If it is code, explain what it does."
        case .fixGrammar: "Fix spelling and grammar in the following text. Change nothing else. Reply with only the corrected text."
        case .makeShorter: "Make the following text shorter while keeping its meaning. Reply with only the shortened text."
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

struct AIMessage: Codable, Hashable {
    let role: String   // "user" | "assistant"
    let content: String
}

enum AIError: LocalizedError {
    case missingKey
    case http(Int, String)
    case refusal
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Anthropic API key in Settings › AI."
        case .http(let code, let message): "Request failed (\(code)): \(message)"
        case .refusal: "Claude declined to answer this request."
        case .network(let message): message
        }
    }
}

/// Streams responses from the Anthropic Messages API over raw HTTP (server-sent events).
/// Only text the user explicitly selects or types is sent, and only when they run an AI command.
@MainActor
final class AIService {
    static let shared = AIService()
    static let defaultModel = "claude-opus-5-5"
    static let keychainAccount = "anthropic-api-key"
    static let models: [(id: String, name: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-haiku-5-5", "Claude Haiku 5.5"),
    ]
    static let efforts = ["low", "medium", "high"]

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var apiKey: String? { Keychain.read(Self.keychainAccount) }
    var hasKey: Bool { !(apiKey ?? "").isEmpty }

    let systemPrompt = """
    You are Glink, an assistant inside a macOS command bar. Answer directly and concisely. \
    Use Markdown sparingly (short lists, inline code, code blocks for code). Never add preambles like "Sure!".
    """

    func stream(_ messages: [AIMessage], model: String? = nil) -> AsyncThrowingStream<String, Error> {
        let key = apiKey
        let model = model ?? AppSettings.shared.aiModel
        let effort = AppSettings.shared.aiEffort
        let request = makeRequest(messages: messages, model: model, effort: effort, key: key ?? "", maxTokens: 32_000)

        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let key, !key.isEmpty else {
                    continuation.finish(throwing: AIError.missingKey)
                    return
                }
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if !(200..<300).contains(status) {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        continuation.finish(throwing: AIError.http(status, Self.errorMessage(from: body)))
                        return
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }
                        switch type {
                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "message_delta":
                            if let delta = event["delta"] as? [String: Any], delta["stop_reason"] as? String == "refusal" {
                                continuation.finish(throwing: AIError.refusal)
                                return
                            }
                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                            continuation.finish(throwing: AIError.http(0, message))
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends a tiny request to verify the key and model.
    func testConnection(key: String, model: String) async throws {
        let request = makeRequest(messages: [AIMessage(role: "user", content: "Reply with: ok")], model: model,
                                  effort: "low", key: key, maxTokens: 64, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.http(status, Self.errorMessage(from: String(decoding: data, as: UTF8.self)))
        }
    }

    private func makeRequest(messages: [AIMessage], model: String, effort: String, key: String,
                             maxTokens: Int, stream: Bool = true) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "output_config": ["effort": effort],
        ]
        if stream { body["stream"] = true }
        // Server-side fallback: if a safety classifier declines, the API retries on a recommended model.
        if model == "claude-opus-5-5" || model == "claude-sonnet-5-5" {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func errorMessage(from body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = (json["error"] as? [String: Any])?["message"] as? String {
            return message
        }
        return body.isEmpty ? "No response" : String(body.prefix(200))
    }
}
