import SwiftUI

/// Bottom bar: current context (or a toast) on the left, key hints on the right.
struct FooterBar: View {
    let model: PanelViewModel
    @Environment(\.textScale) private var scale

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if let toast = model.toast {
                    ToastView(toast: toast) { model.dismissToast() }
                        .id(toast.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity.combined(with: .offset(y: -6))))
                } else {
                    context
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let primary = model.currentActions.first {
                Button { model.handleKeyEquivalentPrimary() } label: {
                    KeyHintLabel(title: primary.title, keys: ["↵"])
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .id(primary.title)
            }
            if model.currentActions.count > 1 {
                Divider().frame(height: 14)
                Button { model.toggleActions() } label: {
                    KeyHintLabel(title: "Actions", keys: ["⌘", "K"])
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.Panel.footerHeight)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
        .motion(Motion.snappy, value: model.currentActions.first?.title)
        .motion(Motion.bouncy, value: model.toast?.id)
    }

    private var context: some View {
        HStack(spacing: 7) {
            if let route = model.route {
                ItemIconView(icon: route.icon, size: 16)
                Text(route.title)
            } else {
                ItemIconView(icon: .glink, size: 16)
                Text("Glink")
            }
        }
        .font(Typography.footer(scale))
        .foregroundStyle(.secondary)
    }
}

extension PanelViewModel {
    /// Clicking the "↵" hint behaves like pressing Return.
    func handleKeyEquivalentPrimary() {
        if argumentItem != nil { return submitArgument() }
        if case .ai = route, let action = ai.actions.first { return run(action, for: nil) }
        if let item = selectedItem { activate(item) } else if let action = currentActions.first { run(action, for: nil) }
    }
}

struct ToastView: View {
    let toast: Toast
    var onDismiss: () -> Void
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: 7) {
            icon
            Text(toast.title)
                .font(.system(size: 12, weight: .semibold))
            if let message = toast.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let retry = toast.retry {
                Button(toast.style == .failure && toast.title.contains("Accessibility") ? "Enable" : "Retry") {
                    retry()
                    onDismiss()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
        .onAppear { bounce += 1 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var icon: some View {
        switch toast.style {
        case .success:
            Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: bounce)
        case .failure:
            Image(systemName: "xmark.octagon.fill").accessibilityHidden(true)
                .foregroundStyle(.red)
                .symbolEffect(.bounce, value: bounce)
        case .info:
            Image(systemName: "info.circle.fill").accessibilityHidden(true).foregroundStyle(.blue)
        case .progress:
            ProgressView().controlSize(.mini)
        }
    }
}
