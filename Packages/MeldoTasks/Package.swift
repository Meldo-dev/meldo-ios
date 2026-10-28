// swift-tools-version: 6.2
// Aufgaben: Hausaufgaben and to-dos, their Start cards and the task editor.
import PackageDescription

let package = Package(
    name: "MeldoTasks",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoTasks", targets: ["MeldoTasks"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoTasks",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
