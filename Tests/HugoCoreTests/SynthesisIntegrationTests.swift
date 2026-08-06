import FluidAudio
import Foundation
import Testing

@testable import HugoCore

/// End-to-end synthesis checks against real Kokoro weights.
///
/// Skipped unless `HUGO_INTEGRATION=1`. Run locally with:
///
///     HUGO_INTEGRATION=1 swift test --filter SynthesisIntegrationTests
@Suite(
    "Synthesis integration",
    .enabled(if: ProcessInfo.processInfo.environment["HUGO_INTEGRATION"] == "1"),
    .serialized
)
struct SynthesisIntegrationTests {

    @Test("Synthesized speech transcribes back to the original words")
    func roundTripsThroughRecognition() async throws {
        let phrase = "the quick brown fox jumps over the lazy dog"

        let synthesis = SynthesisService()
        let samples = try await synthesis.synthesizeAll(phrase)
        #expect(samples.count > 0)

        let expectedDuration = Double(samples.count) / AudioFormat.synthesisSampleRate
        #expect(expectedDuration > 1.0, "nine words should take more than a second to say")

        // Kokoro renders at 24 kHz; Parakeet wants 16 kHz. Round-tripping the
        // two models through a resample is the strongest available check that
        // the audio is real speech and not noise or silence.
        let forRecognition = try AudioConverter().resample(
            samples,
            from: AudioFormat.synthesisSampleRate
        )
        let transcript = try await TranscriptionService().transcribe(forRecognition)

        let heard =
            transcript.text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for word in phrase.split(separator: " ") {
            #expect(heard.contains(String(word)), "missing '\(word)' in '\(transcript.text)'")
        }
    }

    @Test("Long text streams as multiple chunks in order")
    func streamsChunksInOrder() async throws {
        // Comfortably past the default 280-character budget, so this exercises
        // the split rather than accidentally fitting in one chunk.
        let text = """
            Hugo runs entirely on your own machine. It uses Parakeet for \
            speech recognition and Kokoro for synthesis. Both models execute \
            on the Apple Neural Engine, which keeps power draw low enough for \
            an always-on utility. Nothing is sent to a server at any point, \
            and no account is required to use any part of it. The first launch \
            downloads the weights once, after which the app works with the \
            network switched off entirely. That is the whole design goal.
            """
        #expect(text.count > TextChunker.defaultMaximumLength)

        let synthesis = SynthesisService()
        var received: [SpeechChunk] = []
        for try await chunk in await synthesis.synthesize(text) {
            received.append(chunk)
        }

        #expect(received.count > 1, "long text should split for streaming playback")
        #expect(received.map(\.index) == Array(0..<received.count), "chunks arrived out of order")
        #expect(received.allSatisfy { !$0.samples.isEmpty })
        #expect(received.last?.isFinal == true)
        #expect(received.allSatisfy { $0.total == received.count })
    }

    @Test("The first chunk arrives well before the whole utterance is rendered")
    func firstChunkArrivesEarly() async throws {
        let text = String(
            repeating: "This sentence exists only to make the passage long enough to measure. ",
            count: 8
        )

        let synthesis = SynthesisService()
        try await synthesis.prepare()  // exclude model load from the measurement

        let started = ContinuousClock.now
        var firstChunkAt: Duration?
        var chunkCount = 0

        for try await _ in await synthesis.synthesize(text) {
            if firstChunkAt == nil { firstChunkAt = started.duration(to: .now) }
            chunkCount += 1
        }
        let total = started.duration(to: .now)

        let first = try #require(firstChunkAt)
        #expect(chunkCount > 1)
        // This is the entire point of chunking: playback can begin after the
        // first chunk rather than after the last.
        #expect(first < total, "first chunk should land before synthesis finishes")
    }

    @Test("Empty text reports nothing to speak rather than silently succeeding")
    func emptyTextThrows() async throws {
        let synthesis = SynthesisService()

        await #expect(throws: SynthesisError.self) {
            try await synthesis.synthesizeAll("   \n  ")
        }
    }
}
