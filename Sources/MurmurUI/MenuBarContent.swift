import MurmurCore
import SwiftUI

/// Contents of the menu bar dropdown.
public struct MenuBarContent: View {

    public init() {}

    public var body: some View {
        Text("\(Murmur.appName) \(Murmur.version)")

        Divider()

        Button("Quit \(Murmur.appName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
