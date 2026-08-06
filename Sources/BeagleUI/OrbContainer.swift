import BeagleCore
import SwiftUI
import UniformTypeIdentifiers

/// Wraps ``OrbView`` with the drag-and-drop behaviour that makes it a target.
///
/// Dropping is the whole reason the orb is a window rather than a menu bar
/// glyph: you can drag a paragraph out of any document and let go over the orb
/// to hear it read back.
public struct OrbContainer: View {

    /// Largest file Beagle will read off a drop.
    ///
    /// Well past any realistic article, and short of the point where synthesis
    /// would run for an hour on an accidental drop of the wrong file.
    private static let maximumDroppedBytes = 512 * 1024

    // `@Observable` gives SwiftUI dependency tracking on plain property reads,
    // so no property wrapper is needed for a view that only observes.
    private let controller: BeagleController
    @State private var isTargeted = false

    public init(controller: BeagleController) {
        self.controller = controller
    }

    public var body: some View {
        OrbView(
            activity: controller.activity,
            style: controller.settings.orbStyle,
            inputLevel: { controller.inputLevel },
            isTargeted: isTargeted
        ) {
            Task { await controller.toggleDictation() }
        }
        .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// Read the first usable provider and speak it.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Plain text first: dragging a selection offers both text and, in some
        // apps, a file URL for the containing document. Text is what was meant.
        if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text else { return }
                Task { @MainActor in controller.speak(text) }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in speakContents(of: url) }
            }
            return true
        }

        return false
    }

    /// Read a dropped file, refusing anything that is not plain text.
    @MainActor
    private func speakContents(of url: URL) {
        let readableTypes: Set<String> = ["txt", "md", "markdown", "text", "log", "csv", "json"]
        guard readableTypes.contains(url.pathExtension.lowercased()) else {
            controller.reportDropRejected("Beagle can read plain text files — try a .txt or .md.")
            return
        }

        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumDroppedBytes else {
                controller.reportDropRejected("That file is too long to read aloud.")
                return
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            controller.speak(text)
        } catch {
            controller.reportDropRejected("Could not read that file.")
        }
    }
}
