import SwiftUI

/// Font tokens. Sizes follow the spec and scale with the "Text size" setting.
enum Typography {
    static func search(_ s: CGFloat) -> Font { .system(size: 22 * s, weight: .regular) }
    static func rowTitle(_ s: CGFloat) -> Font { .system(size: 14 * s, weight: .regular) }
    static func rowSubtitle(_ s: CGFloat) -> Font { .system(size: 12 * s) }
    static func accessory(_ s: CGFloat) -> Font { .system(size: 12 * s) }
    static func sectionHeader(_ s: CGFloat) -> Font { .system(size: 11 * s, weight: .semibold) }
    static func footer(_ s: CGFloat) -> Font { .system(size: 12 * s, weight: .medium) }
    static func calculator(_ s: CGFloat) -> Font { .system(size: 28 * s, weight: .medium, design: .rounded).monospacedDigit() }
    static func body(_ s: CGFloat) -> Font { .system(size: 13 * s) }
    static func mono(_ s: CGFloat) -> Font { .system(size: 12.5 * s, design: .monospaced) }
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Multiplier from Settings › General › Text size.
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// Uppercase, tracked section header ("APPLICATIONS").
struct SectionHeader: View {
    let title: String
    @Environment(\.textScale) private var scale

    var body: some View {
        Text(title.uppercased())
            .font(Typography.sectionHeader(scale))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.bottom, 4)
            .frame(height: Theme.Panel.sectionHeaderHeight, alignment: .bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }
}
