import HugoCore
import SwiftUI

/// The floating orb: Hugo's entire on-screen footprint.
///
/// 44 points across, which is the smallest target that stays comfortably
/// clickable and matches the platform's minimum hit area. It reads as a status
/// light first and a button second — the hotkeys are the primary interface, and
/// the orb exists so the app is not invisible.
///
/// Each state gets its own motion rather than one generic spinner. The orb is
/// small enough that colour and glyph alone are easy to miss, so the movement
/// carries the meaning: bars that track your voice while listening, a sweep
/// while transcribing, a steady equalizer while speaking.
public struct OrbView: View {

    /// Diameter of the orb in points.
    public static let diameter: CGFloat = 44

    private let activity: ActivityState
    private let inputLevel: () -> Float
    private let isTargeted: Bool
    private let onTap: () -> Void

    @State private var isHovering = false

    /// - Parameter inputLevel: Read on every animation tick rather than passed
    ///   by value. A plain `Float` would be captured when the view is built and
    ///   the meter would sit frozen at that one sample, because SwiftUI has no
    ///   reason to rebuild the orb 60 times a second.
    public init(
        activity: ActivityState,
        inputLevel: @escaping () -> Float = { 0 },
        isTargeted: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.activity = activity
        self.inputLevel = inputLevel
        self.isTargeted = isTargeted
        self.onTap = onTap
    }

    public var body: some View {
        ZStack {
            // Base surface. A material rather than a flat fill so the orb picks
            // up whatever is behind it and reads as glass sitting above the
            // desktop instead of a sticker pasted onto it.
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(tint.opacity(0.55), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)

            if isTargeted {
                Circle()
                    .strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .scaleEffect(1.12)
            }

            // One timeline drives every animated state, so the view redraws only
            // while something is actually happening rather than continuously.
            if activity.isBusy {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    switch activity {
                    case .listening:
                        LevelMeter(level: inputLevel(), time: time, tint: tint)
                    case .transcribing:
                        SweepRing(time: time, tint: tint)
                    case .speaking:
                        LevelMeter(level: nil, time: time, tint: tint)
                    default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: activity.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .scaleEffect(isHovering ? 1.08 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: activity)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onTap)
        .help(helpText)
        .accessibilityLabel(Hugo.appName)
        .accessibilityValue(activity.summary)
        .accessibilityAddTraits(.isButton)
    }

    /// Colour carries the meaning; the glyph confirms it. Red only ever means
    /// recording or failure, so a glance is enough.
    private var tint: Color {
        switch activity {
        case .idle: return .secondary
        case .listening: return .red
        case .transcribing: return .accentColor
        case .speaking: return .green
        case .failed: return .orange
        }
    }

    private var helpText: String {
        switch activity {
        case .idle: return "Click to dictate, or drop text here to hear it"
        case .listening: return "Listening — click to stop"
        case .transcribing: return "Transcribing…"
        case .speaking: return "Speaking — click to stop"
        case .failed(let message): return message
        }
    }
}

/// Five bars that rise and fall.
///
/// When `level` is non-nil the bars track live microphone amplitude, so the orb
/// answers the question a user actually has while dictating: *is it hearing me?*
/// When it is nil the bars run on the clock alone, which is what playback needs
/// since there is no input to follow.
private struct LevelMeter: View {

    let level: Float?
    let time: TimeInterval
    let tint: Color

    /// Per-bar phase offsets, so the bars do not move as one block.
    private static let phases: [Double] = [0.0, 0.9, 1.8, 2.7, 3.6]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(Self.phases.enumerated()), id: \.offset) { index, phase in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: height(index: index, phase: phase))
            }
        }
        .frame(height: 22)
    }

    private func height(index: Int, phase: Double) -> CGFloat {
        let wave = (sin(time * 6.5 + phase) + 1) / 2  // 0...1

        guard let level else {
            // Playback: a steady equalizer, taller in the middle.
            let centreBias = 1.0 - abs(Double(index) - 2) / 3.0
            return 5 + CGFloat(wave * 13 * centreBias)
        }

        // Recording: speech rarely peaks near 1.0, so the level is scaled up to
        // use the full height. A noise floor keeps the bars alive during pauses
        // — a frozen meter reads as a hung app.
        let amplitude = min(1.0, Double(level) * 2.2)
        let floor = 0.14
        return 4 + CGFloat((floor + amplitude * (1 - floor)) * wave * 18)
    }
}

/// A rotating arc, for work with no measurable progress.
private struct SweepRing: View {

    let time: TimeInterval
    let tint: Color

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(time.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360))
    }
}

// Note: no `#Preview` here. That macro is implemented by a compiler plugin
// that ships with Xcode, and Hugo is built with the Command Line Tools
// toolchain in CI — using it would break the build for anyone without a full
// Xcode install. See CONTRIBUTING.md.
