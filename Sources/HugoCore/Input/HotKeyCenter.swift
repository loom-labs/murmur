import Carbon.HIToolbox
import Foundation

/// Which edge of a hotkey press fired.
public enum HotKeyEdge: Sendable {
    case pressed
    case released
}

/// Registers system-wide keyboard shortcuts.
///
/// Uses Carbon's `RegisterEventHotKey` rather than a `CGEventTap`. The Carbon
/// API is old but it is the right tool here: it needs no Accessibility
/// permission, it cannot drop events under load, and it does not put Hugo in
/// the path of every keystroke the user types — which is both a privacy
/// liability and a performance one.
///
/// Both press and release are delivered so push-to-talk can record for exactly
/// as long as the key is held.
@MainActor
public final class HotKeyCenter {

    public static let shared = HotKeyCenter()

    /// A registered shortcut, keyed by the id handed to Carbon.
    private struct Registration {
        let combo: KeyCombo
        let reference: EventHotKeyRef
        let handler: (HotKeyEdge) -> Void
    }

    /// Four-character signature identifying Hugo's hotkeys to Carbon.
    private static let signature: OSType = {
        let characters: [UInt8] = Array("murm".utf8)
        return characters.reduce(0) { ($0 << 8) | OSType($1) }
    }()

    private var registrations: [UInt32: Registration] = [:]
    private var nextIdentifier: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Register `combo`, replacing any existing registration for the same token.
    ///
    /// - Parameters:
    ///   - combo: The shortcut. Must satisfy ``KeyCombo/isValid``.
    ///   - handler: Called on the main actor for both press and release.
    /// - Returns: A token used to unregister, or `nil` when registration failed
    ///   — most often because another application already owns the shortcut.
    @discardableResult
    public func register(
        _ combo: KeyCombo,
        handler: @escaping (HotKeyEdge) -> Void
    ) -> UInt32? {
        guard combo.isValid else {
            Log.app.error("Refusing to register unsafe shortcut \(combo.displayName, privacy: .public)")
            return nil
        }

        installEventHandlerIfNeeded()

        let identifier = nextIdentifier
        nextIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers.carbonFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            Log.app.error(
                "Could not register \(combo.displayName, privacy: .public): OSStatus \(status, privacy: .public)"
            )
            return nil
        }

        registrations[identifier] = Registration(
            combo: combo,
            reference: reference,
            handler: handler
        )
        Log.app.info("Registered \(combo.displayName, privacy: .public)")
        return identifier
    }

    /// Release a shortcut registered with ``register(_:handler:)``.
    public func unregister(_ identifier: UInt32) {
        guard let registration = registrations.removeValue(forKey: identifier) else { return }
        UnregisterEventHotKey(registration.reference)
        Log.app.info("Released \(registration.combo.displayName, privacy: .public)")
    }

    /// Release every shortcut Hugo holds.
    public func unregisterAll() {
        for identifier in registrations.keys { unregister(identifier) }
    }

    /// Whether `combo` can be claimed right now.
    ///
    /// Implemented by trying: there is no API to query ownership, so this
    /// registers and immediately releases. Used by the settings UI to warn
    /// before saving a shortcut another app already owns.
    public func isAvailable(_ combo: KeyCombo) -> Bool {
        guard combo.isValid else { return false }
        guard registrations.values.allSatisfy({ $0.combo != combo }) else { return false }

        let probeID = EventHotKeyID(signature: Self.signature, id: .max)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers.carbonFlags,
            probeID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        UnregisterEventHotKey(reference)
        return true
    }

    // MARK: - Carbon plumbing

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]

        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventCallback,
            eventTypes.count,
            &eventTypes,
            nil,
            &eventHandler
        )
    }

    /// Dispatch a Carbon callback to the registered handler.
    ///
    /// Carbon delivers on the main run loop, so this is already main-actor
    /// correct; `assumeIsolated` documents that rather than hiding it behind an
    /// async hop that would add latency to a push-to-talk release.
    fileprivate func handle(identifier: UInt32, edge: HotKeyEdge) {
        registrations[identifier]?.handler(edge)
    }
}

/// C callback bridging Carbon events onto ``HotKeyCenter``.
private func hotKeyEventCallback(
    _ handlerCall: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let edge: HotKeyEdge = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? .pressed : .released
    let identifier = hotKeyID.id

    MainActor.assumeIsolated {
        HotKeyCenter.shared.handle(identifier: identifier, edge: edge)
    }
    return noErr
}
