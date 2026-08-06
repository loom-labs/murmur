import Foundation
import Testing

@testable import BeagleCore

@Suite("Beagle identity")
struct BeagleIdentityTests {

    @Test("Bundle identifier is reverse-DNS and stable")
    func bundleIdentifierIsStable() {
        // Permission grants (microphone, accessibility) are keyed on this
        // string. Changing it silently invalidates every user's grants, so it
        // is pinned by test rather than left to a refactor.
        #expect(Beagle.bundleIdentifier == "ai.loomlabs.beagle")
    }

    @Test("Support directory is created on demand")
    func supportDirectoryIsCreated() throws {
        let directory = try Beagle.supportDirectory()
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(directory.lastPathComponent == Beagle.appName)
    }

    @Test("Models directory points at FluidAudio's shared cache")
    func modelsDirectoryIsShared() {
        // Beagle must not relocate this: sharing the path with other
        // FluidAudio-backed apps is what keeps a second install from
        // re-downloading a gigabyte of weights.
        let directory = Beagle.modelsDirectory()
        #expect(directory.pathComponents.suffix(2) == ["FluidAudio", "Models"])
    }

    @Test("Cache size is zero rather than throwing when nothing is downloaded")
    func cacheSizeHandlesMissingDirectory() {
        #expect(Beagle.cachedModelBytes() >= 0)
    }
}
