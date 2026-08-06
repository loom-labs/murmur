import AppKit
import BeagleCore
import SwiftUI

/// Contents of the menu bar dropdown.
///
/// Kept to status plus the few actions that are awkward to reach by hotkey.
/// Everything else lives in Settings — a menu bar item that unfolds into a
/// control panel is a menu bar item nobody reads.
public struct MenuBarContent: View {

    private let controller: BeagleController
    private let openSettings: () -> Void

    public init(controller: BeagleController, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.openSettings = openSettings
    }

    public var body: some View {
        Text(controller.activity.summary)

        if !TextInjector.canPostEvents {
            Text("Accessibility is off — transcripts go to the clipboard")
            Text("Remove any old Beagle entry first; the grant is tied to each build.")
            Button("Open Accessibility Settings…") {
                Permissions.openSettings(for: .accessibility)
            }
        }

        Divider()

        if controller.isSpeaking {
            Button("Stop Speaking") { controller.cancelSpeech() }
        } else {
            Button("Speak Selection") {
                Task { await controller.speakSelection() }
            }
        }

        Button(controller.activity == .listening ? "Stop Dictating" : "Start Dictating") {
            Task { await controller.toggleDictation() }
        }

        if let transcript = controller.lastTranscript {
            Button("Copy Last Transcript") {
                TextInjector.copyToClipboard(transcript)
            }
        }

        Divider()

        // Only shown while loading or after a failure: a permanent "Ready" row
        // for each engine would be noise.
        if controller.recognitionPhase.isBusy || isFailed(controller.recognitionPhase) {
            Text("Speech recognition: \(controller.recognitionPhase.summary)")
        }
        if controller.synthesisPhase.isBusy || isFailed(controller.synthesisPhase) {
            Text("Voice: \(controller.synthesisPhase.summary)")
        }

        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")

        Divider()

        Button("Quit Beagle") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func isFailed(_ phase: ModelPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }
}
