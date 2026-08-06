import Foundation
import Testing

@testable import MurmurCore

@Suite("Activity state")
struct ActivityStateTests {

    @Test("Busy covers exactly the states with work in flight")
    func busyStates() {
        #expect(ActivityState.listening.isBusy)
        #expect(ActivityState.transcribing.isBusy)
        #expect(ActivityState.speaking.isBusy)
        #expect(ActivityState.idle.isBusy == false)
        #expect(ActivityState.failed(message: "x").isBusy == false)
    }

    @Test("Every state has a distinct menu bar glyph")
    func distinctSymbols() {
        // The glyph is the only status indicator a user sees at a glance, so two
        // states sharing one would make the menu bar ambiguous.
        let states: [ActivityState] = [
            .idle, .listening, .transcribing, .speaking, .failed(message: "x"),
        ]
        let symbols = states.map(\.symbolName)
        #expect(Set(symbols).count == states.count)
        for symbol in symbols {
            #expect(!symbol.isEmpty)
        }
    }

    @Test("Failure surfaces the message rather than a generic label")
    func failureSummary() {
        #expect(ActivityState.failed(message: "Microphone is off").summary == "Microphone is off")
    }

    @Test("Non-failure states read as plain status")
    func statusSummaries() {
        #expect(ActivityState.idle.summary == "Ready")
        #expect(ActivityState.listening.summary == "Listening…")
        #expect(ActivityState.transcribing.summary == "Transcribing…")
        #expect(ActivityState.speaking.summary == "Speaking…")
    }

    @Test("Failures with different messages are distinct")
    func failureEquality() {
        // The controller compares states to decide whether to clear a failure
        // badge; collapsing distinct messages would drop the second error.
        #expect(ActivityState.failed(message: "a") != ActivityState.failed(message: "b"))
        #expect(ActivityState.failed(message: "a") == ActivityState.failed(message: "a"))
    }
}
