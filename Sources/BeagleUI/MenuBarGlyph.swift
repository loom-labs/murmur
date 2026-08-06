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
        let headW = w * 0.50
        let headH = h * 0.60
        let centre = CGPoint(x: rect.midX, y: rect.midY + h * 0.02)

        // Line art rather than a silhouette. A filled head at 18 points reads as
        // an anonymous blob; an outline with a couple of solid accents keeps the
        // ears, snout, and eyes legible, and sits better beside the other
        // stroked glyphs in the menu bar.
        let stroke = max(1, w * 0.075)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Ears, outlined, flaring away from the head.
        //
        // The sign of the rotation is what makes them read as ears: swinging
        // the bottoms outward gives the hanging silhouette a beagle has, where
        // a smaller or inverted angle just looks like a rounded head.
        let earW = w * 0.21
        let earH = h * 0.56
        for sign in [CGFloat(-1), 1] {
            context.saveGState()
            context.translateBy(x: centre.x + sign * headW * 0.58, y: centre.y + h * 0.03)
            context.rotate(by: sign * (34 + earLift) * .pi / 180)
            context.strokeEllipse(
                in: CGRect(x: -earW / 2, y: -earH / 2, width: earW, height: earH)
            )
            context.restoreGState()
        }

        // Head.
        context.strokeEllipse(
            in: CGRect(
                x: centre.x - headW / 2,
                y: centre.y - headH / 2,
                width: headW,
                height: headH
            )
        )

        // The only solid fills: two eyes and a nose. Enough to make it a face.
        let eye = max(1.1, w * 0.075)
        for sign in [CGFloat(-1), 1] {
            context.fillEllipse(
                in: CGRect(
                    x: centre.x + sign * headW * 0.24 - eye / 2,
                    y: centre.y + headH * 0.10 - eye / 2,
                    width: eye,
                    height: eye
                )
            )
        }

        let noseW = w * 0.13
        let noseH = h * 0.075
        context.fillEllipse(
            in: CGRect(
                x: centre.x - noseW / 2,
                y: centre.y - headH * 0.30,
                width: noseW,
                height: noseH
            )
        )

        // A short muzzle line, opening while speaking.
        if mouthOpen {
            let jaw = centre.y - headH * 0.30 - noseH
            context.move(to: CGPoint(x: centre.x - w * 0.055, y: jaw))
            context.addLine(to: CGPoint(x: centre.x + w * 0.055, y: jaw))
            context.strokePath()
        }
    }
}
