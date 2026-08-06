import AppKit
import Foundation
import Testing
import Vision

@testable import MurmurCore

@Suite("Screen text assembly")
struct ScreenTextJoinTests {

    @Test("Lines join with single spaces")
    func joinsWithSpaces() {
        #expect(ScreenTextReader.join(["Hello", "there", "friend"]) == "Hello there friend")
    }

    @Test("Blank lines are dropped")
    func dropsBlankLines() {
        #expect(ScreenTextReader.join(["Hello", "   ", "", "there"]) == "Hello there")
    }

    @Test("A hyphenated line break is rejoined into one word")
    func rejoinsHyphenation() {
        // Without this the synthesizer says "trans" and "cription" as two words.
        #expect(ScreenTextReader.join(["trans-", "cription"]) == "transcription")
    }

    @Test("Hyphenation rejoin survives surrounding text")
    func rejoinsInContext() {
        let joined = ScreenTextReader.join(["The local trans-", "cription is fast."])
        #expect(joined == "The local transcription is fast.")
    }

    @Test("A trailing hyphen with nothing after it is left alone")
    func trailingHyphenAlone() {
        #expect(ScreenTextReader.join(["wait-"]) == "wait-")
    }

    @Test("Surrounding whitespace is trimmed from each line")
    func trimsLines() {
        #expect(ScreenTextReader.join(["  Hello  ", "  there  "]) == "Hello there")
    }

    @Test("An empty input produces an empty string")
    func emptyInput() {
        #expect(ScreenTextReader.join([]).isEmpty)
        #expect(ScreenTextReader.join(["", "  "]).isEmpty)
    }
}

/// Recognition checks that run Vision against rendered images.
///
/// Skipped unless `MURMUR_INTEGRATION=1`. These pass locally in under a second
/// but **hang indefinitely** on GitHub's headless macOS runners — the first CI
/// run on this branch sat in `VNRecognizeTextRequest` until the job was
/// cancelled. Vision's text recognition wants a real graphics stack, so it is
/// treated like the model-backed suites and kept out of CI.
///
///     MURMUR_INTEGRATION=1 swift test --filter ScreenTextRecognitionTests
@Suite(
    "Screen text recognition",
    .enabled(if: ProcessInfo.processInfo.environment["MURMUR_INTEGRATION"] == "1")
)
struct ScreenTextRecognitionTests {

    /// Render `text` into an image the way it would appear on screen.
    ///
    /// Recognizing rendered text rather than a checked-in screenshot keeps the
    /// repo free of binary fixtures and lets the expected string live next to
    /// the assertion.
    private func image(of text: String, width: Int = 900, height: Int = 220) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48),
            .foregroundColor: NSColor.black,
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(in: CGRect(x: 20, y: 20, width: width - 40, height: height - 40))

        NSGraphicsContext.restoreGraphicsState()
        return try #require(context.makeImage())
    }

    @Test("Recognizes rendered text")
    func recognizesRenderedText() async throws {
        let expected = "Murmur reads the screen"
        let recognized = try await ScreenTextReader.recognizeText(in: image(of: expected))

        // Vision occasionally differs on spacing or casing of a single glyph, so
        // assert on words rather than exact equality.
        let words = recognized.lowercased().split(separator: " ").map(String.init)
        for word in expected.lowercased().split(separator: " ") {
            #expect(words.contains(String(word)), "missing '\(word)' in '\(recognized)'")
        }
    }

    @Test("An image with no text reports nothing found")
    func blankImageFindsNothing() async throws {
        let blank = try image(of: "", width: 400, height: 200)

        await #expect(throws: ScreenTextError.self) {
            try await ScreenTextReader.recognizeText(in: blank)
        }
    }

    @Test("Lines come back in reading order, top to bottom")
    func readingOrder() async throws {
        let recognized = try await ScreenTextReader.recognizeText(
            in: image(of: "First line here\nSecond line here", height: 260)
        )

        let first = try #require(recognized.range(of: "First", options: .caseInsensitive))
        let second = try #require(recognized.range(of: "Second", options: .caseInsensitive))
        #expect(first.lowerBound < second.lowerBound, "got: \(recognized)")
    }
}
