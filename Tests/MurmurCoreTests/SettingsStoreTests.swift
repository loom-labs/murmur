import Foundation
import Testing

@testable import MurmurCore

@Suite("Settings store")
struct SettingsStoreTests {

    /// A `UserDefaults` suite scoped to one test, removed on teardown so tests
    /// never touch the developer's real preferences or each other's.
    private let suiteName: String
    private let defaults: UserDefaults

    init() throws {
        suiteName = "ai.loomlabs.murmur.tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    private func teardown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("First read returns the documented defaults")
    func firstReadReturnsDefaults() {
        defer { teardown() }
        let store = SettingsStore(defaults: defaults)

        #expect(store.current == .default)
    }

    @Test("Values survive a round trip")
    func roundTrips() {
        defer { teardown() }
        var store = SettingsStore(defaults: defaults)

        var updated = Settings.default
        updated.dictationMode = .toggle
        updated.transcriptDelivery = .clipboard
        updated.playFeedbackSounds = false
        updated.showsOrb = false
        updated.speechRate = 1.25
        updated.preloadModels = true
        store.current = updated

        // A fresh store reads the same persisted suite.
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.current == updated)
    }

    @Test(
        "Speech rate is clamped into the intelligible range",
        arguments: [
            (Float(0.0), Float(1.0)),
            (Float(0.1), Float(0.5)),
            (Float(0.5), Float(0.5)),
            (Float(1.0), Float(1.0)),
            (Float(2.0), Float(2.0)),
            (Float(9.9), Float(2.0)),
            (Float(-3.0), Float(1.0)),
        ]
    )
    func clampsSpeechRate(input: Float, expected: Float) {
        #expect(SettingsStore.clampRate(input) == expected)
    }

    @Test("An out-of-range stored rate is clamped on read")
    func clampsOnRead() {
        defer { teardown() }
        defaults.set(Float(7.5), forKey: "speechRate")

        let store = SettingsStore(defaults: defaults)
        #expect(store.current.speechRate == 2.0)
    }

    @Test("An unrecognised enum value falls back rather than crashing")
    func unknownEnumFallsBack() {
        defer { teardown() }
        defaults.set("nonsense", forKey: "dictationMode")

        let store = SettingsStore(defaults: defaults)
        #expect(store.current.dictationMode == .pushToTalk)
    }
}
