import AVFoundation
import Foundation

/// Plays a queue of synthesized speech buffers.
///
/// Wraps a single `AVAudioPlayerNode`. Buffers are scheduled as they arrive, so
/// playback of chunk *n* overlaps synthesis of chunk *n+1* with no gap between
/// them — the node plays a continuous stream rather than restarting per chunk.
///
/// The engine is started lazily and stopped when the queue drains, so an idle
/// Beagle holds no audio hardware.
@MainActor
public final class SpeechPlayer {

    /// Playback state, for driving the orb and menu bar.
    public enum State: Equatable, Sendable {
        case idle
        case playing
        case paused
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    /// Chunks scheduled but not yet finished playing.
    private var pendingBuffers = 0

    /// Called whenever ``state`` changes.
    public var onStateChange: ((State) -> Void)?

    public private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    public init() {
        // Kokoro emits 24 kHz mono float32. Declaring the format up front means
        // the engine converts once into the hardware rate rather than us
        // resampling by hand.
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioFormat.synthesisSampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            preconditionFailure("24 kHz mono float32 is always a valid format")
        }
        self.format = format

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Queue samples for playback, starting the engine if needed.
    ///
    /// - Parameter samples: Mono float samples at ``AudioFormat/synthesisSampleRate``.
    public func enqueue(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SpeechPlayerError.bufferAllocationFailed
        }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else {
            throw SpeechPlayerError.bufferAllocationFailed
        }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }

        try startEngineIfNeeded()

        pendingBuffers += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // The completion handler fires on an audio thread; hop to the main
            // actor before touching state.
            Task { @MainActor in self?.bufferFinished() }
        }

        if state != .playing {
            player.play()
            state = .playing
        }
    }

    /// Pause without discarding queued audio.
    public func pause() {
        guard state == .playing else { return }
        player.pause()
        state = .paused
    }

    /// Resume after ``pause()``.
    public func resume() {
        guard state == .paused else { return }
        player.play()
        state = .playing
    }

    /// Stop immediately and discard anything queued.
    public func stop() {
        guard state != .idle else { return }
        player.stop()
        pendingBuffers = 0
        teardownEngine()
        state = .idle
    }

    /// Whether audio is queued or playing.
    public var isActive: Bool { state != .idle }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw SpeechPlayerError.engineFailedToStart(underlying: error)
        }
    }

    private func bufferFinished() {
        pendingBuffers = max(0, pendingBuffers - 1)

        // Only the *last* buffer draining means the utterance is over.
        guard pendingBuffers == 0 else { return }

        // Deliberately not conditioned on `state == .playing`. A paused player
        // still reports completions for audio the renderer had already consumed,
        // so gating on `.playing` could leave the queue empty, the engine
        // running, and the state stuck at `.paused` — where `resume()` would
        // play silence forever and `stop()` was the only way out.
        guard state != .idle else { return }
        player.stop()
        teardownEngine()
        state = .idle
    }

    private func teardownEngine() {
        guard engine.isRunning else { return }
        engine.stop()
        Log.tts.debug("Playback engine stopped")
    }
}

/// Errors raised while queueing or starting playback.
public enum SpeechPlayerError: LocalizedError {
    case bufferAllocationFailed
    case engineFailedToStart(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .bufferAllocationFailed:
            return "Could not allocate an audio buffer for playback."
        case .engineFailedToStart(let underlying):
            return "Audio playback could not start: \(underlying.localizedDescription)"
        }
    }
}
