import Carbon.HIToolbox
import Testing

@testable import BeagleCore

/// Cover for the shortcut recorder being unable to see Beagle's own shortcuts.
///
/// A Carbon hot key is consumed by the system before the owning app receives an
/// ordinary key event, so while Beagle held ⌃⌥L the recorder's `NSEvent` monitor
/// never saw ⌃⌥L being pressed. Rebinding one action onto a key another action
/// owned was therefore impossible, and failed by doing nothing.
@Suite("Hot key suspension")
struct HotKeySuspendTests {

    @MainActor
    @Test("Resuming restores every suspended registration")
    func resumeRestoresRegistrations() {
        let center = HotKeyCenter.shared
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_8), modifiers: [.control, .option, .command])

        defer { center.unregisterAll() }

        guard let identifier = center.register(combo, handler: { _ in }) else {
            // Another application owns this combination on this machine, so the
            // behaviour under test cannot be observed here.
            return
        }

        center.suspend()
        #expect(
            center.registrations[identifier] != nil,
            "suspension must keep the registration so it can be reclaimed")

        center.resume()

        // Deliberately not asserting that the EventHotKeyRef pointer changed.
        // Carbon frequently hands back the same address after the old one is
        // released, so that would be asserting on the allocator rather than on
        // behaviour.
        let restored = center.registrations[identifier]
        #expect(restored != nil, "resuming must not drop the registration")
        #expect(restored?.combo == combo, "resuming must reclaim the same combination")

        // A second cycle must work too — the recorder opens and closes often.
        center.suspend()
        center.resume()
        #expect(center.registrations[identifier]?.combo == combo)
    }

    @MainActor
    @Test("Suspending twice is harmless")
    func suspendIsIdempotent() {
        let center = HotKeyCenter.shared
        defer { center.unregisterAll() }

        center.suspend()
        center.suspend()
        center.resume()
        center.resume()
    }
}
