// swift-tools-version: 6.2
// Data shared by the app and the widgets: models (`AppData`), the local store, sync merge,
// localization, the Rust engine glue, check-ins and the Live Activity.
import PackageDescription

let package = Package(
    name: "MeldoKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoKit", targets: ["MeldoKit"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
    ],
    targets: [
        .target(
            name: "MeldoKit",
            dependencies: ["MeldeCore"],
            // Not main-actor by default: widgets and intents use these types off the main thread.
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "MeldoKitTests",
            dependencies: ["MeldoKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
