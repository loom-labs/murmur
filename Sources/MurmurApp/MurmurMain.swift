import AppKit
import MurmurCore
import MurmurUI
import SwiftUI

/// Application entry point.
///
/// Murmur is a menu-bar-only agent: no Dock tile, no main window. The scene
/// graph is a single ``MenuBarExtra``; the orb and the settings window are
/// presented by ``AppDelegate`` on demand.
@main
struct MurmurMain: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: delegate.controller) {
                delegate.showSettings()
            }
        } label: {
            // The glyph doubles as the status indicator, so a glance at the
            // menu bar answers "is it listening?" without opening anything.
            Image(systemName: delegate.controller.activity.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Owns the objects SwiftUI's `App` protocol cannot: the controller, the orb
/// panel, and the settings window.
///
/// The controller is a `let` built at delegate initialization rather than an
/// optional filled in at `applicationDidFinishLaunching`. SwiftUI evaluates the
/// scene body before that callback runs, so an optional would force every view
/// to handle a nil case that only exists for the first few milliseconds of the
/// process. Construction has no side effects; those stay in `start()`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let controller = MurmurController()

    private var orbPanel: OrbPanel?
    private var settingsWindow: NSWindow?
    private var orbPreferenceTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: no Dock tile, and focus stays with whatever app the user
        // is typing in — which is the app Murmur is about to paste into.
        NSApp.setActivationPolicy(.accessory)

        controller.start()

        if controller.settings.showsOrb { showOrb(for: controller) }
        observeOrbPreference(controller)

        Log.app.info("Murmur \(Murmur.version, privacy: .public) launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        orbPreferenceTimer?.invalidate()
        controller.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Orb

    private func showOrb(for controller: MurmurController) {
        guard orbPanel == nil else { return }
        let panel = OrbPanel(content: OrbContainer(controller: controller))
        panel.orderFrontRegardless()
        orbPanel = panel
    }

    private func hideOrb() {
        orbPanel?.orderOut(nil)
        orbPanel = nil
    }

    /// Show or hide the orb as the preference changes.
    ///
    /// Polled through a short timer rather than observed: `@Observable` change
    /// tracking is a SwiftUI-view mechanism, and this is AppKit window
    /// management sitting outside any view.
    private func observeOrbPreference(_ controller: MurmurController) {
        orbPreferenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self, weak controller] _ in
            Task { @MainActor in
                guard let self, let controller else { return }
                if controller.settings.showsOrb {
                    self.showOrb(for: controller)
                } else {
                    self.hideOrb()
                }
            }
        }
    }

    // MARK: - Settings

    func showSettings() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(Murmur.appName) Settings"
        window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
