import AppKit
import MurmurCore
import MurmurUI
import SwiftUI

/// The always-on-top window hosting the floating orb.
///
/// An `NSPanel` with `.nonactivatingPanel` rather than an `NSWindow`: clicking
/// the orb must never take focus away from the app the user is typing in,
/// because the very next thing Murmur does is paste into it. A normal window
/// would steal key focus and paste into itself.
final class OrbPanel: NSPanel {

    /// Distance from the screen edge used for the first-launch position.
    private static let defaultInset: CGFloat = 24

    /// `UserDefaults` key holding the orb's last position.
    private static let originKey = "orbOrigin"

    init(content: some View) {
        let size = NSSize(width: OrbView.diameter, height: OrbView.diameter)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            // `.borderless` alone would refuse key status; `.nonactivatingPanel`
            // is what keeps the frontmost app frontmost.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // the SwiftUI view draws its own, shaped to the circle
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        // Follow the user across Spaces and sit above full-screen apps, so the
        // orb is reachable without leaving whatever they are working in.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        contentView = hosting

        restorePosition()
    }

    /// Borderless panels are excluded from key status by default; the orb needs
    /// it so SwiftUI hover and drop targets receive events.
    override var canBecomeKey: Bool { true }

    /// Never become main — that is what would pull focus from the user's app.
    override var canBecomeMain: Bool { false }

    /// Persist the position whenever the user finishes dragging.
    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        UserDefaults.standard.set(NSStringFromPoint(point), forKey: Self.originKey)
    }

    /// Restore the saved position, falling back to the lower-right of the main
    /// screen and clamping to the visible frame so an orb saved on a display
    /// that is now disconnected cannot end up off-screen.
    private func restorePosition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame

        var origin = NSPoint(
            x: visible.maxX - OrbView.diameter - Self.defaultInset,
            y: visible.minY + Self.defaultInset
        )

        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let point = NSPointFromString(saved)
            let onAnyScreen = NSScreen.screens.contains { screen in
                screen.visibleFrame.intersects(
                    NSRect(origin: point, size: NSSize(width: OrbView.diameter, height: OrbView.diameter))
                )
            }
            if onAnyScreen { origin = point }
        }

        setFrameOrigin(origin)
    }
}
