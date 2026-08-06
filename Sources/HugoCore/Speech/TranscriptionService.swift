import FluidAudio
import Foundation

/// Errors surfaced by speech-to-text.
public enum TranscriptionError: LocalizedError {
    case modelsUnavailable(underlying: any Error)
    case notReady
    case audioTooShort

    public var errorDescription: String? {
        switch self {
        case .modelsUnavailable(let underlying):
            return "Speech models could not be loaded: \(underlying.localizedDescription)"
        case .notReady:
            return "Speech models are still loading."
        case .audioTooShort:
            return "That was too short to transcribe."
        }
    }
}

/// The result of transcribing one utterance.
public struct Transcript: Sendable, Equatable {
    /// Recognised text, already trimmed.
    public let text: String
    /// Model confidence in `0...1`.
    public let confidence: Float
    /// Length of the source audio.
    public let audioDuration: TimeInterval
    /// Wall-clock time spent in the model.
    public let processingTime: TimeInterval

    /// Ratio of audio length to processing time. 120 means 120× realtime.
    public var realtimeFactor: Double {
        processingTime > 0 ? audioDuration / processingTime : 0
    }
}

/// Speech-to-text backed by Parakeet TDT running on the Apple Neural Engine.
///
/// An `actor` because model loading and inference must be serialized: the
/// underlying Core ML graphs are stateful across a decode, and a second
/// concurrent `transcribe` would interleave decoder state. Callers get natural
/// queueing for free.
public actor TranscriptionService {

    /// Utterances shorter than this are almost always an accidental hotkey tap.
    /// Below ~0.3 s Parakeet has less than one encoder frame of context and
    /// reliably returns an empty string, so rejecting early gives a better
    /// message than "nothing was said".
    private static let minimumDuration: TimeInterval = 0.3

    private let modelVersion: AsrModelVersion
    private var manager: AsrManager?
    private var loadTask: Task<AsrManager, any Error>?

    /// Observable load progress. Read from the main actor via ``phase``.
    private(set) public var phase: ModelPhase = .idle

    /// Invoked on every ``phase`` change so the UI can react without polling.
    private var phaseObserver: (@Sendable (ModelPhase) -> Void)?

    /// - Parameter modelVersion: `.v3` is multilingual (25 European languages
    ///   plus Japanese); `.v2` is English-only with slightly higher recall and a
    ///   smaller download.
    public init(modelVersion: AsrModelVersion = .v3) {
        self.modelVersion = modelVersion
    }

    public func observePhase(_ observer: @escaping @Sendable (ModelPhase) -> Void) {
        phaseObserver = observer
        observer(phase)
    }

    /// Download and load weights if they are not already resident.
    ///
    /// Safe to call repeatedly and from multiple callers: the first call owns
    /// the work and the rest await the same task.
    @discardableResult
    public func prepare() async throws -> AsrManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.value }

        let task = Task<AsrManager, any Error> { [modelVersion] in
            setPhase(.downloading(fraction: nil))

            let models: AsrModels
            do {
                models = try await AsrModels.downloadAndLoad(
                    version: modelVersion,
                    // int8 encoder: ~2× smaller and measurably faster on the ANE,
                    // with no accuracy difference we can detect on dictation-length
                    // audio.
                    encoderPrecision: .int8,
                    progressHandler: { [weak self] progress in
                        Task { await self?.setPhase(.downloading(fraction: progress.fractionCompleted)) }
                    }
                )
            } catch {
                setPhase(.failed(message: error.localizedDescription))
                throw TranscriptionError.modelsUnavailable(underlying: error)
            }

            setPhase(.loading)
            let manager = AsrManager(config: .default)
            do {
                try await manager.loadModels(models)
            } catch {
                setPhase(.failed(message: error.localizedDescription))
                throw TranscriptionError.modelsUnavailable(underlying: error)
            }

            setPhase(.ready)
            Log.asr.info("Parakeet ready")
            return manager
        }
        loadTask = task

        do {
            let manager = try await task.value
            self.manager = manager
            return manager
        } catch {
            // Clear the failed task so a retry is possible.
            loadTask = nil
            throw error
        }
    }

    /// Transcribe one utterance of 16 kHz mono samples.
    public func transcribe(_ samples: [Float]) async throws -> Transcript {
        let duration = AudioFormat.duration(ofSampleCount: samples.count)
        guard duration >= Self.minimumDuration else {
            throw TranscriptionError.audioTooShort
        }

        let manager = try await prepare()

        // Fresh decoder state per utterance: dictation calls are independent, so
        // carrying state across them would leak the previous sentence's context
        // into the next one.
        var decoderState = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.asr.info(
            "Transcribed \(String(format: "%.1f", duration), privacy: .public)s in \(String(format: "%.2f", result.processingTime), privacy: .public)s"
        )

        return Transcript(
            text: text,
            confidence: result.confidence,
            audioDuration: duration,
            processingTime: result.processingTime
        )
    }

    /// Release Core ML resources. The next ``prepare()`` reloads from cache.
    public func unload() {
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
