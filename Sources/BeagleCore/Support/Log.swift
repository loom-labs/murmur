import OSLog

/// Shared `os.Logger` instances, one per subsystem.
///
/// `OSLog` is used rather than `print` so release builds stay quiet by default
/// but remain inspectable through Console.app and `log stream` when a user
/// reports a bug. Signposts are cheap enough to leave in hot paths.
public enum Log {

    private static let subsystem = Beagle.bundleIdentifier

    /// Application lifecycle, windows, hotkey registration.
    public static let app = Logger(subsystem: subsystem, category: "app")

    /// Microphone capture and audio graph state.
    public static let audio = Logger(subsystem: subsystem, category: "audio")

    /// Speech-to-text: model loading and transcription.
    public static let asr = Logger(subsystem: subsystem, category: "asr")

    /// Text-to-speech: synthesis and playback.
    public static let tts = Logger(subsystem: subsystem, category: "tts")

    /// Model downloads and cache management.
    public static let models = Logger(subsystem: subsystem, category: "models")
}
