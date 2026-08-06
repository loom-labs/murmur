import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut: one key plus its modifiers.
///
/// Stored as a virtual key code rather than a character so the shortcut stays
/// in the same physical position across keyboard layouts — ⌃⌥L should be the
/// same key on QWERTY and AZERTY.
public struct KeyCombo: Equatable, Hashable, Codable, Sendable {

    /// Modifier keys, as an option set independent of AppKit and Carbon.
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)

        /// Carbon's mask, for `RegisterEventHotKey`.
        var carbonFlags: UInt32 {
            var flags: UInt32 = 0
            if contains(.command) { flags |= UInt32(cmdKey) }
            if contains(.shift) { flags |= UInt32(shiftKey) }
            if contains(.option) { flags |= UInt32(optionKey) }
            if contains(.control) { flags |= UInt32(controlKey) }
            return flags
        }

        /// Symbols in Apple's canonical order: ⌃⌥⇧⌘.
        var symbols: String {
            var result = ""
            if contains(.control) { result += "⌃" }
            if contains(.option) { result += "⌥" }
            if contains(.shift) { result += "⇧" }
            if contains(.command) { result += "⌘" }
            return result
        }
    }

    /// Virtual key code, as in Carbon's `kVK_` constants.
    public let keyCode: UInt32
    public let modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Human-readable form, e.g. `⇧⌘L`.
    public var displayName: String {
        modifiers.symbols + Self.keyName(for: keyCode)
    }

    /// Whether the combo is safe to register globally.
    ///
    /// A shortcut with no modifiers — or with Shift alone — would swallow
    /// ordinary typing system-wide, so those are rejected before they can make
    /// the machine unusable.
    public var isValid: Bool {
        !modifiers.isEmpty && modifiers != [.shift]
    }

    // MARK: - Defaults

    // Two modifiers and a letter — three keys. A third modifier would be safer
    // in the abstract and worse in the hand, and these are pressed constantly.
    //
    // The letters are chosen around window managers rather than by adding
    // modifiers. Rectangle, the most common one, claims ⌃⌥ with U I J K for
    // quarters, C D E F G T for thirds and centring, the arrows for halves,
    // and ⌃⌥⌘←/→ for displays — so adding ⌘ would have moved into its
    // namespace, not out of it. L, S and R are clear of all of it, and happen
    // to be mnemonic: listen, speak, read.
    //
    // macOS cannot report which combinations other applications hold — see
    // `HotKeyCenter.isAvailable` — so this avoids a known conflict rather than
    // proving the field is clear. Shortcuts are rebindable for the rest.
    //
    // Fn is deliberately not offered. `RegisterEventHotKey` accepts only
    // ⌘/⇧/⌥/⌃ — Fn is not a Carbon modifier — so an Fn shortcut would require a
    // `CGEventTap`, putting Beagle in the path of every keystroke on the
    // machine. That is a privacy and performance cost the app is built to
    // avoid; see SECURITY.md.

    /// Start and stop dictation. Held in push-to-talk mode.
    public static let dictation = KeyCombo(
        keyCode: UInt32(kVK_ANSI_L),
        modifiers: [.control, .option]
    )

    /// Read the current selection aloud.
    public static let speakSelection = KeyCombo(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: [.control, .option]
    )

    /// Capture a region of the screen and read it aloud.
    public static let readScreen = KeyCombo(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: [.control, .option]
    )

    // MARK: - Key names

    /// Names for keys whose glyph is not simply their character.
    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
    ]

    /// Printable keys, keyed by virtual key code.
    private static let printableKeyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
    ]

    /// Display name for a virtual key code.
    static func keyName(for keyCode: UInt32) -> String {
        if let name = specialKeyNames[keyCode] { return name }
        if let name = printableKeyNames[keyCode] { return name }
        // Function keys are contiguous from F1 but not worth a 20-entry table.
        if keyCode == UInt32(kVK_F1) { return "F1" }
        if keyCode == UInt32(kVK_F2) { return "F2" }
        if keyCode == UInt32(kVK_F3) { return "F3" }
        if keyCode == UInt32(kVK_F4) { return "F4" }
        if keyCode == UInt32(kVK_F5) { return "F5" }
        if keyCode == UInt32(kVK_F6) { return "F6" }
        if keyCode == UInt32(kVK_F7) { return "F7" }
        if keyCode == UInt32(kVK_F8) { return "F8" }
        if keyCode == UInt32(kVK_F9) { return "F9" }
        if keyCode == UInt32(kVK_F10) { return "F10" }
        if keyCode == UInt32(kVK_F11) { return "F11" }
        if keyCode == UInt32(kVK_F12) { return "F12" }
        return "Key \(keyCode)"
    }
}
