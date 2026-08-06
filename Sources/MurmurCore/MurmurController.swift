import AppKit
import Foundation
import Observation

/// What Murmur is doing right now.
///
/// Drives the orb, the menu bar glyph, and which hotkeys are meaningful. Kept
/// as one enum rather than a set of booleans so impossible combinations —
/// listening while speaking, say — cannot be represented.
public enum ActivityState: Equatable, Sendable {

    /// Waiting for a hotkey.
    case idle

    /// Recording from the microphone.
    case listening

    /// Running speech recognition on the captured audio.
    case transcribing

    /// Synthesizing or playing speech.
    case speaking

    /// Something failed. Clears on the next successful action.
    case failed(message: String)

    /// SF Symbol representing this state in the menu bar.
    public var symbolName: String {
        switch self {
        case .idle: return "waveform"
        case .listening: return "mic.fill"
        case .transcribing: return "waveform.badge.magnifyingglass"
        case .speaking: return "speaker.wave.2.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// Short label for the menu bar dropdown.
    public var summary: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .speaking: return "Speaking…"
        case .failed(let message): return message
        }
    }

    public var isBusy: Bool {
        switch self {
        case .listening, .transcribing, .speaking: return true
        case .idle, .failed: return false
        }
    }
}

/// Coordinates capture, recognition, synthesis, and delivery.
///
/// This is the one object that knows the whole flow; the engines below it stay
/// independent and testable, and the views above it only observe state. All of
/// it runs on the main actor because every input and output — hotkeys, the
/// pasteboard, the orb — is main-actor bound anyway.
@MainActor
@Observable
public final class MurmurController {

    // MARK: - Observable state

    public private(set) var activity: ActivityState = .idle
    public private(set) var recognitionPhase: ModelPhase = .idle
    public private(set) var synthesisPhase: ModelPhase = .idle

    /// The most recent transcript, for the menu bar's "copy last" affordance.
    public private(set) var lastTranscript: String?

    /// Text currently being spoken, for caption display.
    public private(set) var spokenText: String?

    public var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.current = settings
            if settings.dictationMode != oldValue.dictationMode { rebindHotKeys() }
        }
    }

    // MARK: - Collaborators

    private let recorder = AudioRecorder()
    private let recognition = TranscriptionService()
    private let synthesis = SynthesisService()
    private let player = SpeechPlayer()
    private let settingsStore: SettingsStore

    private var hotKeyTokens: [UInt32] = []
    private var speechTask: Task<Void, Never>?

    public init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.current

        player.onStateChange = { [weak self] state in
            guard let self else { return }
            if state == .idle, self.activity == .speaking { self.activity = .idle }
        }
    }

    /// Register hotkeys and observe model loading. Call once at launch.
    public func start() {
        rebindHotKeys()
        observeModelPhases()

        if settings.preloadModels {
            Task { await preloadModels() }
        }
    }

    /// Release hotkeys. Call at termination.
    public func stop() {
        cancelSpeech()
        for token in hotKeyTokens { HotKeyCenter.shared.unregister(token) }
        hotKeyTokens.removeAll()
    }

    // MARK: - Dictation

    /// Begin capturing, after confirming microphone access.
    public func startDictation() async {
        guard activity == .idle || isFailed else { return }

        guard await Permissions.request(.microphone) else {
            fail("Microphone access is off. Turn it on in System Settings.")
            return
        }

        do {
            try recorder.start()
            activity = .listening
            if settings.playFeedbackSounds { Sounds.startListening() }
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Stop capturing, transcribe, and deliver the result.
    public func finishDictation() async {
        guard activity == .listening else { return }

        let samples: [Float]
        do {
            samples = try recorder.stop()
        } catch {
            fail(error.localizedDescription)
            return
        }

        activity = .transcribing
        if settings.playFeedbackSounds { Sounds.stopListening() }

        do {
            let transcript = try await recognition.transcribe(samples)
            guard !transcript.text.isEmpty else {
                fail("Nothing was said.")
                return
            }

            lastTranscript = transcript.text
            try deliver(transcript.text)
            activity = .idle
            Log.app.info(
                "Dictation delivered at \(String(format: "%.0f", transcript.realtimeFactor), privacy: .public)x realtime"
            )
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Abandon the in-flight recording.
    public func cancelDictation() {
        guard activity == .listening else { return }
        recorder.cancel()
        activity = .idle
    }

    /// Toggle dictation, for the orb and for toggle-mode hotkeys.
    public func toggleDictation() async {
        switch activity {
        case .listening: await finishDictation()
        case .speaking: cancelSpeech()
        default: await startDictation()
        }
    }

    /// Route a finished transcript to wherever the user asked for it.
    private func deliver(_ text: String) throws {
        switch settings.transcriptDelivery {
        case .paste:
            try TextInjector.insert(text)
        case .clipboard:
            TextInjector.copyToClipboard(text)
        }
    }

    // MARK: - Speaking

    /// Read the frontmost application's selection aloud.
    public func speakSelection() async {
        do {
            guard let selection = try await TextInjector.readSelection() else {
                fail("Select some text first.")
                return
            }
            speak(selection)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Capture a region of the screen, read the text in it, and speak it.
    public func readScreenRegion() async {
        guard await Permissions.request(.screenRecording) else {
            fail("Screen Recording access is off. Turn it on in System Settings.")
            return
        }

        do {
            let text = try await ScreenTextReader.captureRegionAndRecognize()
            speak(text)
        } catch ScreenTextError.cancelled {
            // Pressing Escape is a decision, not a failure.
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Speak `text`, replacing anything currently being spoken.
    public func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail("There was no text to read.")
            return
        }

        cancelSpeech()
        activity = .speaking
        spokenText = trimmed

        speechTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in await self.synthesis.synthesize(
                    trimmed, rate: self.settings.speechRate)
                {
                    try Task.checkCancellation()
                    try self.player.enqueue(chunk.samples)
                }
            } catch is CancellationError {
                // Expected when the user interrupts; not a failure.
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    /// Stop speaking and discard queued audio.
    public func cancelSpeech() {
        speechTask?.cancel()
        speechTask = nil
        player.stop()
        spokenText = nil
        if activity == .speaking { activity = .idle }
    }

    /// Whether speech is currently playing, for the orb's stop affordance.
    public var isSpeaking: Bool { player.isActive }

    /// Surface a message about something the user dropped that cannot be read.
    ///
    /// Exposed so the drop target can report a rejection through the same
    /// transient-failure path as everything else, rather than inventing its own
    /// alert.
    public func reportDropRejected(_ message: String) {
        fail(message)
    }

    // MARK: - Models

    /// Load both model sets ahead of first use.
    public func preloadModels() async {
        async let recognitionReady: Void = loadRecognition()
        async let synthesisReady: Void = loadSynthesis()
        _ = await (recognitionReady, synthesisReady)
    }

    private func loadRecognition() async {
        do { _ = try await recognition.prepare() } catch {
            Log.asr.error("Preload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadSynthesis() async {
        do { _ = try await synthesis.prepare() } catch {
            Log.tts.error("Preload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeModelPhases() {
        Task { [weak self] in
            await self?.recognition.observePhase { phase in
                Task { @MainActor in self?.recognitionPhase = phase }
            }
        }
        Task { [weak self] in
            await self?.synthesis.observePhase { phase in
                Task { @MainActor in self?.synthesisPhase = phase }
            }
        }
    }

    // MARK: - Hotkeys

    private func rebindHotKeys() {
        for token in hotKeyTokens { HotKeyCenter.shared.unregister(token) }
        hotKeyTokens.removeAll()

        let center = HotKeyCenter.shared
        let pushToTalk = settings.dictationMode == .pushToTalk

        if let token = center.register(
            .dictation,
            handler: { [weak self] edge in
                guard let self else { return }
                switch (pushToTalk, edge) {
                case (true, .pressed):
                    Task { await self.startDictation() }
                case (true, .released):
                    Task { await self.finishDictation() }
                case (false, .pressed):
                    Task { await self.toggleDictation() }
                case (false, .released):
                    break
                }
            })
        {
            hotKeyTokens.append(token)
        }

        if let token = center.register(
            .speakSelection,
            handler: { [weak self] edge in
                guard let self, edge == .pressed else { return }
                // Pressing it again while speaking stops, which is what every user
                // reaches for first.
                if self.isSpeaking {
                    self.cancelSpeech()
                } else {
                    Task { await self.speakSelection() }
                }
            })
        {
            hotKeyTokens.append(token)
        }

        if let token = center.register(
            .readScreen,
            handler: { [weak self] edge in
                guard let self, edge == .pressed else { return }
                Task { await self.readScreenRegion() }
            })
        {
            hotKeyTokens.append(token)
        }
    }

    // MARK: - Failure

    private var isFailed: Bool {
        if case .failed = activity { return true }
        return false
    }

    private func fail(_ message: String) {
        Log.app.error("\(message, privacy: .public)")
        activity = .failed(message: message)
        if settings.playFeedbackSounds { Sounds.failure() }

        // Clear the badge after a beat so the orb does not sit red forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.isFailed else { return }
            self.activity = .idle
        }
    }
}

/// Short system sounds marking state changes.
///
/// Uses the built-in alert sounds rather than shipping audio assets: they
/// respect the user's alert volume and match what the rest of the OS does.
@MainActor
enum Sounds {
    static func startListening() { NSSound(named: "Tink")?.play() }
    static func stopListening() { NSSound(named: "Pop")?.play() }
    static func failure() { NSSound(named: "Funk")?.play() }
}
