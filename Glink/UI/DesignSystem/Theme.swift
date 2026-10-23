import AppKit
import SwiftUI

enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let panel: CGFloat = 16
        static let row: CGFloat = 8
        static let card: CGFloat = 12
        static let keycap: CGFloat = 4
    }

    enum Panel {
        static let width: CGFloat = 750
        static let maxHeight: CGFloat = 474
        static let searchHeight: CGFloat = 56
        static let footerHeight: CGFloat = 40
        static let rowHeight: CGFloat = 44
        static let sectionHeaderHeight: CGFloat = 28
        static let listPadding: CGFloat = 8
        /// Transparent margin around the panel inside its window, so the shadow and entrance motion aren't clipped.
        static let windowMargin: CGFloat = 60
        static var minHeight: CGFloat { searchHeight + footerHeight + 1 }
    }

    /// Selection fill: accent color at ~18% opacity (stronger with Increase Contrast).
    static func selectionFill(contrast: ColorSchemeContrast) -> Color {
        Color.accentColor.opacity(contrast == .increased ? 0.32 : 0.18)
    }

    static func hoverFill(contrast: ColorSchemeContrast) -> Color {
        Color.primary.opacity(contrast == .increased ? 0.12 : 0.06)
    }

    static func borderOpacity(_ scheme: ColorScheme, contrast: ColorSchemeContrast) -> Double {
        if contrast == .increased { return 0.45 }
        return scheme == .dark ? 0.14 : 0.5
    }

    static func shadowOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.25 : 0.15 }
}

// MARK: - Panel background

/// The panel's material. Liquid Glass on macOS 26, a HUD vibrancy view on 14–15,
/// or an opaque fill when the user picks "Solid" or turns on Reduce Transparency.
struct PanelBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.panel
    var style: WindowStyle = AppSettings.shared.windowStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if style == .solid || reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26, *) {
            // A vibrancy layer under the glass keeps text legible over busy wallpapers.
            VisualEffectBlur(material: .popover, blending: .behindWindow)
                .clipShape(shape)
                .opacity(scheme == .dark ? 0.8 : 0.85)
                .glassEffect(.regular, in: shape)
        } else {
            VisualEffectBlur(material: .hudWindow, blending: .behindWindow)
                .clipShape(shape)
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// 0.5pt inner stroke that catches light like a real glass edge: brighter at the top.
struct GlassEdge: View {
    var cornerRadius: CGFloat = Theme.Radius.panel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let o = Theme.borderOpacity(scheme, contrast: contrast)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color.white.opacity(o * 1.4), Color.white.opacity(o * 0.6)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.5
            )
            .overlay {
                if scheme == .light {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(contrast == .increased ? 0.4 : 0.12), lineWidth: 0.5)
                        .padding(-0.5)
                }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Keycap

/// A small keyboard key, used in the footer, actions panel and onboarding.
struct Keycap: View {
    let text: String
    var prominent = false
    @Environment(\.textScale) private var scale

    var body: some View {
        Text(text)
            .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(prominent ? Color.primary : Color.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
                    .fill(Color.primary.opacity(prominent ? 0.12 : 0.07))
            )
    }
}

struct KeyHintLabel: View {
    let title: String
    let keys: [String]

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { Keycap(text: $0) }
            }
        }
    }
}
