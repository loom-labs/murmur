// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hugo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hugo", targets: ["HugoApp"]),
        .library(name: "HugoCore", targets: ["HugoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5")
    ],
    targets: [
        // Domain layer: audio, speech engines, settings. No UI, no AppKit chrome.
        .target(
            name: "HugoCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        // Presentation layer: SwiftUI views and view models.
        .target(
            name: "HugoUI",
            dependencies: ["HugoCore"]
        ),
        // Application shell: lifecycle, hotkeys, windows.
        .executableTarget(
            name: "HugoApp",
            dependencies: ["HugoCore", "HugoUI"]
        ),
        .testTarget(
            name: "HugoCoreTests",
            dependencies: ["HugoCore"]
        ),
    ]
)
