import BeagleCore
import SwiftUI

/// The beagle's face, drawn at orb size and animated by state.
///
/// The whole point of this over abstract bars is that the states become
/// legible without a legend: ears lift when he is listening to you, the muzzle
/// works when he is talking back, his head tilts while he is thinking. Nothing
/// here needs explaining to a first-time user.
///
/// Drawn with shapes rather than shipped as images so it scales cleanly and the
/// animated parts can move independently.
struct BeagleFace: View {

    let activity: ActivityState
    /// Live microphone level in `0...1`, used to drive the ears while listening.
    let level: Float
    /// Continuously advancing time, from the caller's `TimelineView`.
    let time: TimeInterval

    // Palette taken from the app icon, which is taken from Hugo.
    private let tan = Color(red: 186 / 255, green: 118 / 255, blue: 58 / 255)
    private let tanDark = Color(red: 150 / 255, green: 90 / 255, blue: 42 / 255)
    private let cream = Color(red: 255 / 255, green: 252 / 255, blue: 247 / 255)
    private let ink = Color(red: 48 / 255, green: 34 / 255, blue: 28 / 255)
    private let thread = Color(red: 207 / 255, green: 46 / 255, blue: 46 / 255)

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let head = size * 0.74
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                ears(size: size, head: head)
                headShape(size: size, head: head)
                muzzle(size: size, head: head)
                eyes(size: size, head: head)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(centre)
            .rotationEffect(.degrees(headTilt))
        }
    }

    // MARK: - Animated quantities

    /// How far the ears lift, in degrees.
    ///
    /// Loud speech perks them; silence lets them fall. This is the single most
    /// useful signal in the whole app — it answers "can you hear me?" without a
    /// word of UI.
    private var earLift: Double {
        switch activity {
        case .listening:
            let amplitude = min(1.0, Double(level) * 2.6)
            let flutter = sin(time * 7) * 2.5
            return -22 * amplitude + flutter
        case .speaking:
            return sin(time * 3.4) * 4
        case .transcribing:
            return 5
        default:
            return 0
        }
    }

    /// A slow tilt while thinking; the classic dog head-cock.
    private var headTilt: Double {
        switch activity {
        case .transcribing: return sin(time * 2.2) * 7
        case .listening: return sin(time * 1.6) * 1.5
        default: return 0
        }
    }

    /// How far the mouth opens, in points, while speaking.
    private var mouthOpen: CGFloat {
        guard activity == .speaking else { return 0 }
        // Two frequencies so the rhythm reads as speech rather than a metronome.
        let value = (sin(time * 11) + 1) / 2 * 0.7 + (sin(time * 6.3) + 1) / 2 * 0.3
        return CGFloat(value)
    }

    /// Eyes narrow while transcribing — concentration — and blink otherwise.
    private var eyeOpen: CGFloat {
        if activity == .transcribing { return 0.55 }
        // A blink every ~4 s, lasting ~120 ms.
        let phase = time.truncatingRemainder(dividingBy: 4)
        return phase < 0.12 ? 0.15 : 1.0
    }

    // MARK: - Parts

    private func ears(size: CGFloat, head: CGFloat) -> some View {
        let earW = head * 0.40
        let earH = head * 0.86

        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { sign in
                Ellipse()
                    .fill(tan)
                    .overlay(
                        Ellipse()
                            .fill(tanDark)
                            .frame(width: earW * 0.52, height: earH * 0.66)
                            .offset(y: earH * 0.06)
                    )
                    .frame(width: earW, height: earH)
                    .rotationEffect(.degrees(sign * (17 + earLift)), anchor: .top)
                    .offset(x: sign * head * 0.44, y: head * 0.04)
            }
        }
    }

    private func headShape(size: CGFloat, head: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(tan)
                .frame(width: head, height: head)

            // White blaze down the centre of the face.
            Capsule()
                .fill(cream)
                .frame(width: head * 0.24, height: head * 0.72)
                .offset(y: -head * 0.02)
                .clipShape(Circle().size(width: head, height: head).offset(x: -head / 2, y: -head / 2))
        }
        .compositingGroup()
        .overlay(alignment: .bottom) {
            // The red thread, at the base of the head.
            Capsule()
                .fill(thread)
                .frame(width: head * 0.62, height: max(1.5, head * 0.055))
                .offset(y: head * 0.02)
        }
    }

    private func muzzle(size: CGFloat, head: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(cream)
                .frame(width: head * 0.52, height: head * 0.40)

            // Nose
            Ellipse()
                .fill(ink)
                .frame(width: head * 0.20, height: head * 0.135)
                .offset(y: -head * 0.055)

            // Mouth: opens while speaking, a closed line otherwise.
            Ellipse()
                .fill(ink.opacity(0.85))
                .frame(width: head * 0.17, height: head * 0.03 + mouthOpen * head * 0.13)
                .offset(y: head * 0.085)
        }
        .offset(y: head * 0.20)
    }

    private func eyes(size: CGFloat, head: CGFloat) -> some View {
        let eyeW = head * 0.155
        let eyeH = head * 0.185 * eyeOpen

        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { sign in
                ZStack {
                    Ellipse()
                        .fill(ink)
                        .frame(width: eyeW, height: eyeH)
                    Circle()
                        .fill(.white.opacity(0.95))
                        .frame(width: eyeW * 0.34, height: eyeW * 0.34)
                        .offset(x: eyeW * 0.12, y: -eyeH * 0.20)
                        .opacity(eyeOpen > 0.5 ? 1 : 0)
                }
                .offset(x: sign * head * 0.215, y: -head * 0.075)
            }
        }
        .animation(.easeInOut(duration: 0.08), value: eyeOpen)
    }
}
