import Foundation

/// Package-wide identity and filesystem conventions.
///
/// Everything user-visible that needs a stable string — the bundle id, the
/// support directory, the app name — resolves through here so renames stay a
/// one-line change.
public enum Murmur {

    /// Marketing name, used in menus and window titles.
    public static let appName = "Murmur"

    /// Reverse-DNS bundle identifier. Must match `Info.plist` in the packaged
    /// `.app`, otherwise macOS treats permission grants as belonging to a
    /// different application on every launch.
    public static let bundleIdentifier = "ai.loomlabs.murmur"

    /// Semantic version, injected at build time from the repository `VERSION`
    /// file via `-DMURMUR_VERSION`. Falls back to `0.0.0-dev` for plain
    /// `swift build` / `swift test` invocations.
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0-dev"
    }

    /// `~/Library/Application Support/Murmur`, created on first access.
    ///
    /// Holds the transcript history database and any user-authored assets.
    /// Model weights deliberately live elsewhere — see ``modelsDirectory``.
    public static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Cache location for downloaded Core ML weights.
    ///
    /// Deliberately under `~/.cache` rather than Application Support: these are
    /// reproducible downloads, not user data, so they should not be swept into
    /// backups. This is also the path FluidAudio defaults to, which means a
    /// user who already runs another FluidAudio-backed app shares the weights
    /// instead of paying for a second copy.
    public static func modelsDirectory() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory =
            home
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("fluidaudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
