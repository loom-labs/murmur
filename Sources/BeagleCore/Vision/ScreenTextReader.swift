import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit
import Vision

/// Errors raised while reading text off the screen.
public enum ScreenTextError: LocalizedError {
    case cancelled
    case captureFailed
    case captureBlank
    case noDisplay
    case noTextFound
    case recognitionFailed(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Screen capture was cancelled."
        case .captureFailed:
            return "Could not capture that part of the screen."
        case .captureBlank:
            return "The capture came back empty — check Screen Recording access for Beagle."
        case .noDisplay:
            return "Could not find the display to capture."
        case .noTextFound:
            return "No readable text in that area."
        case .recognitionFailed(let underlying):
            return "Text recognition failed: \(underlying.localizedDescription)"
        }
    }
}

/// Captures a region of the screen and reads the text in it.
///
/// Region selection delegates to `/usr/sbin/screencapture -i`, the same binary
/// behind ⌘⇧4. Reusing it means the crosshair, the Escape-to-cancel behaviour,
/// the window-snapping, and the Screen Recording permission prompt all match
/// what the user already knows, for none of the code a custom overlay would
/// cost.
///
/// Recognition uses Vision, which is on-device and free — no model download and
/// nothing leaves the machine, consistent with the rest of Beagle.
@MainActor
public enum ScreenTextReader {

    /// Let the user drag out a region, then return the text inside it.
    public static func captureRegionAndRecognize() async throws -> String {
        let image = try await captureRegion()
        return try await recognizeText(in: image)
    }

    /// Let the user drag out a region, then capture exactly that.
    ///
    /// Uses ScreenCaptureKit rather than spawning `/usr/sbin/screencapture`.
    /// That subprocess is attributed to itself for TCC purposes, so the Screen
    /// Recording grant given to Beagle did not apply to it and macOS returned a
    /// blank image — which surfaced to users as "no readable text in that area"
    /// with no hint that a permission was the cause.
    private static func captureRegion() async throws -> CGImage {
        guard let rect = await RegionSelector().selectRegion() else {
            throw ScreenTextError.cancelled
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        // Pick the display the selection actually falls on, so a drag on a
        // second monitor captures that monitor.
        guard let display = display(containing: rect, from: content.displays) else {
            throw ScreenTextError.noDisplay
        }

        // Beagle's own windows are excluded so the dimming overlay and the orb
        // never end up in the captured pixels.
        let filter = SCContentFilter(
            display: display,
            excludingApplications: content.applications.filter {
                $0.bundleIdentifier == Beagle.bundleIdentifier
            },
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = displayRelativeRect(rect, on: display)
        // Capture at backing scale so text on a Retina display keeps the detail
        // recognition depends on.
        let scale =
            NSScreen.screens
            .first { NSPointInRect(CGPoint(x: rect.midX, y: rect.midY), $0.frame) }?
            .backingScaleFactor ?? 2
        configuration.width = Int(configuration.sourceRect.width * scale)
        configuration.height = Int(configuration.sourceRect.height * scale)
        configuration.captureResolution = .best
        configuration.showsCursor = false

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw ScreenTextError.captureFailed
        }

        guard image.width > 0, image.height > 0 else {
            throw ScreenTextError.captureBlank
        }
        return image
    }

    /// The display whose bounds contain the centre of `rect`.
    private static func display(containing rect: CGRect, from displays: [SCDisplay]) -> SCDisplay? {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // `SCDisplay.frame` is top-left origin like CoreGraphics; NSScreen is
        // bottom-left. Match through NSScreen, which is what the selection used.
        let screen = NSScreen.screens.first { NSPointInRect(centre, $0.frame) } ?? NSScreen.main
        guard
            let number = screen?.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID
        else {
            return displays.first
        }
        return displays.first { $0.displayID == number } ?? displays.first
    }

    /// Convert a bottom-left-origin screen rect into the top-left-origin,
    /// display-relative rect `SCStreamConfiguration.sourceRect` expects.
    private static func displayRelativeRect(_ rect: CGRect, on display: SCDisplay) -> CGRect {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                == display.displayID
        }
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)

        return CGRect(
            x: rect.origin.x - frame.origin.x,
            y: frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Recognize text in `image` and return it in reading order.
    ///
    /// `nonisolated` so the Vision pass runs on the cooperative pool: accurate
    /// recognition takes a few hundred milliseconds, which would visibly stall
    /// the orb if it ran on the main actor.
    public static nonisolated func recognizeText(in image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        // Accurate over fast: this runs once on a user-initiated capture, so a
        // few hundred milliseconds is invisible and the quality difference on
        // small on-screen type is not.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ScreenTextError.recognitionFailed(underlying: error)
        }

        let observations = request.results ?? []
        guard !observations.isEmpty else { throw ScreenTextError.noTextFound }

        let text = assemble(observations)
        guard !text.isEmpty else { throw ScreenTextError.noTextFound }
        return text
    }

    /// Order recognized lines the way a person would read them and join them.
    static nonisolated func assemble(_ observations: [VNRecognizedTextObservation]) -> String {
        let lines =
            observations
            .compactMap { observation -> (text: String, top: CGFloat, left: CGFloat)? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                // Vision's origin is bottom-left, so a larger maxY is higher on
                // screen and therefore earlier in reading order.
                return (candidate.string, box.maxY, box.minX)
            }
            .sorted { lhs, rhs in
                // Treat lines within 1% of the frame height as the same row, so
                // side-by-side text reads left to right rather than by a
                // sub-pixel vertical difference.
                if abs(lhs.top - rhs.top) > 0.01 { return lhs.top > rhs.top }
                return lhs.left < rhs.left
            }
            .map(\.text)

        return join(lines)
    }

    /// Join OCR lines into prose.
    ///
    /// Hard-wrapped text is the common case for a screen region, so a line
    /// ending in a hyphen is rejoined without one — otherwise synthesis reads
    /// "trans-" and "cription" as two words.
    static nonisolated func join(_ lines: [String]) -> String {
        var result = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if result.isEmpty {
                result = trimmed
            } else if result.hasSuffix("-") {
                result.removeLast()
                result += trimmed
            } else {
                result += " " + trimmed
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
