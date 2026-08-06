import FluidAudio
import Foundation
import Testing

@testable import BeagleCore

/// End-to-end checks that download real weights and run real inference.
///
/// Skipped unless `BEAGLE_INTEGRATION=1` is set: the first run pulls ~650 MB
/// from HuggingFace and pays ANE compilation, which has no business running on
/// every pull request. Run locally with:
///
///     BEAGLE_INTEGRATION=1 swift test --filter Transcription
@Suite(
    "Transcription integration",
    .enabled(if: ProcessInfo.processInfo.environment["BEAGLE_INTEGRATION"] == "1")
)
struct TranscriptionIntegrationTests {

    /// Synthesize known speech with the system `say` binary.
    ///
    /// Using macOS's own voice rather than a checked-in fixture keeps the repo
    /// small and gives clean, accent-neutral audio to assert against.
    private func speak(_ text: String) throws -> [Float] {
        // WAVE container: `say` rejects the little-endian float format below when
        // asked to write AIFF, which is big-endian by definition.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("beagle-\(UUID().uuidString).wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, "--data-format=LEF32@16000", text]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "say failed to synthesize fixture audio")

        defer { try? FileManager.default.removeItem(at: url) }
        return try AudioConverter().resampleAudioFile(url)
    }

    @Test("Transcribes synthesized speech back to the original words")
    func transcribesKnownPhrase() async throws {
        let phrase = "the quick brown fox jumps over the lazy dog"
        let samples = try speak(phrase)
        #expect(samples.count > 16_000, "fixture should be at least a second long")

        let service = TranscriptionService()
        let transcript = try await service.transcribe(samples)

        let normalized =
            transcript.text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Word-level rather than exact-string: Parakeet punctuates and
        // capitalizes, and asserting on that would make this a formatting test.
        for word in phrase.split(separator: " ") {
            #expect(normalized.contains(String(word)), "missing '\(word)' in '\(transcript.text)'")
        }

        #expect(transcript.confidence > 0)
        #expect(transcript.realtimeFactor > 1, "ANE inference should beat realtime")
    }

    @Test("Rejects audio too short to hold a word")
    func rejectsShortAudio() async throws {
        let service = TranscriptionService()
        let tooShort = [Float](repeating: 0, count: 1_000)  // 62 ms

        await #expect(throws: TranscriptionError.self) {
            try await service.transcribe(tooShort)
        }
    }

    @Test("Preparing twice loads the model once")
    func prepareIsIdempotent() async throws {
        let service = TranscriptionService()

        async let first = service.prepare()
        async let second = service.prepare()
        _ = try await (first, second)

        let phase = await service.phase
        #expect(phase == .ready)
    }
}
