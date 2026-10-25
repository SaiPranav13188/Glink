import AppKit
import Observation
import SwiftUI

/// Playful moments: now and then a kitten, a puppy or one of their (trending) friends peeks out of
/// the panel to celebrate. They never take clicks or keystrokes, stay away under Reduce Motion or
/// "Animation level: Off", and can be switched off in Settings › Appearance.
enum MascotMoment: Equatable {
    case copied, aiAnswer, securityAllClear, securityAtRisk, undo, windowSnapped
    case milestone(Int), goodMorning, onboardingDone, emptyClipboard

    /// How often this moment gets a visitor. "Sometimes", not every time.
    var chance: Double {
        switch self {
        case .copied: 0.3
        case .aiAnswer: 0.35
        case .windowSnapped: 0.25
        case .undo: 0.5
        case .emptyClipboard: 0.5
        case .goodMorning: 0.6
        case .securityAllClear, .securityAtRisk, .milestone, .onboardingDone: 1
        }
    }

    var confetti: Bool {
        switch self {
        case .securityAllClear, .milestone, .onboardingDone: true
        default: false
        }
    }
}

struct Mascot: Equatable {
    let emoji: String
    let name: String
    /// Lines in the mascot's own voice.
    let voice: [String]

    static let kitten = Mascot(emoji: "🐱", name: "Kitten", voice: ["Purr-fect!", "Meow-velous!", "Nailed it, human."])
    static let puppy = Mascot(emoji: "🐶", name: "Puppy", voice: ["Woof! Good job!", "Fetched it!", "Best human ever!"])
    // Trending friends.
    static let capybara = Mascot(emoji: "🦫", name: "Capybara", voice: ["Ok I pull up.", "Chill. It's done.", "Calm vibes only."])
    static let otter = Mascot(emoji: "🦦", name: "Otter", voice: ["Otterly done!", "Holding paws with your files."])
    static let duck = Mascot(emoji: "🦆", name: "Rubber duck", voice: ["Quack! Explained it to me?", "Debugged by duck."])
    static let frog = Mascot(emoji: "🐸", name: "Frog", voice: ["Hop hop, done!", "Ribbit-ing work."])
    static let hamster = Mascot(emoji: "🐹", name: "Hamster", voice: ["Wheel spun!", "Snack break earned."])
    static let panda = Mascot(emoji: "🐼", name: "Panda", voice: ["Bamboo-tiful!", "Big panda energy."])

    static let everyday: [Mascot] = [kitten, puppy, kitten, puppy, capybara, otter, duck, frog, hamster, panda]

    /// Seasonal guests join the cast around their dates.
    static func seasonal(on date: Date = Date()) -> [Mascot] {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        switch (c.month ?? 0, c.day ?? 0) {
        case (10, 15...31), (11, 1):
            return [Mascot(emoji: "👻", name: "Ghost", voice: ["Boo! It's done.", "Spooky fast."]),
                    Mascot(emoji: "🎃", name: "Pumpkin", voice: ["Gourd job!", "Happy Halloween!"]),
                    Mascot(emoji: "🐈‍⬛", name: "Black cat", voice: ["Lucky you!", "Hiss-tory made."]),
                    Mascot(emoji: "🦇", name: "Bat", voice: ["Fang-tastic!"])]
        case (11, 2...12):
            return [Mascot(emoji: "🪔", name: "Diya", voice: ["Happy Diwali! ✨", "Lighting up your day."])]
        case (12, _):
            return [Mascot(emoji: "⛄️", name: "Snowman", voice: ["Cool, cool, cool."]),
                    Mascot(emoji: "🦌", name: "Reindeer", voice: ["Sleigh-ed it!"])]
        case (2, 10...14):
            return [Mascot(emoji: "💌", name: "Love letter", voice: ["Glink loves you back."])]
        default:
            return []
        }
    }
}

struct MascotAppearance: Identifiable, Equatable {
    enum Style { case peek, walk }
    let id = UUID()
    let mascot: Mascot
    let line: String
    let style: Style
    let confetti: Bool
    let hearts: Bool
}

@MainActor @Observable
final class Mascots {
    static let shared = Mascots()

    private(set) var current: MascotAppearance?
    @ObservationIgnored private var lastShown = Date.distantPast
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored var random: () -> Double = { Double.random(in: 0..<1) }

    static var isAllowed: Bool {
        UserDefaults.standard.object(forKey: "playfulMascots") as? Bool ?? true
            && !Motion.isOff
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func celebrate(_ moment: MascotMoment) { shared.celebrate(moment) }

    func celebrate(_ moment: MascotMoment) {
        guard Self.isAllowed else { return }
        let important = moment.chance >= 1
        // A cooldown keeps it charming instead of noisy; important moments always get through.
        guard important || Date().timeIntervalSince(lastShown) > 25, random() < moment.chance else { return }

        let seasonal = Mascot.seasonal()
        let cast = seasonal.isEmpty || random() < 0.5 ? Mascot.everyday : seasonal
        var mascot = cast[Int(random() * Double(cast.count)) % cast.count]
        var line = mascot.voice[Int(random() * Double(mascot.voice.count)) % mascot.voice.count]

        switch moment {
        case .securityAllClear:
            mascot = .puppy
            line = "Woof! All clear."
        case .securityAtRisk:
            mascot = Mascot(emoji: "🙀", name: "Worried kitten", voice: [])
            line = "Yikes, check these!"
        case .milestone(let n):
            line = "\(n) commands! 🎉"
        case .goodMorning:
            mascot = random() < 0.5 ? .kitten : .puppy
            line = "Good morning! ☀️"
        case .onboardingDone:
            line = "Welcome to Glink!"
        case .emptyClipboard:
            mascot = .kitten
            line = "Nothing here yet. Copy something!"
        case .undo:
            line = "Phew! Undone."
        default:
            break
        }

        let style: MascotAppearance.Style = moment.confetti || random() < 0.3 ? .walk : .peek
        current = MascotAppearance(mascot: mascot, line: line, style: style, confetti: moment.confetti,
                                   hearts: mascot == .kitten || mascot.emoji == "💌")
        lastShown = Date()
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(style == .walk ? 2.6 : 2.0))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// Counts actions and celebrates round numbers.
    func countAction() {
        let key = "glinkActionCount"
        let n = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(n, forKey: key)
        if [10, 50, 100, 250, 500, 1000].contains(n) { celebrate(.milestone(n)) }
    }

    /// Once a day, the first open before noon gets a greeting.
    func greetIfMorning() {
        let key = "lastMorningGreeting"
        let today = Calendar.current.startOfDay(for: Date())
        guard Calendar.current.component(.hour, from: Date()) < 12,
              (UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast) < today else { return }
        UserDefaults.standard.set(today, forKey: key)
        celebrate(.goodMorning)
    }
}

// MARK: - Views

/// Drop this over a container's bottom edge; it renders whatever mascot is visiting.
struct MascotStage: View {
    private var mascots: Mascots { Mascots.shared }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let appearance = mascots.current {
                if appearance.confetti {
                    ConfettiBurst().id("confetti-\(appearance.id)")
                }
                MascotView(appearance: appearance)
                    .id(appearance.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.2), value: mascots.current?.id)
    }
}

private struct MascotView: View {
    let appearance: MascotAppearance

    struct Pose {
        var x: CGFloat = 0
        var y: CGFloat = 70
        var rotation: Double = 0
        var scale: CGFloat = 1
        var bubble: CGFloat = 0
    }

    var body: some View {
        GeometryReader { geo in
            if appearance.style == .walk {
                walk(width: geo.size.width)
            } else {
                peek
            }
        }
        .clipped()
    }

    private func figure(_ pose: Pose) -> some View {
        ZStack(alignment: .topLeading) {
            if appearance.hearts { FloatingHearts().offset(x: 6, y: -20) }
            Text(appearance.mascot.emoji)
                .font(.system(size: 34))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
                .scaleEffect(pose.scale, anchor: .bottom)
            SpeechBubble(text: appearance.line)
                .scaleEffect(pose.bubble, anchor: .bottomLeading)
                .opacity(Double(pose.bubble))
                .offset(x: 30, y: -28)
        }
    }

    /// Walks across the bottom edge with little hops and a waddle.
    private func walk(width: CGFloat) -> some View {
        KeyframeAnimator(initialValue: Pose(x: -40), repeating: false) { pose in
            figure(pose)
                .offset(x: pose.x, y: pose.y)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                LinearKeyframe(width * 0.55, duration: 2.0)
                CubicKeyframe(width + 60, duration: 0.6)
            }
            KeyframeTrack(\.y) {
                SpringKeyframe(-6, duration: 0.3, spring: .bouncy)
                CubicKeyframe(-14, duration: 0.17); CubicKeyframe(-6, duration: 0.17)
                CubicKeyframe(-14, duration: 0.17); CubicKeyframe(-6, duration: 0.17)
                CubicKeyframe(-14, duration: 0.17); CubicKeyframe(-6, duration: 0.17)
                CubicKeyframe(-14, duration: 0.17); CubicKeyframe(-6, duration: 0.17)
                CubicKeyframe(-14, duration: 0.17); CubicKeyframe(-6, duration: 0.17)
                CubicKeyframe(-6, duration: 0.6)
            }
            KeyframeTrack(\.rotation) {
                CubicKeyframe(-6, duration: 0.17); CubicKeyframe(6, duration: 0.17)
                CubicKeyframe(-6, duration: 0.17); CubicKeyframe(6, duration: 0.17)
                CubicKeyframe(-6, duration: 0.17); CubicKeyframe(6, duration: 0.17)
                CubicKeyframe(-6, duration: 0.17); CubicKeyframe(6, duration: 0.17)
                CubicKeyframe(-6, duration: 0.17); CubicKeyframe(6, duration: 0.17)
                CubicKeyframe(0, duration: 0.2)
            }
            KeyframeTrack(\.bubble) {
                CubicKeyframe(0, duration: 0.5)
                SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                CubicKeyframe(1, duration: 1.1)
                CubicKeyframe(0, duration: 0.2)
            }
        }
    }

    /// Pops up from the edge, wiggles hello, says something, ducks back down.
    private var peek: some View {
        KeyframeAnimator(initialValue: Pose(), repeating: false) { pose in
            figure(pose)
                .offset(y: pose.y)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 140)
        } keyframes: { _ in
            KeyframeTrack(\.y) {
                SpringKeyframe(-8, duration: 0.45, spring: .bouncy)
                CubicKeyframe(-8, duration: 1.15)
                CubicKeyframe(70, duration: 0.35)
            }
            KeyframeTrack(\.rotation) {
                CubicKeyframe(0, duration: 0.45)
                CubicKeyframe(-12, duration: 0.12)
                CubicKeyframe(10, duration: 0.12)
                CubicKeyframe(-6, duration: 0.12)
                CubicKeyframe(0, duration: 0.12)
            }
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.12, duration: 0.3, spring: .bouncy)
                SpringKeyframe(1, duration: 0.3)
            }
            KeyframeTrack(\.bubble) {
                CubicKeyframe(0, duration: 0.4)
                SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                CubicKeyframe(1, duration: 0.8)
                CubicKeyframe(0, duration: 0.2)
            }
        }
    }
}

private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(.background).shadow(color: .black.opacity(0.2), radius: 6, y: 2))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            .fixedSize()
    }
}

/// A few hearts drift up and fade (the kitten's favorite).
private struct FloatingHearts: View {
    @State private var up = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Text("💗")
                    .font(.system(size: 11))
                    .offset(x: CGFloat(i * 9 - 6), y: up ? -34 - CGFloat(i * 8) : 0)
                    .opacity(up ? 0 : 1)
                    .animation(.easeOut(duration: 1.3).delay(0.4 + Double(i) * 0.15), value: up)
            }
        }
        .onAppear { up = true }
    }
}

/// A short burst of confetti, drawn with Canvas from a timeline (no per-particle views).
struct ConfettiBurst: View {
    private struct Particle {
        let angle: Double, speed: Double, spin: Double, size: Double, color: Color, isEmoji: Bool
    }

    private let start = Date()
    private let particles: [Particle] = (0..<36).map { i in
        let colors: [Color] = [.pink, .orange, .yellow, .green, .blue, .purple, .mint]
        return Particle(angle: Double.random(in: -.pi * 0.95 ... -.pi * 0.05), speed: Double.random(in: 180...380),
                        spin: Double.random(in: -8...8), size: Double.random(in: 5...9),
                        color: colors[i % colors.count], isEmoji: i % 9 == 0)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard t < 1.6 else { return }
                let origin = CGPoint(x: size.width * 0.5, y: size.height - 10)
                for p in particles {
                    let x = origin.x + cos(p.angle) * p.speed * t
                    let y = origin.y + sin(p.angle) * p.speed * t + 380 * t * t   // gravity
                    let alpha = max(0, 1 - t / 1.6)
                    if p.isEmoji {
                        ctx.opacity = alpha
                        ctx.draw(Text("✨").font(.system(size: 14)), at: CGPoint(x: x, y: y))
                    } else {
                        var c = ctx
                        c.opacity = alpha
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(p.spin * t))
                        c.fill(Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2),
                                    cornerRadius: 1.5), with: .color(p.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
