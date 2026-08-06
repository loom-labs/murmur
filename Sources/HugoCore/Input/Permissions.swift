import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// The system permissions Hugo needs, and how to ask for them.
///
/// Each is requested lazily, at the moment the feature that needs it is first
/// used, rather than in a wall of prompts at launch. A user who only ever
/// dictates should never be asked about screen recording.
public enum Permission: String, CaseIterable, Sendable {

    /// Microphone capture, for dictation.
    case microphone

    /// Posting synthetic keystrokes and reading the selection in other apps.
    case accessibility

    /// Capturing a screen region for OCR.
    case screenRecording

    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    /// Why Hugo needs it, in the user's terms.
    public var rationale: String {
        switch self {
        case .microphone:
            return "So Hugo can hear you when you dictate."
        case .accessibility:
            return "So Hugo can paste transcripts at your cursor and read your selection."
        case .screenRecording:
            return "So Hugo can read text from a region of your screen."
        }
    }

    /// Deep link to the matching System Settings pane.
    public var settingsURL: URL? {
        let pane =
            switch self {
            case .microphone: "Privacy_Microphone"
            case .accessibility: "Privacy_Accessibility"
            case .screenRecording: "Privacy_ScreenCapture"
            }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}

/// Queries and requests system permissions.
@MainActor
public enum Permissions {

    /// Whether `permission` is currently granted.
    public static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        }
    }

    /// Request `permission`, showing the system prompt if it has never been asked.
    ///
    /// - Returns: `true` when granted.
    ///
    /// Accessibility is the odd one out: macOS never returns a decision
    /// synchronously and the user must toggle a switch in System Settings, so
    /// this returns the *current* state after showing the prompt. Callers
    /// should re-check rather than treat `false` as a final refusal.
    @discardableResult
    public static func request(_ permission: Permission) async -> Bool {
        switch permission {
        case .microphone:
            return await AudioRecorder.requestPermission()

        case .accessibility:
            guard !AXIsProcessTrusted() else { return true }
            // Passing the prompt option opens System Settings for the user.
            // The key is spelled out rather than read from
            // `kAXTrustedCheckOptionPrompt`: that symbol is an unannotated
            // mutable global in the C header, which Swift 6 rejects as
            // concurrency-unsafe. The string value is stable public API.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)

        case .screenRecording:
            guard !CGPreflightScreenCaptureAccess() else { return true }
            return CGRequestScreenCaptureAccess()
        }
    }

    /// Open the System Settings pane for `permission`.
    ///
    /// Needed because macOS shows the Accessibility prompt only once per app;
    /// after a user declines, the only route back is Settings.
    public static func openSettings(for permission: Permission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
