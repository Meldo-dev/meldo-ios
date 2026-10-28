// swift-tools-version: 6.2
// Statistik: Meldungen per day, per subject and over the weeks.
import PackageDescription

let package = Package(
    name: "MeldoStatistics",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoStatistics", targets: ["MeldoStatistics"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoStatistics",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
