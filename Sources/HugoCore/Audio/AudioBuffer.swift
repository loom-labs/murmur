import AVFoundation
import Foundation

/// A lock-guarded, monotonically growing buffer of mono float samples.
///
/// The producer is Core Audio's realtime render thread, which must never block
/// on an actor hop or allocate unpredictably. A plain `NSLock` around an
/// `Array` is the pragmatic choice: appends amortize to a memcpy, and the only
/// contention is the single reader that drains the buffer once recording stops.
final class AudioSampleBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var samples: [Float] = []
    private let capacity: Int

    /// Number of samples that have been dropped because ``capacity`` was hit.
    private var overflowed = false

    /// Smoothed peak amplitude of recent audio, in `0...1`.
    ///
    /// Kept here rather than computed by the UI because this is the only place
    /// that sees every sample. The decay is applied per append so the meter
    /// falls back to zero during silence instead of latching at the loudest
    /// moment of the session.
    private var peak: Float = 0

    /// - Parameter capacity: Hard ceiling on retained samples. Appends past this
    ///   point are discarded rather than growing without bound, so a forgotten
    ///   recording cannot exhaust memory.
    init(capacity: Int) {
        self.capacity = capacity
        samples.reserveCapacity(min(capacity, 16_000 * 30))
    }

    /// Append samples from the audio thread. Safe to call at realtime priority.
    func append(_ newSamples: UnsafeBufferPointer<Float>) {
        lock.lock()
        defer { lock.unlock() }

        guard samples.count < capacity else {
            overflowed = true
            return
        }
        let room = capacity - samples.count
        if newSamples.count <= room {
            samples.append(contentsOf: newSamples)
        } else {
            samples.append(contentsOf: newSamples[0..<room])
            overflowed = true
        }
    }

    /// Downmix a captured buffer to mono and append it, allocating nothing.
    ///
    /// Called on Core Audio's realtime render thread. An earlier version built a
    /// temporary `[Float]` per callback to hold the mono mix, which put a heap
    /// allocation in the realtime path and risked timing spikes on
    /// multi-channel interfaces. Averaging straight into the reserved storage
    /// avoids that entirely.
    func appendDownmixed(_ pcmBuffer: AVAudioPCMBuffer) {
        guard let channels = pcmBuffer.floatChannelData else { return }
        let frameCount = Int(pcmBuffer.frameLength)
        guard frameCount > 0 else { return }

        let channelCount = Int(pcmBuffer.format.channelCount)
        if channelCount == 1 {
            let source = UnsafeBufferPointer(start: channels[0], count: frameCount)
            var magnitude: Float = 0
            for sample in source { magnitude = max(magnitude, abs(sample)) }
            append(source)
            lock.lock()
            updatePeak(with: magnitude)
            lock.unlock()
            return
        }

        // Most Macs deliver mono from the built-in mic, but external interfaces
        // and aggregate devices are routinely multi-channel.
        lock.lock()
        defer { lock.unlock() }

        let room = capacity - samples.count
        guard room > 0 else {
            overflowed = true
            return
        }
        let frames = min(frameCount, room)
        if frames < frameCount { overflowed = true }

        let scale = 1.0 / Float(channelCount)
        var magnitude: Float = 0
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += channels[channel][frame]
            }
            let mono = sum * scale
            magnitude = max(magnitude, abs(mono))
            samples.append(mono)
        }
        updatePeak(with: magnitude)
    }

    /// Remove and return everything captured so far.
    func drain() -> (samples: [Float], overflowed: Bool) {
        lock.lock()
        defer { lock.unlock() }

        let captured = samples
        let didOverflow = overflowed
        samples.removeAll(keepingCapacity: true)
        overflowed = false
        peak = 0
        return (captured, didOverflow)
    }

    /// Sample count captured so far, for UI duration.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    /// Current smoothed input level in `0...1`, for the recording meter.
    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    /// Fold `magnitude` into the smoothed peak.
    ///
    /// Attack is immediate and release is gradual: a meter that tracks decay as
    /// fast as it tracks onset reads as flicker rather than as speech.
    private func updatePeak(with magnitude: Float) {
        let decayed = peak * 0.82
        peak = min(1, max(decayed, magnitude))
    }
}
