import SwiftUI

/// Preview of a destructive action: exactly what will change, then Confirm / Cancel.
/// Slides up from the footer like the actions panel; ↵ confirms, Esc cancels.
struct ConfirmSheet: View {
    let request: ConfirmRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: request.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(request.destructive ? Color.orange : Color.accentColor)
                    .symbolEffect(.bounce, value: appeared)
                    .accessibilityHidden(true)
                Text(request.title).font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(request.changes.prefix(6).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                if request.changes.count > 6 {
                    Text("and \(request.changes.count - 6) more").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(request.confirmTitle, role: request.destructive ? .destructive : nil, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(request.destructive ? .red : .accentColor)
            }
            .controlSize(.regular)
        }
        .padding(16)
        .background(PanelBackground(cornerRadius: 12))
        .overlay(GlassEdge(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.title)
    }
}

struct RecentActionsView: View {
    let model: PanelViewModel

    var body: some View {
        if model.sections.isEmpty {
            EmptyStateView(symbol: "arrow.uturn.backward.circle", title: "Nothing to undo yet",
                           message: "Window snaps, trashed files, clipboard changes, snippets and AI rewrites show up here.")
        } else {
            ResultsList(model: model, sections: model.sections)
        }
    }
}
