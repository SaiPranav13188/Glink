import SwiftUI

struct AIResponseView: View {
    let model: PanelViewModel
    private var ai: AIConversationModel { model.ai }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let request = ai.request {
                        header(request)
                    }
                    ForEach(Array(ai.turns.enumerated()), id: \.element.id) { index, turn in
                        turnView(turn, isLast: index == ai.turns.count - 1)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                    if let error = ai.error {
                        errorCard(error)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(18)
            }
            .onChange(of: ai.revealed) { proxy.scrollTo("bottom", anchor: .bottom) }
            .motion(Motion.smooth, value: ai.turns.count)
            .motion(Motion.smooth, value: ai.error)
        }
    }

    private func header(_ request: AIRequest) -> some View {
        HStack(spacing: 8) {
            SymbolTile(symbol: request.command.symbol, tint: .purple, size: 22)
            Text(request.command.title).font(.system(size: 13, weight: .semibold))
            if let source = request.sourceLabel {
                Text(source)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            Spacer()
            Text(AIService.models.first { $0.id == AppSettings.shared.aiModel }?.name ?? AppSettings.shared.aiModel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func turnView(_ turn: AITurn, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.fill").accessibilityHidden(true)
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text(turn.prompt)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").accessibilityHidden(true)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.pulse, isActive: isLast && ai.isStreaming && turn.response.isEmpty)
                    .frame(width: 18)
                MarkdownText(text: turn.response, showsCaret: isLast && ai.isStreaming)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        let missingKey = !ai.hasKey
        return HStack(spacing: 12) {
            Image(systemName: missingKey ? "key.fill" : "exclamationmark.triangle.fill").accessibilityHidden(true)
                .font(.system(size: 18))
                .foregroundStyle(missingKey ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(missingKey ? "Connect your Anthropic account" : "Something went wrong").font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(missingKey ? "Add API Key" : "Retry") {
                if missingKey {
                    PanelController.shared.hide()
                    SettingsWindowController.shared.show(pane: .ai)
                } else {
                    ai.regenerate()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// Renders a streaming Markdown response: inline styles, fenced code blocks, and a blinking caret.
struct MarkdownText: View {
    let text: String
    var showsCaret: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let blocks = Self.split(text)
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let isLast = index == blocks.count - 1
                if block.isCode {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.text + (showsCaret && isLast ? "▍" : ""))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                } else if isLast && showsCaret {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                        (Text(Self.inline(block.text)) + Text("▍").foregroundColor(Color.accentColor.opacity(on ? 1 : 0.15)))
                            .font(.system(size: 13.5))
                            .lineSpacing(3)
                    }
                } else {
                    Text(Self.inline(block.text))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct Block { var text: String; var isCode: Bool }

    static func split(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var inCode = false
        var current: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                blocks.append(Block(text: current.joined(separator: "\n"), isCode: inCode))
                current = []
                inCode.toggle()
            } else {
                current.append(line)
            }
        }
        blocks.append(Block(text: current.joined(separator: "\n"), isCode: inCode))
        return blocks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.isCode }
            .map { Block(text: $0.isCode ? $0.text : $0.text.trimmingCharacters(in: .newlines), isCode: $0.isCode) }
            .ifEmpty([Block(text: "", isCode: false)])
    }

    static func inline(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        // Bullets read nicer as real bullets.
        let bulleted = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return String(line.prefix(line.count - trimmed.count)) + "•  " + trimmed.dropFirst(2) }
            if trimmed.hasPrefix("#") { return "**" + trimmed.drop { $0 == "#" || $0 == " " } + "**" }
            return String(line)
        }.joined(separator: "\n")
        return (try? AttributedString(markdown: bulleted, options: options)) ?? AttributedString(s)
    }
}

extension Array {
    func ifEmpty(_ fallback: [Element]) -> [Element] { isEmpty ? fallback : self }
}
