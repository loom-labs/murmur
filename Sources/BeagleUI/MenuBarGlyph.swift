import AppKit
import BeagleCore
import SwiftUI

/// The menu bar icon: a beagle head, drawn rather than an SF Symbol.
///
/// Rendered as a **template image**, which is what lets macOS invert it for
/// light and dark menu bars and dim it when the bar is inactive. A full-colour
/// icon would keep the tricolour but look foreign next to every other item in
/// the bar, so the glyph carries the silhouette instead — ears, muzzle, and the
/// notch that reads as a dog even at 16 points.
///
/// State is shown by the ears: up while listening, back while thinking, neutral
/// otherwise. That mirrors the orb, so the two never disagree.
public enum MenuBarGlyph {

    /// Height macOS expects for a menu bar item.
    private static let size = NSSize(width: 20, height: 18)

    /// A beagle head for `activity`, ready to hand to `MenuBarExtra`.
    public static func image(for activity: ActivityState) -> NSImage {
        let earLift = earLift(for: activity)
        let mouthOpen = activity == .speaking

        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: rect, context: context, earLift: earLift, mouthOpen: mouthOpen)
            return true
        }
        // Template: macOS recolours it to match the menu bar rather than
        // drawing our black pixels literally.
        image.isTemplate = true
        return image
    }

    /// Degrees the ears swing out from rest. Negative lifts them.
    private static func earLift(for activity: ActivityState) -> CGFloat {
        switch activity {
        case .listening: return -20
        case .transcribing: return 10
        case .failed: return 14
        default: return 0
        }
    }

    private static func draw(
        in rect: NSRect,
        context: CGContext,
        earLift: CGFloat,
        mouthOpen: Bool
    ) {
        let w = rect.width
        let h = rect.height
        let headW = w * 0.56
        let headH = h * 0.66
        let centre = CGPoint(x: rect.midX, y: rect.midY + h * 0.04)

        context.setFillColor(NSColor.black.cgColor)

        // Ears first, so the head overlaps them.
        let earW = w * 0.24
        let earH = h * 0.62
        for sign in [CGFloat(-1), 1] {
            context.saveGState()
            context.translateBy(x: centre.x + sign * headW * 0.46, y: centre.y + h * 0.02)
            context.rotate(by: sign * (18 + earLift) * .pi / 180)
            context.fillEllipse(in: CGRect(x: -earW / 2, y: -earH / 2, width: earW, height: earH))
            context.restoreGState()
        }

        // Head
        context.fillEllipse(
            in: CGRect(
                x: centre.x - headW / 2,
                y: centre.y - headH / 2,
                width: headW,
                height: headH
            )
        )

        // Muzzle, punched out so the silhouette reads as a snout rather than a
        // blob. Clearing to transparent is what makes the shape legible once
        // macOS fills the template with a single colour.
        context.saveGState()
        context.setBlendMode(.clear)
        let muzzleW = headW * 0.42
        let muzzleH = headH * (mouthOpen ? 0.40 : 0.26)
        context.fillEllipse(
            in: CGRect(
                x: centre.x - muzzleW / 2,
                y: centre.y - headH * 0.46,
                width: muzzleW,
                height: muzzleH
            )
        )
        context.restoreGState()

        // Nose, sitting in the cleared muzzle.
        context.fillEllipse(
            in: CGRect(
                x: centre.x - headW * 0.10,
                y: centre.y - headH * 0.34,
                width: headW * 0.20,
                height: headH * 0.14
            )
        )
    }
}
