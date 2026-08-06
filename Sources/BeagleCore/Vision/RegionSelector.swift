import AppKit
import Foundation

/// Lets the user drag out a rectangle across the screen.
///
/// Replaces the crosshair that `/usr/sbin/screencapture -i` provides. Doing it
/// in-process is not a preference — it is the only way the capture is
/// attributed to Beagle. A spawned `screencapture` is a separate process, so
/// the Screen Recording grant the user gave Beagle does not cover it, and macOS
/// hands back a blank image rather than refusing.
@MainActor
final class RegionSelector {

    /// One overlay per screen, so a drag works on any display.
    private var overlays: [SelectionOverlay] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    /// Present the overlay and wait for a selection.
    ///
    /// - Returns: The chosen rectangle in bottom-left-origin screen coordinates,
    ///   or `nil` if the user pressed Escape or clicked without dragging.
    func selectRegion() async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    private func present() {
        for screen in NSScreen.screens {
            let overlay = SelectionOverlay(screen: screen)
            overlay.onFinish = { [weak self] rect in
                self?.finish(with: rect)
            }
            overlay.orderFrontRegardless()
            overlays.append(overlay)
        }
        // The overlay has to be key to receive the Escape key.
        NSApp.activate(ignoringOtherApps: true)
        overlays.first?.makeKey()
    }

    private func finish(with rect: CGRect?) {
        for overlay in overlays { overlay.orderOut(nil) }
        overlays.removeAll()

        // Guard against both overlays reporting: only the first wins.
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: rect)
    }
}

/// A full-screen transparent window that tracks one drag.
private final class SelectionOverlay: NSPanel {

    /// Called with the selected rect in screen coordinates, or `nil` to cancel.
    var onFinish: ((CGRect?) -> Void)?

    private let selectionView = SelectionView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Above everything, including full-screen apps, so the user can grab
        // any part of any window.
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        selectionView.frame = NSRect(origin: .zero, size: screen.frame.size)
        selectionView.screenOrigin = screen.frame.origin
        selectionView.onFinish = { [weak self] rect in self?.onFinish?(rect) }
        contentView = selectionView

        // A crosshair makes it obvious the screen is in a picking mode.
        NSCursor.crosshair.push()
    }

    deinit {
        NSCursor.pop()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onFinish?(nil)
    }

    override func keyDown(with event: NSEvent) {
        // 53 is Escape. Handled here as well as `cancelOperation` because a
        // borderless panel does not always get the latter.
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }
}

/// Draws the dimming layer and the live selection rectangle.
private final class SelectionView: NSView {

    var onFinish: ((CGRect?) -> Void)?

    /// Bottom-left origin of the screen this view covers, for converting the
    /// local rect into global screen coordinates.
    var screenOrigin: CGPoint = .zero

    private var anchor: CGPoint?
    private var current: CGRect = .zero

    /// A drag shorter than this in either axis is treated as a stray click.
    private static let minimumDrag: CGFloat = 4

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything, then punch out the selection so the user sees exactly
        // what will be captured.
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard !current.isEmpty else { return }

        NSColor.clear.setFill()
        current.fill(using: .copy)

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: current)
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        current = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        current = CGRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x),
            height: abs(point.y - anchor.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            anchor = nil
            current = .zero
        }

        guard
            current.width >= Self.minimumDrag,
            current.height >= Self.minimumDrag
        else {
            onFinish?(nil)
            return
        }

        // Local view coordinates → global screen coordinates.
        let global = CGRect(
            x: current.origin.x + screenOrigin.x,
            y: current.origin.y + screenOrigin.y,
            width: current.width,
            height: current.height
        )
        onFinish?(global)
    }
}
