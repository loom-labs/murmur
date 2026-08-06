import Foundation

/// User-facing preferences, persisted in `UserDefaults`.
///
/// Deliberately a small, flat value type rather than a sprawl of
/// `@AppStorage` properties scattered through the view layer: settings are read
/// from the audio and speech engines too, and those must not depend on SwiftUI.
public struct Settings: Equatable, Sendable {

    /// How the dictation hotkey behaves.
    public enum DictationMode: String, CaseIterable, Sendable {
        /// Record while the key is held, transcribe on release. Best for short
        /// bursts and the default because it is impossible to leave running.
        case pushToTalk
        /// First press starts, second press stops.
        case toggle

        public var title: String {
            switch self {
            case .pushToTalk: return "Hold to talk"
            case .toggle: return "Press to start and stop"
            }
        }
    }

    /// How the floating orb renders itself.
    public enum OrbStyle: String, CaseIterable, Sendable {
        /// The beagle's face: ears perk while listening, muzzle moves while
        /// speaking.
        case beagle
        /// Abstract level bars and a sweep ring.
        case classic

        public var title: String {
            switch self {
            case .beagle: return "Beagle"
            case .classic: return "Classic"
            }
        }
    }

    /// Which appearance the app's own windows use.
    public enum Appearance: String, CaseIterable, Sendable {
        /// Follow the system setting, including its automatic day/night switch.
        case system
        case light
        case dark

        public var title: String {
            switch self {
            case .system: return "Match System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    /// What Beagle does with a finished transcript.
    public enum TranscriptDelivery: String, CaseIterable, Sendable {
        /// Paste at the cursor in the frontmost app.
        case paste
        /// Copy to the clipboard and leave it there.
        case clipboard

        public var title: String {
            switch self {
            case .paste: return "Paste at cursor"
            case .clipboard: return "Copy to clipboard"
            }
        }
    }

    public var dictationMode: DictationMode
    public var transcriptDelivery: TranscriptDelivery
    public var orbStyle: OrbStyle
    public var appearance: Appearance

    /// Global shortcuts. Customizable, because any default will collide with
    /// something on someone's machine.
    public var dictationShortcut: KeyCombo
    public var speakSelectionShortcut: KeyCombo
    public var readScreenShortcut: KeyCombo

    /// Play a short tick when recording starts and stops.
    public var playFeedbackSounds: Bool

    /// Keep the floating orb on screen. When off, Beagle is menu-bar only.
    public var showsOrb: Bool

    /// Speech rate multiplier for synthesis, `0.5...2.0`.
    public var speechRate: Float

    /// Load models at launch instead of on first use. Costs ~700 MB of resident
    /// memory but removes the first-use delay.
    public var preloadModels: Bool

    public static let `default` = Settings(
        dictationMode: .pushToTalk,
        transcriptDelivery: .paste,
        orbStyle: .beagle,
        appearance: .system,
        dictationShortcut: .dictation,
        speakSelectionShortcut: .speakSelection,
        readScreenShortcut: .readScreen,
        playFeedbackSounds: true,
        showsOrb: true,
        speechRate: 1.0,
        preloadModels: false
    )
}

/// Reads and writes ``Settings`` to a `UserDefaults` suite.
///
/// Injectable so tests can run against an ephemeral suite instead of the user's
/// real preferences.
public final class SettingsStore: @unchecked Sendable {

    private enum Key {
        static let dictationMode = "dictationMode"
        static let transcriptDelivery = "transcriptDelivery"
        static let orbStyle = "orbStyle"
        static let appearance = "appearance"
        static let dictationShortcut = "dictationShortcut"
        static let speakSelectionShortcut = "speakSelectionShortcut"
        static let readScreenShortcut = "readScreenShortcut"
        static let playFeedbackSounds = "playFeedbackSounds"
        static let showsOrb = "showsOrb"
        static let speechRate = "speechRate"
        static let preloadModels = "preloadModels"
    }

    /// Kokoro's PostAlbert stage becomes unintelligible outside this range.
    public static let speechRateRange: ClosedRange<Float> = 0.5...2.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        register()
    }

    /// Seed defaults so a first launch reads real values rather than zeroes.
    private func register() {
        let fallback = Settings.default
        defaults.register(defaults: [
            Key.dictationMode: fallback.dictationMode.rawValue,
            Key.transcriptDelivery: fallback.transcriptDelivery.rawValue,
            Key.orbStyle: fallback.orbStyle.rawValue,
            Key.appearance: fallback.appearance.rawValue,
            Key.playFeedbackSounds: fallback.playFeedbackSounds,
            Key.showsOrb: fallback.showsOrb,
            Key.speechRate: fallback.speechRate,
            Key.preloadModels: fallback.preloadModels,
        ])
    }

    public var current: Settings {
        get {
            Settings(
                dictationMode: defaults.string(forKey: Key.dictationMode)
                    .flatMap(Settings.DictationMode.init(rawValue:)) ?? .pushToTalk,
                transcriptDelivery: defaults.string(forKey: Key.transcriptDelivery)
                    .flatMap(Settings.TranscriptDelivery.init(rawValue:)) ?? .paste,
                orbStyle: defaults.string(forKey: Key.orbStyle)
                    .flatMap(Settings.OrbStyle.init(rawValue:)) ?? .beagle,
                appearance: defaults.string(forKey: Key.appearance)
                    .flatMap(Settings.Appearance.init(rawValue:)) ?? .system,
                dictationShortcut: Self.combo(defaults, Key.dictationShortcut, fallback: .dictation),
                speakSelectionShortcut: Self.combo(
                    defaults, Key.speakSelectionShortcut, fallback: .speakSelection),
                readScreenShortcut: Self.combo(
                    defaults, Key.readScreenShortcut, fallback: .readScreen),
                playFeedbackSounds: defaults.bool(forKey: Key.playFeedbackSounds),
                showsOrb: defaults.bool(forKey: Key.showsOrb),
                speechRate: Self.clampRate(defaults.float(forKey: Key.speechRate)),
                preloadModels: defaults.bool(forKey: Key.preloadModels)
            )
        }
        set {
            defaults.set(newValue.dictationMode.rawValue, forKey: Key.dictationMode)
            defaults.set(newValue.transcriptDelivery.rawValue, forKey: Key.transcriptDelivery)
            defaults.set(newValue.orbStyle.rawValue, forKey: Key.orbStyle)
            defaults.set(newValue.appearance.rawValue, forKey: Key.appearance)
            Self.store(newValue.dictationShortcut, in: defaults, at: Key.dictationShortcut)
            Self.store(newValue.speakSelectionShortcut, in: defaults, at: Key.speakSelectionShortcut)
            Self.store(newValue.readScreenShortcut, in: defaults, at: Key.readScreenShortcut)
            defaults.set(newValue.playFeedbackSounds, forKey: Key.playFeedbackSounds)
            defaults.set(newValue.showsOrb, forKey: Key.showsOrb)
            defaults.set(Self.clampRate(newValue.speechRate), forKey: Key.speechRate)
            defaults.set(newValue.preloadModels, forKey: Key.preloadModels)
        }
    }

    /// Decode a stored shortcut, falling back when absent or corrupt.
    ///
    /// A malformed entry must not strand the user without a working shortcut,
    /// so a decode failure quietly restores the default rather than throwing.
    private static func combo(
        _ defaults: UserDefaults,
        _ key: String,
        fallback: KeyCombo
    ) -> KeyCombo {
        guard
            let data = defaults.data(forKey: key),
            let combo = try? JSONDecoder().decode(KeyCombo.self, from: data),
            combo.isValid
        else { return fallback }
        return combo
    }

    private static func store(_ combo: KeyCombo, in defaults: UserDefaults, at key: String) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        defaults.set(data, forKey: key)
    }

    /// Clamp into ``speechRateRange``, mapping a missing key (0) to normal speed.
    static func clampRate(_ rate: Float) -> Float {
        guard rate > 0 else { return 1.0 }
        return min(max(rate, speechRateRange.lowerBound), speechRateRange.upperBound)
    }
}
