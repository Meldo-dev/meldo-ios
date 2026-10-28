// swift-tools-version: 6.2
// The first-run tour.
import PackageDescription

let package = Package(
    name: "MeldoOnboarding",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoOnboarding", targets: ["MeldoOnboarding"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoOnboarding",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
