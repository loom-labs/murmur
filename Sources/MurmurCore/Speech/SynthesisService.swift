import FluidAudio
import Foundation

/// Errors surfaced by text-to-speech.
public enum SynthesisError: LocalizedError {
    case modelsUnavailable(underlying: any Error)
    case nothingToSpeak
    case synthesisFailed(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .modelsUnavailable(let underlying):
            return "Voice models could not be loaded: \(underlying.localizedDescription)"
        case .nothingToSpeak:
            return "There was no text to read."
        case .synthesisFailed(let underlying):
            return "Speech synthesis failed: \(underlying.localizedDescription)"
        }
    }
}

/// One synthesized chunk of speech.
public struct SpeechChunk: Sendable {
    /// Position of this chunk in the utterance, from zero.
    public let index: Int
    /// Total chunks in the utterance.
    public let total: Int
    /// The text this audio speaks, for caption display.
    public let text: String
    /// Mono float samples at ``AudioFormat/synthesisSampleRate``.
    public let samples: [Float]

    /// Playback length in seconds.
    public var duration: TimeInterval {
        Double(samples.count) / AudioFormat.synthesisSampleRate
    }

    /// Whether this is the last chunk of the utterance.
    public var isFinal: Bool { index == total - 1 }
}

/// Text-to-speech backed by Kokoro-82M running on the Apple Neural Engine.
///
/// Synthesis is exposed as an `AsyncThrowingStream` of chunks rather than one
/// buffer: the caller can start playing chunk zero while chunk one is still on
/// the ANE, which is the difference between speech starting in 200 ms and
/// starting after the whole document is rendered.
public actor SynthesisService {

    /// Kokoro's English variant currently ships a single voice.
    public static let defaultVoice = "af_heart"

    private var manager: KokoroAneManager?
    private var loadTask: Task<KokoroAneManager, any Error>?

    private(set) public var phase: ModelPhase = .idle
    private var phaseObserver: (@Sendable (ModelPhase) -> Void)?

    public init() {}

    public func observePhase(_ observer: @escaping @Sendable (ModelPhase) -> Void) {
        phaseObserver = observer
        observer(phase)
    }

    /// Download and load the voice models if they are not already resident.
    @discardableResult
    public func prepare() async throws -> KokoroAneManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.value }

        let task = Task<KokoroAneManager, any Error> {
            // Kokoro reports no download progress, so this stays indeterminate
            // rather than inventing a percentage.
            setPhase(.downloading(fraction: nil))

            let manager = KokoroAneManager(variant: .english, defaultVoice: Self.defaultVoice)
            do {
                setPhase(.loading)
                try await manager.initialize()
            } catch {
                setPhase(.failed(message: error.localizedDescription))
                throw SynthesisError.modelsUnavailable(underlying: error)
            }

            setPhase(.ready)
            Log.tts.info("Kokoro ready")
            return manager
        }
        loadTask = task

        do {
            let manager = try await task.value
            self.manager = manager
            return manager
        } catch {
            loadTask = nil
            throw error
        }
    }

    /// Synthesize `text`, yielding audio chunk by chunk as it is produced.
    ///
    /// - Parameters:
    ///   - text: Prose to speak. Split internally on sentence boundaries.
    ///   - rate: Speech rate multiplier, clamped to the intelligible range.
    /// - Returns: A stream that finishes after the final chunk. Cancelling the
    ///   consuming task stops synthesis at the next chunk boundary.
    public func synthesize(
        _ text: String,
        rate: Float = 1.0
    ) -> AsyncThrowingStream<SpeechChunk, any Error> {
        let chunks = TextChunker.chunk(text)
        let speed = SettingsStore.clampRate(rate)

        return AsyncThrowingStream { continuation in
            let work = Task {
                guard !chunks.isEmpty else {
                    continuation.finish(throwing: SynthesisError.nothingToSpeak)
                    return
                }

                do {
                    let manager = try await self.prepare()

                    for (index, chunkText) in chunks.enumerated() {
                        // Checked here rather than only at the await: a cancelled
                        // read should stop synthesizing, not keep burning ANE
                        // cycles for audio nobody will hear.
                        try Task.checkCancellation()

                        let started = ContinuousClock.now
                        let result = try await manager.synthesizeDetailed(
                            text: chunkText,
                            voice: Self.defaultVoice,
                            speed: speed
                        )
                        let elapsed = started.duration(to: .now)

                        let chunk = SpeechChunk(
                            index: index,
                            total: chunks.count,
                            text: chunkText,
                            samples: result.samples
                        )
                        Log.tts.debug(
                            "Chunk \(index + 1)/\(chunks.count): \(String(format: "%.2f", chunk.duration), privacy: .public)s audio in \(String(describing: elapsed), privacy: .public)"
                        )
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as SynthesisError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: SynthesisError.synthesisFailed(underlying: error))
                }
            }

            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// Synthesize the whole of `text` into one buffer.
    ///
    /// For callers that need a complete waveform — exporting to a file, say —
    /// rather than streaming playback.
    public func synthesizeAll(_ text: String, rate: Float = 1.0) async throws -> [Float] {
        var samples: [Float] = []
        for try await chunk in synthesize(text, rate: rate) {
            samples.append(contentsOf: chunk.samples)
        }
        guard !samples.isEmpty else { throw SynthesisError.nothingToSpeak }
        return samples
    }

    /// Release Core ML resources.
    public func unload() async {
        if let manager { await manager.cleanup() }
        manager = nil
        loadTask = nil
        setPhase(.idle)
    }

    private func setPhase(_ newPhase: ModelPhase) {
        guard phase != newPhase else { return }
        phase = newPhase
        phaseObserver?(newPhase)
    }
}
