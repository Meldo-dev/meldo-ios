// swift-tools-version: 6.2
// Swift wrapper around the Rust core. `Generated/` and `Sources/MeldeCore/melde_ffi.swift`
// are produced by scripts/build-rust-ios.sh on macOS and are not committed.
import PackageDescription

let package = Package(
    name: "MeldeCore",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldeCore", targets: ["MeldeCore"]),
    ],
    targets: [
        .binaryTarget(name: "MeldeFFI", path: "Generated/MeldeFFI.xcframework"),
        .target(
            name: "MeldeCore",
            dependencies: ["MeldeFFI"],
            path: "Sources/MeldeCore",
            // UniFFI emits Swift 5-style globals; the app itself builds in Swift 6 mode.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MeldeCoreTests",
            dependencies: ["MeldeCore"],
            path: "Tests/MeldeCoreTests"
        ),
    ]
)
