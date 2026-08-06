import AVFoundation
import FluidAudio
import Foundation

/// Errors surfaced while capturing microphone audio.
public enum AudioRecorderError: LocalizedError {
    case microphonePermissionDenied
    case engineFailedToStart(underlying: any Error)
    case noAudioCaptured
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Beagle needs microphone access to transcribe speech."
        case .engineFailedToStart(let underlying):
            return "The audio engine could not start: \(underlying.localizedDescription)"
        case .noAudioCaptured:
            return "No audio was captured."
        case .notRecording:
            return "Nothing was being recorded."
        }
    }
}

/// Captures microphone audio and hands back 16 kHz mono samples.
///
/// Design notes:
/// - Samples are held in memory at the hardware rate and resampled **once** on
///   stop. Per-buffer resampling would introduce a filter discontinuity at every
///   tap boundary; a single pass over the whole utterance avoids that and is
///   also cheaper.
/// - The engine is torn down completely on stop rather than left running. An
///   idle `AVAudioEngine` holds the microphone open, which lights the orange
///   recording indicator and is a bad look for an always-on utility.
@MainActor
public final class AudioRecorder {

    /// Ceiling on a single utterance. Five minutes of 48 kHz mono float is
    /// ~57 MB — beyond that the user has almost certainly left dictation on by
    /// accident, so capture stops growing instead of consuming the machine.
    public static let maximumDuration: TimeInterval = 300

    private let engine = AVAudioEngine()
    private let converter = AudioConverter()
    private var buffer: AudioSampleBuffer?
    private var hardwareSampleRate: Double = 48_000

    public private(set) var isRecording = false

    public init() {}

    /// Ask for microphone access, prompting the user on first call.
    ///
    /// - Returns: `true` when capture is permitted.
    public static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Begin capturing from the default input device.
    public func start() throws {
        guard !isRecording else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        hardwareSampleRate = format.sampleRate

        let capacity = Int(hardwareSampleRate * Self.maximumDuration)
        let sampleBuffer = AudioSampleBuffer(capacity: capacity)
        buffer = sampleBuffer

        Self.installTap(on: input, format: format, into: sampleBuffer)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            buffer = nil
            throw AudioRecorderError.engineFailedToStart(underlying: error)
        }

        isRecording = true
        Log.audio.info("Capture started at \(self.hardwareSampleRate, privacy: .public) Hz")
    }

    /// Stop capturing and return the utterance as 16 kHz mono samples.
    @discardableResult
    public func stop() throws -> [Float] {
        // Throwing rather than returning an empty array: a caller that stops
        // without having started has a bug, and silently handing back `[]` makes
        // it indistinguishable from a recording that captured nothing.
        guard isRecording, let buffer else { throw AudioRecorderError.notRecording }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        self.buffer = nil

        let (captured, overflowed) = buffer.drain()
        if overflowed {
            Log.audio.warning("Recording hit the \(Self.maximumDuration, privacy: .public)s ceiling")
        }
        guard !captured.isEmpty else { throw AudioRecorderError.noAudioCaptured }

        let resampled = try converter.resample(captured, from: hardwareSampleRate)
        let seconds = AudioFormat.duration(ofSampleCount: resampled.count)
        Log.audio.info("Captured \(String(format: "%.1f", seconds), privacy: .public)s")
        return resampled
    }

    /// Abandon the current recording without transcribing it.
    public func cancel() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        buffer = nil
        Log.audio.info("Capture cancelled")
    }

    /// Current microphone level in `0...1`, for the recording meter.
    ///
    /// Zero when not recording, so the UI can bind to it unconditionally.
    public var inputLevel: Float {
        buffer?.level ?? 0
    }

    /// Seconds captured so far, for live duration display.
    public var capturedDuration: TimeInterval {
        guard let buffer else { return 0 }
        return Double(buffer.count) / hardwareSampleRate
    }

    /// Install the capture tap.
    ///
    /// This is `nonisolated static` for a reason that is not cosmetic. A closure
    /// created inside a `@MainActor` method inherits that isolation, and under
    /// Swift 6 the compiler emits an executor check at its entry. Core Audio
    /// invokes the tap on a realtime thread, the check fails, and the process
    /// dies with `EXC_BREAKPOINT` on the very first buffer. Building the closure
    /// in a nonisolated context is what keeps it off the main actor.
    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        into sampleBuffer: AudioSampleBuffer
    ) {
        // 4096 frames is ~85 ms at 48 kHz: large enough that the tap overhead is
        // negligible, small enough that stopping feels instant.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { pcmBuffer, _ in
            sampleBuffer.appendDownmixed(pcmBuffer)
        }
    }
}
