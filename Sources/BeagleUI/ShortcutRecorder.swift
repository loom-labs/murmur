import AppKit
import BeagleCore
import SwiftUI

/// A field that records a global shortcut.
///
/// Click it, press a combination, and it is saved. Uses a **local** event
/// monitor — it only sees keys pressed while Beagle's settings window has
/// focus, so recording a shortcut needs no additional permission and never
/// observes typing in other applications.
public struct ShortcutRecorder: View {

    private let title: String
    @Binding private var combo: KeyCombo

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var problem: String?

    public init(_ title: String, combo: Binding<KeyCombo>) {
        self.title = title
        self._combo = combo
    }

    public var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Button(action: toggle) {
                        Text(isRecording ? "Press keys…" : combo.displayName)
                            .font(.system(.body, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 76)
                            .foregroundStyle(isRecording ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.bordered)
                    .help("Click, then press the combination you want")

                    if isRecording {
                        Button("Cancel", action: stop)
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }

                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        problem = nil
        isRecording = true

        // Beagle's own shortcuts are Carbon hot keys, which the system consumes
        // before this monitor ever runs. Without standing them down, pressing
        // any key Beagle already owns does nothing at all — which is exactly
        // what you press when you are trying to move it.
        HotKeyCenter.shared.suspend()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape abandons recording and keeps the existing shortcut.
            if event.keyCode == 53 {
                stop()
                return nil
            }
            record(event)
            // Swallowed, so the keystroke does not also reach the UI behind it.
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotKeyCenter.shared.resume()
    }

    private func record(_ event: NSEvent) {
        var modifiers: KeyCombo.Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }

        let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)

        // A shortcut with no real modifier would swallow that key everywhere.
        guard candidate.isValid else {
            problem = "Add ⌘, ⌥, or ⌃ — a bare key would be captured system-wide."
            return
        }

        // Registering is the only way to know whether something else owns it.
        guard candidate == combo || HotKeyCenter.shared.isAvailable(candidate) else {
            problem = "\(candidate.displayName) is already taken by another app."
            return
        }

        // Fn cannot be captured here, and would not be registrable anyway —
        // `RegisterEventHotKey` has no Fn modifier. Saying so beats letting a
        // user press ⌥-Fn-L and wonder why only ⌥L was stored.
        if event.modifierFlags.contains(.function) {
            problem = "Fn cannot be used in a global shortcut on macOS."
            return
        }

        combo = candidate
        problem = nil
        stop()
    }
}
