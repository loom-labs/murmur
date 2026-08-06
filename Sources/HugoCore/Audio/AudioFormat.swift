import Foundation

/// The audio format every speech model in Hugo expects.
///
/// Both Parakeet and Kokoro's frontend are fixed at 16 kHz mono float32, so this
/// is a property of the models rather than a user preference. Kept free of actor
/// isolation deliberately: capture runs on the main actor, transcription runs on
/// its own actor, and both need these numbers.
public enum AudioFormat {

    /// Input rate for speech recognition, in hertz.
    public static let sampleRate: Double = 16_000

    /// ``sampleRate`` as an integer, for APIs that want frame counts.
    public static let sampleRateInt = 16_000

    /// Output rate of Kokoro's vocoder, in hertz.
    public static let synthesisSampleRate: Double = 24_000

    /// Seconds of audio represented by `count` samples at ``sampleRate``.
    public static func duration(ofSampleCount count: Int) -> TimeInterval {
        Double(count) / sampleRate
    }
}
