import MurmurCore
import SwiftUI

/// The settings window.
public struct SettingsView: View {

    @Bindable private var controller: MurmurController

    public init(controller: MurmurController) {
        self.controller = controller
    }

    public var body: some View {
        TabView {
            GeneralSettings(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }

            PermissionSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            ModelSettings(controller: controller)
                .tabItem { Label("Models", systemImage: "cpu") }
        }
        .frame(width: 460, height: 340)
    }
}

// MARK: - General

private struct GeneralSettings: View {

    @Bindable var controller: MurmurController

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Hotkey behaviour", selection: $controller.settings.dictationMode) {
                    ForEach(Settings.DictationMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                LabeledContent("Shortcut", value: KeyCombo.dictation.displayName)

                Picker("When finished", selection: $controller.settings.transcriptDelivery) {
                    ForEach(Settings.TranscriptDelivery.allCases, id: \.self) { delivery in
                        Text(delivery.title).tag(delivery)
                    }
                }
            }

            Section("Speech") {
                LabeledContent("Shortcut", value: KeyCombo.speakSelection.displayName)

                // Stepped rather than continuous: a slider that lands on 1.03×
                // is a slider that never lands on 1×.
                Slider(
                    value: $controller.settings.speechRate,
                    in: SettingsStore.speechRateRange,
                    step: 0.05
                ) {
                    Text("Rate")
                } minimumValueLabel: {
                    Text("0.5×").font(.caption)
                } maximumValueLabel: {
                    Text("2×").font(.caption)
                }

                LabeledContent("Current") {
                    Text(String(format: "%.2f×", controller.settings.speechRate))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Toggle("Show the floating orb", isOn: $controller.settings.showsOrb)
                Toggle(
                    "Play a sound when recording starts and stops",
                    isOn: $controller.settings.playFeedbackSounds)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionSettings: View {

    /// Re-read on appear rather than observed: permissions change in System
    /// Settings, outside this process, and macOS offers no change notification.
    @State private var granted: [Permission: Bool] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(
                        permission: permission,
                        isGranted: granted[permission] ?? false,
                        onRequest: { request(permission) }
                    )
                }
            } header: {
                Text("Murmur asks for each of these the first time you use the feature that needs it.")
                    .textCase(nil)
            }

            Section {
                Button("Refresh") { refresh() }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        for permission in Permission.allCases {
            granted[permission] = Permissions.isGranted(permission)
        }
    }

    private func request(_ permission: Permission) {
        Task {
            await Permissions.request(permission)
            // The Accessibility switch is flipped by hand in System Settings, so
            // the answer is rarely available immediately after the prompt.
            Permissions.openSettings(for: permission)
            refresh()
        }
    }
}

private struct PermissionRow: View {

    let permission: Permission
    let isGranted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                Text(permission.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(permission.title) granted")
            } else {
                Button("Grant…", action: onRequest)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Models

private struct ModelSettings: View {

    let controller: MurmurController

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Speech recognition", value: controller.recognitionPhase.summary)
                LabeledContent("Voice", value: controller.synthesisPhase.summary)
            }

            Section("Storage") {
                LabeledContent("Downloaded weights", value: cacheSize)
                Text(Murmur.modelsDirectory().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                Toggle(
                    "Load models at launch",
                    isOn: Binding(
                        get: { controller.settings.preloadModels },
                        set: { controller.settings.preloadModels = $0 }
                    ))
                Text(
                    "Keeps about 700 MB resident so the first dictation is instant. "
                        + "Leave this off if you dictate rarely."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Download now") {
                    Task { await controller.preloadModels() }
                }
                .disabled(controller.recognitionPhase.isBusy || controller.synthesisPhase.isBusy)
            }

            Section {
                LabeledContent("Murmur", value: Murmur.version)
            }
        }
        .formStyle(.grouped)
    }

    private var cacheSize: String {
        let bytes = Murmur.cachedModelBytes()
        guard bytes > 0 else { return "Not downloaded" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
