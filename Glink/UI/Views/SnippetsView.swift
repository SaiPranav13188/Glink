import GlinkCore
import SwiftUI

struct SnippetsView: View {
    let model: PanelViewModel

    var body: some View {
        let sections = model.sections
        if sections.isEmpty {
            EmptyStateView(symbol: "text.quote", title: model.query.isEmpty ? "No snippets yet" : "No matching snippets",
                           message: "Create snippets in Settings › Snippets. Type a keyword like ;date anywhere to expand it.")
        } else {
            HStack(spacing: 0) {
                ResultsList(model: model, sections: sections)
                    .frame(width: 300)
                Divider()
                if let snippet = model.snippets.snippet(for: model.selectedItem) {
                    SnippetPreview(snippet: snippet)
                        .id(snippet.id)
                        .transition(.opacity)
                }
            }
            .motion(Motion.gentle, value: model.selectedID)
        }
    }
}

struct SnippetPreview: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(snippet.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Keycap(text: snippet.keyword, prominent: true)
            }
            ScrollView {
                Text(SnippetExpander.expand(snippet.text).text)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
            HStack {
                Text("Used \(snippet.useCount) time\(snippet.useCount == 1 ? "" : "s")")
                Spacer()
                Text("Type \(snippet.keyword) anywhere to expand")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
