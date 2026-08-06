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
            return "Accessibility is off — the transcript is on your clipboard."
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

    /// Whether this process may post synthetic keyboard events.
    ///
    /// `CGPreflightPostEventAccess()` rather than `AXIsProcessTrusted()`: they
    /// read the same TCC service, but the trust check can report `true` from a
    /// stale entry — one granted to a previous build of an ad-hoc signed app,
    /// whose signature changed on the next rebuild. In that state `AXIsProcessTrusted`
    /// says yes and every posted event is silently dropped. The CG preflight
    /// tracks what actually governs posting.
    public static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    /// Ask for permission to post events, prompting on first call.
    @discardableResult
    public static func requestEventPosting() -> Bool {
        CGRequestPostEventAccess()
    }

    /// Paste `text` at the cursor in the frontmost application.
    ///
    /// The text is left on the clipboard when the paste cannot be confirmed, so
    /// a failure never loses a transcript — ⌘V still works.
    public static func insert(_ text: String) throws {
        guard !text.isEmpty else { return }

        // Checked before the clipboard is touched. An earlier version clobbered
        // the clipboard first, posted a ⌘V that was silently dropped, and then
        // restored the previous contents 300 ms later — destroying the
        // transcript entirely and leaving no trace of what went wrong.
        guard canPostEvents else {
            copyToClipboard(text)
            throw TextInjectionError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general
        let snapshot = capture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        do {
            try postCommandKey(kVK_ANSI_V)
        } catch {
            // The transcript stays on the clipboard rather than being rolled
            // back: recovering it with ⌘V beats losing it.
            throw error
        }

        Task {
            try? await Task.sleep(for: restoreDelay)
            // If the user copied something in the meantime, their clipboard
            // wins — silently overwriting it would be worse than leaving the
            // transcript behind.
            guard pasteboard.changeCount == ourChangeCount else { return }
            // Re-check: losing posting rights between the ⌘V and the restore
            // means the paste never landed, and restoring would throw the
            // transcript away.
            guard canPostEvents else { return }
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
        guard canPostEvents else {
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
