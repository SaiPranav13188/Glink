import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        let w = window ?? makeWindow()
        window = w
        w.appearance = AppSettings.shared.theme.appearance
        NSApp.activate()
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = .clear
        w.contentView = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] in
            AppSettings.shared.hasCompletedOnboarding = true
            self?.close()
            Mascots.celebrate(.onboardingDone)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { PanelController.shared.show() }
        }))
        w.delegate = self
        return w
    }

    func windowWillClose(_ notification: Notification) {
        AppSettings.shared.hasCompletedOnboarding = true
        window = nil   // start fresh next time
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, hotkey, permissions, tryIt
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step: OnboardingStep = .welcome
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(step)
                    .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .frame(width: 640, height: 500)
        .background(PanelBackground(cornerRadius: 0))
        .ignoresSafeArea()
    }

    private var transition: AnyTransition {
        if reduceMotion || Motion.isOff { return .opacity }
        return .asymmetric(insertion: .push(from: forward ? .trailing : .leading),
                           removal: .push(from: forward ? .leading : .trailing))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .hotkey: HotkeyStep()
        case .permissions: PermissionsStep()
        case .tryIt: TryItStep(onFinish: onFinish)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: s == step ? 20 : 7, height: 7)
                }
            }
            .motion(Motion.bouncy, value: step)
            Spacer()
            if step != .welcome {
                Button("Back") { go(-1) }
                    .controlSize(.large)
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            if step != .tryIt {
                Button(step == .welcome ? "Get Started" : (step == .permissions ? "Continue" : "Next")) { go(1) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func go(_ delta: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        Motion.animate(Motion.smooth) { step = next }
    }
}

// MARK: Step 1 — Welcome

private struct WelcomeStep: View {
    @State private var appeared = false
    @State private var glow = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.purple, .blue, .teal, .pink, .purple], center: .center))
                    .frame(width: 170, height: 170)
                    .blur(radius: 40)
                    .opacity(appeared ? 0.55 : 0)
                    .rotationEffect(.degrees(glow ? 360 : 0))
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .rotationEffect(.degrees(appeared ? 0 : -12))
                    .opacity(appeared ? 1 : 0)
            }
            VStack(spacing: 8) {
                Text("Welcome to Glink")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Launch apps, find files, reuse your clipboard, snap windows\nand ask AI — all from one shortcut.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            Spacer()
        }
        .onAppear {
            withAnimation(Motion.resolved(Motion.bouncy)?.delay(0.1)) { appeared = true }
            if !Motion.isReduced {
                withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { glow = true }
            }
        }
    }
}

// MARK: Step 2 — Hotkey with an animated keyboard

private struct HotkeyStep: View {
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Choose your hotkey")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Press it anywhere to open Glink. ⌥ Space works great for most people.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            AnimatedKeyboard(shortcut: shortcut)
                .padding(.vertical, 8)
            KeyboardShortcuts.Recorder(for: .togglePanel) { new in
                Motion.animate(Motion.bouncy) { shortcut = new }
            }
            .controlSize(.large)
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

/// A mini keyboard that lights up the keys of the chosen shortcut and "presses" them in sequence.
struct AnimatedKeyboard: View {
    let shortcut: KeyboardShortcuts.Shortcut?
    @State private var pressed = false

    private var keys: [(label: String, active: Bool, width: CGFloat)] {
        let mods = shortcut?.modifiers ?? []
        let keyLabel: String = {
            guard let s = shortcut else { return "Space" }
            let desc = s.description
            let stripped = desc.trimmingCharacters(in: CharacterSet(charactersIn: "⌃⌥⇧⌘"))
            return stripped.isEmpty ? "Space" : (stripped == "Space" || stripped == " " ? "Space" : stripped)
        }()
        return [
            ("⌃", mods.contains(.control), 46),
            ("⌥", mods.contains(.option), 46),
            ("⌘", mods.contains(.command), 58),
            (keyLabel == "Space" ? "" : "⇧", mods.contains(.shift) && keyLabel == "Space", keyLabel == "Space" ? 0 : 46),
            (keyLabel, true, keyLabel == "Space" ? 220 : 46),
        ].filter { $0.2 > 0 }
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                KeyView(label: key.label, active: key.active, pressed: pressed && key.active, width: key.width)
                    .animation(Motion.resolved(Motion.bouncy)?.delay(Double(index) * 0.05), value: pressed)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
        .task {
            guard !Motion.isReduced, !Motion.isOff else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.1))
                pressed = true
                try? await Task.sleep(for: .seconds(0.35))
                pressed = false
            }
        }
    }
}

private struct KeyView: View {
    let label: String
    let active: Bool
    let pressed: Bool
    let width: CGFloat

    var body: some View {
        Text(label)
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(active ? Color.white : Color.secondary)
            .frame(width: width, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                                 : AnyShapeStyle(Color.primary.opacity(0.08)))
                    .shadow(color: active ? Color.accentColor.opacity(pressed ? 0.6 : 0.3) : .clear, radius: pressed ? 12 : 6, y: pressed ? 1 : 3)
            )
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            .scaleEffect(pressed ? 0.92 : 1)
            .offset(y: pressed ? 2 : 0)
    }
}

// MARK: Step 3 — Permissions

private struct PermissionsStep: View {
    private var permissions: PermissionsManager { PermissionsManager.shared }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("A couple of permissions")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Everything is optional. Features that need a permission will ask again later.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                PermissionRow(
                    symbol: "accessibility", tint: .blue, title: "Accessibility",
                    detail: "Lets Glink snap windows, paste into apps and expand snippets. It never records what you type.",
                    granted: permissions.isAccessibilityTrusted,
                    action: { permissions.requestAccessibility() }
                )
                PermissionRow(
                    symbol: "doc.on.clipboard", tint: .orange, title: "Clipboard history",
                    detail: "Stays on this Mac. Password-manager items are skipped automatically.",
                    granted: true, action: nil
                )
            }
            .frame(maxWidth: 500)
            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear { permissions.beginPolling() }
        .onDisappear { permissions.endPolling() }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let granted: Bool
    let action: (() -> Void)?
    @State private var drawn: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(symbol: symbol, tint: granted ? .green : tint, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                // Checkmark draws itself on, then bounces.
                ZStack {
                    Circle().fill(Color.green).frame(width: 26, height: 26)
                    CheckmarkShape()
                        .trim(from: 0, to: drawn)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 10)
                }
                .transition(.scale.combined(with: .opacity))
                .onAppear { withAnimation(.easeOut(duration: Motion.isOff ? 0 : 0.35).delay(0.1)) { drawn = 1 } }
            } else if let action {
                Button("Enable", action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((granted ? Color.green : Color.primary).opacity(granted ? 0.1 : 0.05))
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder((granted ? Color.green : Color.primary).opacity(0.15)))
        .motion(Motion.bouncy, value: granted)
    }
}

struct CheckmarkShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

// MARK: Step 4 — Try it

private struct TryItStep: View {
    let onFinish: () -> Void
    @State private var opened = false
    @State private var pulse = false

    private var shortcutKeys: [String] {
        guard let s = KeyboardShortcuts.getShortcut(for: .togglePanel) else { return ["⌥", "Space"] }
        var keys: [String] = []
        if s.modifiers.contains(.control) { keys.append("⌃") }
        if s.modifiers.contains(.option) { keys.append("⌥") }
        if s.modifiers.contains(.shift) { keys.append("⇧") }
        if s.modifiers.contains(.command) { keys.append("⌘") }
        let rest = s.description.trimmingCharacters(in: CharacterSet(charactersIn: "⌃⌥⇧⌘"))
        keys.append(rest.isEmpty ? "Space" : rest)
        return keys
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if opened {
                ZStack {
                    Circle().fill(Color.green.opacity(0.15)).frame(width: 110, height: 110)
                        .scaleEffect(pulse ? 1.15 : 1)
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: opened)
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                Text("You're all set!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Glink lives in your menu bar. Press the hotkey any time.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                Button("Finish", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("Try it now")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    ForEach(shortcutKeys, id: \.self) { key in
                        Text(key)
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .frame(minWidth: 56, minHeight: 56)
                            .padding(.horizontal, key.count > 1 ? 18 : 0)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.15)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(pulse ? 0.8 : 0.25), lineWidth: 1.5))
                            .scaleEffect(pulse ? 1.05 : 1)
                    }
                }
                Text("Press it to open Glink. This step completes when the panel appears.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                Button("Skip") { onFinish() }.buttonStyle(.link)
            }
            Spacer()
        }
        .onAppear {
            guard !Motion.isReduced, !Motion.isOff else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidOpen)) { _ in
            Haptics.level()
            Motion.animate(Motion.bouncy) { opened = true }
        }
    }
}
