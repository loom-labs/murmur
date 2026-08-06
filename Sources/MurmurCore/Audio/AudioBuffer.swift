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
            append(UnsafeBufferPointer(start: channels[0], count: frameCount))
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
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += channels[channel][frame]
            }
            samples.append(sum * scale)
        }
    }

    /// Remove and return everything captured so far.
    func drain() -> (samples: [Float], overflowed: Bool) {
        lock.lock()
        defer { lock.unlock() }

        let captured = samples
        let didOverflow = overflowed
        samples.removeAll(keepingCapacity: true)
        overflowed = false
        return (captured, didOverflow)
    }

    /// Sample count captured so far, for level metering and UI duration.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }
}
