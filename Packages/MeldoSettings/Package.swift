// swift-tools-version: 6.2
// Einstellungen, Status and Über Meldo.
import PackageDescription

let package = Package(
    name: "MeldoSettings",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoSettings", targets: ["MeldoSettings"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoSettings",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
