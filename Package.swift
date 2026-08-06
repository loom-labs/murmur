// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Beagle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Beagle", targets: ["BeagleApp"]),
        .library(name: "BeagleCore", targets: ["BeagleCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5")
    ],
    targets: [
        // Domain layer: audio, speech engines, settings. No UI, no AppKit chrome.
        .target(
            name: "BeagleCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        // Presentation layer: SwiftUI views and view models.
        .target(
            name: "BeagleUI",
            dependencies: ["BeagleCore"]
        ),
        // Application shell: lifecycle, hotkeys, windows.
        .executableTarget(
            name: "BeagleApp",
            dependencies: ["BeagleCore", "BeagleUI"]
        ),
        .testTarget(
            name: "BeagleCoreTests",
            dependencies: ["BeagleCore"]
        ),
    ]
)
