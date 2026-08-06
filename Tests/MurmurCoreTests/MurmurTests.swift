import Foundation
import Testing

@testable import MurmurCore

@Suite("Murmur identity")
struct MurmurIdentityTests {

    @Test("Bundle identifier is reverse-DNS and stable")
    func bundleIdentifierIsStable() {
        // Permission grants (microphone, accessibility) are keyed on this
        // string. Changing it silently invalidates every user's grants, so it
        // is pinned by test rather than left to a refactor.
        #expect(Murmur.bundleIdentifier == "ai.loomlabs.murmur")
    }

    @Test("Support directory is created on demand")
    func supportDirectoryIsCreated() throws {
        let directory = try Murmur.supportDirectory()
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(directory.lastPathComponent == Murmur.appName)
    }

    @Test("Models directory is created on demand")
    func modelsDirectoryIsCreated() throws {
        let directory = try Murmur.modelsDirectory()
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }
}
