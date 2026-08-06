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

    /// Where downloaded Core ML weights live: `~/Library/Application
    /// Support/FluidAudio/Models`.
    ///
    /// This is FluidAudio's own default, and Murmur deliberately does not
    /// override it — a user who already runs another FluidAudio-backed app
    /// shares the weights instead of paying for a second ~1 GB copy.
    ///
    /// Not created here: FluidAudio owns the layout inside this directory, and
    /// this accessor exists so the UI can report cache size and offer to clear it.
    public static func modelsDirectory() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return
            base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Total bytes occupied by downloaded weights, or zero when nothing is cached.
    public static func cachedModelBytes() -> Int64 {
        let directory = modelsDirectory()
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize
            total += Int64(size ?? 0)
        }
        return total
    }
}
