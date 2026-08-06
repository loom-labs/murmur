import AppKit
import Carbon.HIToolbox
import Foundation

/// Errors raised while moving text in or out of other applications.
public enum TextInjectionError: LocalizedError {
    case accessibilityNotGranted
    case eventCreationFailed
    case nothingSelected

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Hugo needs Accessibility access to type into other apps."
        case .eventCreationFailed:
            return "Could not synthesize a keyboard event."
        case .nothingSelected:
            return "No text is selected."
        }
    }
}

/// Moves text between Hugo and whatever application has focus.
///
/// Both directions go through the pasteboard and a synthetic ⌘V / ⌘C. Typing
/// character by character with `CGEvent` was tried and rejected: it is an order
/// of magnitude slower on long transcripts, mangles non-ASCII text, and races
/// with apps that do their own input handling. The cost of the pasteboard route
/// is that it briefly borrows the clipboard, so this restores the previous
/// contents afterwards.
@MainActor
public enum TextInjector {

    /// How long to leave text on the pasteboard before restoring the previous
    /// contents.
    ///
    /// The receiving app reads the pasteboard asynchronously after ⌘V lands, so
    /// restoring immediately would paste the *old* clipboard. 300 ms clears
    /// every app tested, including slow Electron ones.
    private static let restoreDelay: Duration = .milliseconds(300)

    /// How long to wait for a ⌘C to land before giving up on the selection.
    private static let copyTimeout: Duration = .milliseconds(500)

    /// A snapshot of the pasteboard, so it can be put back.
    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
        let changeCount: Int
    }

    /// Paste `text` at the cursor in the frontmost application.
    public static func insert(_ text: String) throws {
        guard !text.isEmpty else { return }
        guard Permissions.isGranted(.accessibility) else {
            throw TextInjectionError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general
        let snapshot = capture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        try postCommandKey(kVK_ANSI_V)

        Task {
            try? await Task.sleep(for: restoreDelay)
            // If the user copied something in the meantime, their clipboard
            // wins — silently overwriting it would be worse than leaving the
            // transcript behind.
            guard pasteboard.changeCount == ourChangeCount else { return }
            restore(snapshot, to: pasteboard)
        }

        Log.app.info("Inserted \(text.count, privacy: .public) characters at the cursor")
    }

    /// Put `text` on the clipboard without pasting it.
    public static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Read the current selection from the frontmost application.
    ///
    /// - Returns: The selected text, or `nil` when nothing is selected.
    public static func readSelection() async throws -> String? {
        guard Permissions.isGranted(.accessibility) else {
            throw TextInjectionError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general
        let snapshot = capture(pasteboard)
        let beforeCount = pasteboard.changeCount

        try postCommandKey(kVK_ANSI_C)

        // Poll rather than sleeping a fixed interval: most apps answer in well
        // under 50 ms, and waiting the full timeout every time would make
        // "speak my selection" feel sluggish.
        let deadline = ContinuousClock.now.advanced(by: copyTimeout)
        while ContinuousClock.now < deadline {
            if pasteboard.changeCount != beforeCount { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        guard pasteboard.changeCount != beforeCount else {
            restore(snapshot, to: pasteboard)
            return nil
        }

        let selected = pasteboard.string(forType: .string)
        restore(snapshot, to: pasteboard)

        let trimmed = selected?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    // MARK: - Event synthesis

    /// Post ⌘ + `keyCode` as a synthetic key press.
    private static func postCommandKey(_ keyCode: Int) throws {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: false
            )
        else {
            throw TextInjectionError.eventCreationFailed
        }

        // Set the flags explicitly instead of inheriting the current keyboard
        // state. The dictation hotkey may still be physically held when this
        // fires, and an inherited Shift would turn ⌘V into ⇧⌘V — "paste and
        // match style" in some apps, and something else entirely in others.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Pasteboard preservation

    private static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
        return PasteboardSnapshot(items: items, changeCount: pasteboard.changeCount)
    }

    private static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let restored = snapshot.items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
