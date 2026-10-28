// swift-tools-version: 6.2
// The app's model: `AppData` on screen, every change saved through `mutate`, preferences,
// and the lookups several features share (timetable blocks, tasks, holidays, WebUntis extras).
// Modules keep their own state on it and hook into changes and sync merges.
import PackageDescription

let package = Package(
    name: "MeldoState",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoState", targets: ["MeldoState"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
    ],
    targets: [
        .target(
            name: "MeldoState",
            dependencies: ["MeldeCore", "MeldoKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "MeldoStateTests",
            dependencies: ["MeldoState"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
