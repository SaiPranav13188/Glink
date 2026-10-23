import SwiftUI

/// Placeholder rows with a soft shimmer sweep, shown when results take more than 120 ms.
struct SkeletonList: View {
    let rows: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().frame(width: CGFloat([180, 240, 150, 210, 170][i % 5]), height: 9)
                        Capsule().frame(width: CGFloat([110, 90, 130, 80, 120][i % 5]), height: 7).opacity(0.7)
                    }
                    Spacer()
                    Capsule().frame(width: 60, height: 8).opacity(0.6)
                }
                .padding(.horizontal, 12)
                .frame(height: Theme.Panel.rowHeight)
            }
        }
        .foregroundStyle(Color.primary.opacity(0.08))
        .padding(Theme.Panel.listPadding)
        .shimmer()
        .accessibilityLabel("Loading results")
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                        .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !Motion.isReduced, !Motion.isOff else { return }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

/// Inline explanation for a missing permission. Turns green with a bouncing checkmark once granted.
struct PermissionCard: View {
    static let height: CGFloat = 64
    let feature: String
    private var permissions: PermissionsManager { PermissionsManager.shared }
    @State private var dismissed = false
    @State private var showGranted = false

    var body: some View {
        Group {
            if !dismissed && (!permissions.isAccessibilityTrusted || showGranted) {
                card.transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .onAppear { permissions.beginPolling() }
        .onDisappear { permissions.endPolling() }
        .onChange(of: permissions.isAccessibilityTrusted) { _, trusted in
            guard trusted else { return }
            Motion.animate(Motion.bouncy) { showGranted = true }
            Haptics.level()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                Motion.animate(Motion.smooth) { dismissed = true }
            }
        }
    }

    private var card: some View {
        let granted = permissions.isAccessibilityTrusted
        return HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "lock.shield.fill").accessibilityHidden(true)
                .font(.system(size: 22))
                .foregroundStyle(granted ? Color.green : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: granted)
            VStack(alignment: .leading, spacing: 2) {
                Text(granted ? "Accessibility enabled" : "Allow Accessibility access")
                    .font(.system(size: 13, weight: .semibold))
                Text(granted ? "You're all set." : "Glink needs it to \(feature). It never reads what you type.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open System Settings") { permissions.requestAccessibility() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((granted ? Color.green : Color.accentColor).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder((granted ? Color.green : Color.accentColor).opacity(0.3), lineWidth: 0.5)
        )
        .motion(Motion.smooth, value: granted)
    }
}

/// Friendly centered empty state used by sub-screens.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).accessibilityHidden(true)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: appeared)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared.toggle() }
    }
}
