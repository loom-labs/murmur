import Foundation
import Testing

@testable import BeagleCore

@Suite("Model phase")
struct ModelPhaseTests {

    @Test("Only ready reports readiness")
    func readinessIsExclusive() {
        #expect(ModelPhase.ready.isReady)
        #expect(ModelPhase.idle.isReady == false)
        #expect(ModelPhase.loading.isReady == false)
        #expect(ModelPhase.downloading(fraction: 1.0).isReady == false)
        #expect(ModelPhase.failed(message: "x").isReady == false)
    }

    @Test("Busy covers exactly the in-flight phases")
    func busyCoversInFlight() {
        #expect(ModelPhase.downloading(fraction: nil).isBusy)
        #expect(ModelPhase.loading.isBusy)
        #expect(ModelPhase.idle.isBusy == false)
        #expect(ModelPhase.ready.isBusy == false)
        #expect(ModelPhase.failed(message: "x").isBusy == false)
    }

    @Test("Download progress renders as a whole percentage")
    func downloadSummaryShowsPercent() {
        #expect(ModelPhase.downloading(fraction: 0.42).summary == "Downloading 42%")
        #expect(ModelPhase.downloading(fraction: nil).summary == "Downloading…")
    }

    @Test("Failure summary carries the message through to the user")
    func failureSummaryIncludesMessage() {
        #expect(ModelPhase.failed(message: "no network").summary == "Failed: no network")
    }

    @Test("Phases with different progress are not equal")
    func progressParticipatesInEquality() {
        // The service suppresses duplicate observer callbacks by comparing
        // phases, so distinct progress values must compare unequal or the UI
        // would freeze at the first percentage.
        #expect(ModelPhase.downloading(fraction: 0.1) != ModelPhase.downloading(fraction: 0.2))
    }
}

@Suite("Transcript")
struct TranscriptTests {

    @Test("Realtime factor is audio over processing time")
    func realtimeFactor() {
        let transcript = Transcript(
            text: "hello",
            confidence: 0.9,
            audioDuration: 12.0,
            processingTime: 0.1
        )
        #expect(transcript.realtimeFactor == 120)
    }

    @Test("Realtime factor is zero when processing time is unmeasured")
    func realtimeFactorGuardsDivideByZero() {
        let transcript = Transcript(
            text: "hello",
            confidence: 0.9,
            audioDuration: 12.0,
            processingTime: 0
        )
        #expect(transcript.realtimeFactor == 0)
    }
}

@Suite("Audio format")
struct AudioFormatTests {

    @Test("Duration converts sample counts at 16 kHz")
    func durationConverts() {
        #expect(AudioFormat.duration(ofSampleCount: 16_000) == 1.0)
        #expect(AudioFormat.duration(ofSampleCount: 8_000) == 0.5)
        #expect(AudioFormat.duration(ofSampleCount: 0) == 0)
    }
}
