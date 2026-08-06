import Carbon.HIToolbox
import Foundation
import Testing

@testable import BeagleCore

@Suite("Key combo")
struct KeyComboTests {

    @Test("Modifier symbols use Apple's canonical order")
    func modifierOrder() {
        let all: KeyCombo.Modifiers = [.command, .shift, .option, .control]
        // ⌃⌥⇧⌘ is the order Apple uses everywhere in menus; anything else looks
        // wrong next to native shortcuts.
        #expect(all.symbols == "⌃⌥⇧⌘")
    }

    @Test("Display name pairs modifiers with the key")
    func displayName() {
        // ⌃⌥⌘ rather than ⌃⌥: window managers claim ⌃⌥ — Rectangle owns ⌃⌥J
        // and ⌃⌥K for quarter-tiling. See KeyCombo's defaults for the reasoning.
        #expect(KeyCombo.dictation.displayName == "⌃⌥⌘L")
        #expect(KeyCombo.speakSelection.displayName == "⌃⌥⌘K")
        #expect(KeyCombo.readScreen.displayName == "⌃⌥⌘J")
    }

    @Test("Special keys render as glyphs, not codes")
    func specialKeyNames() {
        #expect(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.option]).displayName == "⌥Space")
        #expect(KeyCombo(keyCode: UInt32(kVK_Escape), modifiers: [.command]).displayName == "⌘⎋")
        #expect(KeyCombo(keyCode: UInt32(kVK_Return), modifiers: [.control]).displayName == "⌃↩")
    }

    @Test("An unmapped key code degrades to a readable label")
    func unknownKeyCode() {
        #expect(KeyCombo.keyName(for: 9_999) == "Key 9999")
    }

    @Test("Carbon flags map to the platform constants")
    func carbonFlags() {
        #expect(KeyCombo.Modifiers.command.carbonFlags == UInt32(cmdKey))
        #expect(KeyCombo.Modifiers.shift.carbonFlags == UInt32(shiftKey))
        #expect(KeyCombo.Modifiers.option.carbonFlags == UInt32(optionKey))
        #expect(KeyCombo.Modifiers.control.carbonFlags == UInt32(controlKey))

        let combined: KeyCombo.Modifiers = [.command, .shift]
        #expect(combined.carbonFlags == UInt32(cmdKey) | UInt32(shiftKey))
    }

    @Test("A shortcut with no modifiers is rejected")
    func rejectsBareKey() {
        // Registering bare "L" globally would swallow the letter everywhere and
        // leave the user unable to type it.
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: []).isValid == false)
    }

    @Test("Shift alone is rejected")
    func rejectsShiftOnly() {
        // ⇧L is just a capital L.
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: [.shift]).isValid == false)
    }

    @Test(
        "Any combo carrying command, option, or control is accepted",
        arguments: [
            KeyCombo.Modifiers.command,
            .option,
            .control,
            [.command, .shift],
            [.option, .shift],
            [.control, .option],
        ]
    )
    func acceptsRealModifiers(modifiers: KeyCombo.Modifiers) {
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: modifiers).isValid)
    }

    @Test("Combos round-trip through Codable")
    func codableRoundTrip() throws {
        // Shortcuts are persisted in settings, so this has to survive encoding.
        let original = KeyCombo.dictation
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)

        #expect(decoded == original)
        #expect(decoded.displayName == "⌃⌥⌘L")
    }

    @Test("Defaults are distinct from one another")
    func defaultsDoNotCollide() {
        let defaults = [KeyCombo.dictation, .speakSelection, .readScreen]
        #expect(Set(defaults).count == defaults.count)
        for combo in defaults {
            #expect(combo.isValid, "\(combo.displayName) is not safe to register")
        }
    }
}
