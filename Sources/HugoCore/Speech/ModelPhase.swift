import Foundation

/// Lifecycle of a locally cached Core ML model bundle.
///
/// Both the speech-to-text and text-to-speech engines download weights on first
/// use, which can take a minute on a slow connection. Modelling that as an
/// explicit phase — rather than a bare `isReady` flag — lets the UI show real
/// progress instead of an indeterminate spinner, and lets a failed download be
/// retried without restarting the app.
public enum ModelPhase: Equatable, Sendable {

    /// Weights have not been requested yet.
    case idle

    /// Downloading weights. `fraction` is `nil` when the source does not report
    /// a total size.
    case downloading(fraction: Double?)

    /// Compiling and loading into Core ML. The first ever load also pays ANE
    /// compilation, which can take ~20 seconds.
    case loading

    /// Ready for inference.
    case ready

    /// Load failed. The message is user-facing.
    case failed(message: String)

    public var isReady: Bool {
        self == .ready
    }

    /// Whether work is in flight, for driving a busy indicator.
    public var isBusy: Bool {
        switch self {
        case .downloading, .loading: return true
        case .idle, .ready, .failed: return false
        }
    }

    /// Short status suitable for a menu bar item or settings row.
    public var summary: String {
        switch self {
        case .idle:
            return "Not loaded"
        case .downloading(let fraction):
            guard let fraction else { return "Downloading…" }
            return "Downloading \(Int(fraction * 100))%"
        case .loading:
            return "Loading…"
        case .ready:
            return "Ready"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}
