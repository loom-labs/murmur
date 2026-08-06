import AVFoundation
import Foundation
import Testing

@testable import HugoCore

@Suite("Audio downmix")
struct AudioDownmixTests {

    /// Build a non-interleaved float buffer whose channels hold `channelValues`.
    private func buffer(channels channelValues: [[Float]]) throws -> AVAudioPCMBuffer {
        let frameCount = try #require(channelValues.first?.count)

        // Above two channels the convenience initializer returns nil: there is
        // no implied layout, so one has to be supplied. Discrete-in-order is the
        // right choice for an audio interface presenting unlabelled inputs.
        let format: AVAudioFormat
        if channelValues.count <= 2 {
            format = try #require(
                AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 48_000,
                    channels: AVAudioChannelCount(channelValues.count),
                    interleaved: false
                )
            )
        } else {
            let layout = try #require(
                AVAudioChannelLayout(
                    layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelValues.count)
                )
            )
            format = try #require(
                AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 48_000,
                    interleaved: false,
                    channelLayout: layout
                )
            )
        }
        let pcm = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        )
        pcm.frameLength = AVAudioFrameCount(frameCount)

        let data = try #require(pcm.floatChannelData)
        for (index, values) in channelValues.enumerated() {
            values.withUnsafeBufferPointer { source in
                data[index].update(from: source.baseAddress!, count: frameCount)
            }
        }
        return pcm
    }

    @Test("A mono buffer passes through unchanged")
    func monoPassthrough() throws {
        let sink = AudioSampleBuffer(capacity: 100)
        sink.appendDownmixed(try buffer(channels: [[0.1, 0.2, 0.3]]))

        let (samples, overflowed) = sink.drain()
        #expect(samples == [0.1, 0.2, 0.3])
        #expect(overflowed == false)
    }

    @Test("Stereo is averaged to mono")
    func stereoAveraged() throws {
        let sink = AudioSampleBuffer(capacity: 100)
        sink.appendDownmixed(try buffer(channels: [[1.0, 0.0, 0.5], [0.0, 1.0, 0.5]]))

        let (samples, _) = sink.drain()
        #expect(samples == [0.5, 0.5, 0.5])
    }

    @Test("Four channels average correctly")
    func multiChannelAveraged() throws {
        // Aggregate devices and audio interfaces routinely present more than two
        // channels, so this is not a hypothetical case.
        let sink = AudioSampleBuffer(capacity: 100)
        sink.appendDownmixed(
            try buffer(channels: [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0], [7.0, 8.0]])
        )

        let (samples, _) = sink.drain()
        #expect(samples == [4.0, 5.0])
    }

    @Test("A multi-channel append respects the capacity ceiling")
    func multiChannelTruncates() throws {
        let sink = AudioSampleBuffer(capacity: 2)
        sink.appendDownmixed(try buffer(channels: [[1.0, 1.0, 1.0], [1.0, 1.0, 1.0]]))

        let (samples, overflowed) = sink.drain()
        #expect(samples == [1.0, 1.0])
        #expect(overflowed, "hitting the ceiling mid-downmix must still be reported")
    }

    @Test("A multi-channel append to a full buffer is dropped")
    func multiChannelDropsWhenFull() throws {
        let sink = AudioSampleBuffer(capacity: 1)
        sink.appendDownmixed(try buffer(channels: [[1.0], [1.0]]))
        sink.appendDownmixed(try buffer(channels: [[2.0], [2.0]]))

        let (samples, overflowed) = sink.drain()
        #expect(samples == [1.0])
        #expect(overflowed)
    }

    @Test("An empty buffer is ignored")
    func emptyBufferIgnored() throws {
        let sink = AudioSampleBuffer(capacity: 100)
        let pcm = try buffer(channels: [[0.5], [0.5]])
        pcm.frameLength = 0
        sink.appendDownmixed(pcm)

        #expect(sink.drain().samples.isEmpty)
    }
}
