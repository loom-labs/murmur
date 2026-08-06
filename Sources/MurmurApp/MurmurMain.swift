import MurmurCore
import MurmurUI
import SwiftUI

/// Application entry point.
///
/// Murmur is a menu-bar-only agent: it has no Dock icon and no main window, so
/// the scene graph is a single ``MenuBarExtra``. Everything else the app shows
/// (the floating orb, the settings window) is presented on demand.
@main
struct MurmurMain: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "waveform")
                .accessibilityLabel(Murmur.appName)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Owns process-level configuration that SwiftUI's `App` protocol does not expose.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: no Dock tile, no menu bar takeover when focused. The app
        // is a background utility that other apps keep focus through.
        NSApp.setActivationPolicy(.accessory)
        Log.app.info("Murmur \(Murmur.version, privacy: .public) launched")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
