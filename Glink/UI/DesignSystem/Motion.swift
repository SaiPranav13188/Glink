import AppKit
import SwiftUI

/// Every animation in Glink comes from here so motion stays consistent and can be dialed down globally.
enum Motion {
    // Springs feel physical; prefer them over easing curves.
    static let snappy = Animation.spring(response: 0.24, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.90)
    static let bouncy = Animation.spring(response: 0.40, dampingFraction: 0.70)
    static let gentle = Animation.easeOut(duration: 0.18)

    // Panel
    static let panelIn = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let panelOut = Animation.easeIn(duration: 0.12)
    static let panelOutDuration: TimeInterval = 0.12

    // Stagger delay between list rows on first appearance
    static let staggerStep: Double = 0.018
    static let staggerMaxRows = 8

    static let reducedFade = Animation.easeInOut(duration: 0.1)

    /// True when the user asked for less motion, either in macOS or in Glink's own setting.
    @MainActor static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || AppSettings.shared.animationLevel == .reduced
    }

    @MainActor static var isOff: Bool { AppSettings.shared.animationLevel == .off }

    /// Resolves a token against Reduce Motion and the "Animation level" setting.
    @MainActor static func resolved(_ animation: Animation) -> Animation? {
        if isOff { return nil }
        if isReduced { return reducedFade }
        return animation
    }

    /// `withAnimation` that honors the user's motion preferences.
    @MainActor @discardableResult
    static func animate<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(resolved(animation), body)
    }

    /// Insert/remove transition for rows: fade + 4pt vertical move, or a plain fade when motion is reduced.
    @MainActor static var rowTransition: AnyTransition {
        isReduced || isOff ? .opacity : .opacity.combined(with: .offset(y: 4))
    }
}

/// Applies an animation only when motion is allowed; falls back to a short cross-fade under Reduce Motion.
struct MotionAware<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        let level = AppSettings.shared.animationLevel
        let resolved: Animation? = level == .off ? nil : (reduceMotion || level == .reduced ? Motion.reducedFade : animation)
        content.animation(resolved, value: value)
    }
}

extension View {
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAware(animation: animation, value: value))
    }
}

/// Plays a light trackpad "tick". Only Force Touch trackpads produce feedback; elsewhere it's a no-op.
enum Haptics {
    @MainActor static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    @MainActor static func level() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
