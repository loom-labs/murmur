import AVFoundation
import Foundation
import Testing

@testable import BeagleCore

/// Exercises the real `AVAudioEngine` capture path.
///
/// Skipped unless `BEAGLE_INTEGRATION=1`, because it opens the default input
/// device and therefore needs a granted microphone permission. Run with:
///
///     BEAGLE_INTEGRATION=1 swift test --filter AudioRecorderIntegrationTests
@Suite(
    "Audio recorder integration",
    .enabled(if: ProcessInfo.processInfo.environment["BEAGLE_INTEGRATION"] == "1"),
    .serialized
)
@MainActor
struct AudioRecorderIntegrationTests {

    @Test("Capturing from the real device delivers samples")
    func capturesFromDevice() async throws {
        guard await AudioRecorder.requestPermission() else {
            Issue.record("Microphone permission is not granted; cannot run this test.")
            return
        }

        let recorder = AudioRecorder()
        try recorder.start()
        #expect(recorder.isRecording)

        // Long enough for several tap callbacks at ~85 ms per buffer.
        //
        // Regression guard: the tap closure used to inherit `@MainActor` from
        // `start()`, so Swift 6 emitted an executor check that trapped on Core
        // Audio's realtime thread. This test crashed the whole process with
        // EXC_BREAKPOINT before the fix — reaching the assertions at all is the
        // substance of what it proves.
        try await Task.sleep(for: .milliseconds(600))

        let samples = try recorder.stop()
        #expect(recorder.isRecording == false)
        #expect(!samples.isEmpty, "the tap should have delivered audio")

        let duration = AudioFormat.duration(ofSampleCount: samples.count)
        #expect(duration > 0.2, "expected at least a fraction of a second, got \(duration)s")
    }

    @Test("Stopping without starting is an error, not an empty result")
    func stopWithoutStartThrows() {
        let recorder = AudioRecorder()

        #expect(throws: AudioRecorderError.self) {
            try recorder.stop()
        }
    }

    @Test("Cancelling discards the recording and releases the device")
    func cancelReleasesDevice() async throws {
        guard await AudioRecorder.requestPermission() else {
            Issue.record("Microphone permission is not granted; cannot run this test.")
            return
        }

        let recorder = AudioRecorder()
        try recorder.start()
        try await Task.sleep(for: .milliseconds(200))
        recorder.cancel()

        #expect(recorder.isRecording == false)
        // Starting again must succeed, which it cannot if cancel left the engine
        // holding the input device.
        try recorder.start()
        recorder.cancel()
    }
}
