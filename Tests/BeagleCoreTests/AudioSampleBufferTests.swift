import Foundation
import Testing

@testable import BeagleCore

@Suite("Audio sample buffer")
struct AudioSampleBufferTests {

    /// Convenience for appending a plain array through the pointer API.
    private func append(_ values: [Float], to buffer: AudioSampleBuffer) {
        values.withUnsafeBufferPointer { buffer.append($0) }
    }

    @Test("Appended samples come back in order")
    func preservesOrder() {
        let buffer = AudioSampleBuffer(capacity: 100)
        append([1, 2, 3], to: buffer)
        append([4, 5], to: buffer)

        let (samples, overflowed) = buffer.drain()
        #expect(samples == [1, 2, 3, 4, 5])
        #expect(overflowed == false)
    }

    @Test("Draining empties the buffer")
    func drainEmpties() {
        let buffer = AudioSampleBuffer(capacity: 100)
        append([1, 2, 3], to: buffer)

        #expect(buffer.drain().samples.count == 3)
        #expect(buffer.drain().samples.isEmpty)
        #expect(buffer.count == 0)
    }

    @Test("Appends past capacity are truncated, not grown into")
    func truncatesAtCapacity() {
        let buffer = AudioSampleBuffer(capacity: 4)
        append([1, 2, 3], to: buffer)
        append([4, 5, 6], to: buffer)

        let (samples, overflowed) = buffer.drain()
        #expect(samples == [1, 2, 3, 4])
        #expect(overflowed, "hitting the ceiling must be reported so the UI can warn")
    }

    @Test("Appends once full are dropped entirely")
    func dropsWhenFull() {
        let buffer = AudioSampleBuffer(capacity: 2)
        append([1, 2], to: buffer)
        append([3, 4], to: buffer)

        let (samples, overflowed) = buffer.drain()
        #expect(samples == [1, 2])
        #expect(overflowed)
    }

    @Test("Overflow flag resets after draining")
    func overflowResets() {
        let buffer = AudioSampleBuffer(capacity: 2)
        append([1, 2, 3], to: buffer)
        #expect(buffer.drain().overflowed)

        append([9], to: buffer)
        #expect(buffer.drain().overflowed == false)
    }

    @Test("Concurrent appends do not lose or corrupt samples")
    func concurrentAppendsAreSafe() async {
        let writers = 8
        let perWriter = 500
        let buffer = AudioSampleBuffer(capacity: writers * perWriter)

        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<writers {
                group.addTask {
                    let chunk = [Float](repeating: Float(writer), count: perWriter)
                    chunk.withUnsafeBufferPointer { buffer.append($0) }
                }
            }
        }

        let (samples, overflowed) = buffer.drain()
        #expect(samples.count == writers * perWriter)
        #expect(overflowed == false)

        // Every writer's samples must all be present, whatever the interleaving.
        for writer in 0..<writers {
            let matching = samples.filter { $0 == Float(writer) }.count
            #expect(matching == perWriter)
        }
    }
}
