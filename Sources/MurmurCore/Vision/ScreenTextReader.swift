import AppKit
import Foundation
import Vision

/// Errors raised while reading text off the screen.
public enum ScreenTextError: LocalizedError {
    case cancelled
    case captureFailed
    case noTextFound
    case recognitionFailed(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Screen capture was cancelled."
        case .captureFailed:
            return "Could not capture that part of the screen."
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
/// nothing leaves the machine, consistent with the rest of Murmur.
@MainActor
public enum ScreenTextReader {

    /// Let the user drag out a region, then return the text inside it.
    public static func captureRegionAndRecognize() async throws -> String {
        let image = try await captureRegion()
        return try await recognizeText(in: image)
    }

    /// Run the interactive region picker and return the captured image.
    private static func captureRegion() async throws -> CGImage {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive, -x silent (no shutter sound), -o no window shadow.
        process.arguments = ["-i", "-x", "-o", url.path]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ScreenTextError.captureFailed)
            }
        }

        // screencapture exits 0 and writes nothing when the user presses Escape.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScreenTextError.cancelled
        }

        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ScreenTextError.captureFailed
        }
        return image
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
