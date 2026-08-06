// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Murmur", targets: ["MurmurApp"]),
        .library(name: "MurmurCore", targets: ["MurmurCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5")
    ],
    targets: [
        // Domain layer: audio, speech engines, settings. No UI, no AppKit chrome.
        .target(
            name: "MurmurCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        // Presentation layer: SwiftUI views and view models.
        .target(
            name: "MurmurUI",
            dependencies: ["MurmurCore"]
        ),
        // Application shell: lifecycle, hotkeys, windows.
        .executableTarget(
            name: "MurmurApp",
            dependencies: ["MurmurCore", "MurmurUI"]
        ),
        .testTarget(
            name: "MurmurCoreTests",
            dependencies: ["MurmurCore"]
        ),
    ]
)
