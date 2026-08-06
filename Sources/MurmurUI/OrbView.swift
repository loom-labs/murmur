import MurmurCore
import SwiftUI

/// The floating orb: Murmur's entire on-screen footprint.
///
/// 44 points across, which is the smallest target that stays comfortably
/// clickable and matches the platform's minimum hit area. It reads as a status
/// light first and a button second — the hotkeys are the primary interface, and
/// the orb exists so the app is not invisible.
public struct OrbView: View {

    /// Diameter of the orb in points.
    public static let diameter: CGFloat = 44

    private let activity: ActivityState
    private let isTargeted: Bool
    private let onTap: () -> Void

    @State private var pulse = false
    @State private var isHovering = false

    public init(
        activity: ActivityState,
        isTargeted: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.activity = activity
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
                .overlay(
                    Circle()
                        .strokeBorder(tint.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)

            // Activity ring: expands and fades while busy.
            if activity.isBusy {
                Circle()
                    .stroke(tint.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 1.35 : 1.0)
                    .opacity(pulse ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                        value: pulse
                    )
            }

            // Drop target ring, shown while a drag hovers.
            if isTargeted {
                Circle()
                    .strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .scaleEffect(1.12)
            }

            Image(systemName: activity.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .scaleEffect(isHovering ? 1.08 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: activity)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onTap)
        .onAppear { pulse = activity.isBusy }
        .onChange(of: activity.isBusy) { _, busy in pulse = busy }
        .help(helpText)
        .accessibilityLabel("Murmur")
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

// Note: no `#Preview` here. That macro is implemented by a compiler plugin
// that ships with Xcode, and Murmur is built with the Command Line Tools
// toolchain in CI — using it would break the build for anyone without a full
// Xcode install. See CONTRIBUTING.md.
