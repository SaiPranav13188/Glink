import SwiftUI

struct SearchBar: View {
    @Bindable var model: PanelViewModel
    @FocusState private var focused: Bool
    @Environment(\.textScale) private var scale

    var body: some View {
        HStack(spacing: 12) {
            leading
            if let item = model.argumentItem {
                ArgumentChip(item: item)
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
            TextField("", text: $model.query, prompt: Text(model.placeholder).foregroundStyle(.tertiary))
                .textFieldStyle(.plain)
                .font(Typography.search(scale))
                .focused($focused)
                .disableAutocorrection(true)
                .accessibilityLabel("Search")
                .accessibilityIdentifier("searchField")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: Theme.Panel.searchHeight)
        .motion(Motion.snappy, value: model.query.isEmpty)
        .motion(Motion.snappy, value: model.argumentItem?.id)
        .motion(Motion.snappy, value: model.route)
        .motion(Motion.gentle, value: model.isLoading)
        // Short horizontal shake on invalid input.
        .keyframeAnimator(initialValue: 0.0, trigger: model.shakeTrigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(8, duration: 0.06)
                SpringKeyframe(-6, duration: 0.06)
                SpringKeyframe(3, duration: 0.06)
                SpringKeyframe(0, duration: 0.08)
            }
        }
        .onAppear { focused = true }
        .onChange(of: model.openCount) { focused = model.focus == .search }
        .onChange(of: model.focus) { focused = model.focus == .search }
        .onChange(of: model.route) { focused = true }
    }

    @ViewBuilder
    private var leading: some View {
        if model.route != nil {
            Button { model.pop() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Back (Esc)")
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .accessibilityLabel("Back")
        } else {
            // Magnifying glass gives way to a spinner while files are still streaming in. The spinner
            // is its own view so its endless rotation stops the moment loading ends (idle CPU stays ~0%).
            ZStack {
                if model.isLoading {
                    LoadingGlyph().transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 22)
                .accessibilityHidden(true)
        }
    }
}

private struct ArgumentChip: View {
    let item: SearchItem

    var body: some View {
        HStack(spacing: 6) {
            ItemIconView(icon: item.icon, size: 16)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5))
        .fixedSize()
    }
}

/// A dotted ring that spins while it's on screen.
private struct LoadingGlyph: View {
    @State private var spinning = false

    var body: some View {
        Image(systemName: "circle.dotted").accessibilityHidden(true)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                guard !Motion.isReduced, !Motion.isOff else { return }
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
            }
    }
}
