import AVFoundation
import Testing

@testable import BeagleCore

/// Regression cover for the completion-handler crash.
///
/// `AVAudioPlayerNode` invokes its completion handler on a private dispatch
/// queue. A handler that Swift infers as `@MainActor` traps on entry there, and
/// the trap surfaced as the app quitting the moment speech finished — not as an
/// error anyone could see. Playing real audio in a unit test is not practical,
/// so this asserts the property that made the crash possible: enqueueing must
/// be safe to drive to completion without the process dying.
@Suite("Speech player")
struct SpeechPlayerTests {

    @MainActor
    @Test("Enqueueing and stopping does not trap")
    func enqueueAndStop() throws {
        let player = SpeechPlayer()
        let samples = [Float](repeating: 0, count: 2400)

        try player.enqueue(samples)
        player.stop()

        #expect(player.state == .idle)
    }

    @MainActor
    @Test("Empty input is ignored rather than scheduled")
    func emptyInputIgnored() throws {
        let player = SpeechPlayer()
        try player.enqueue([])
        #expect(player.state == .idle)
    }
}
