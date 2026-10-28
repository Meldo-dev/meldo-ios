// swift-tools-version: 6.2
// Start: the cards the student arranges, its own cards (today, week, Meldungen, streak).
import PackageDescription

let package = Package(
    name: "MeldoDashboard",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoDashboard", targets: ["MeldoDashboard"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoDashboard",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
