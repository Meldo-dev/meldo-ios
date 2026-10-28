// swift-tools-version: 6.2
// Melden: the button that records a Meldung for the running lesson.
import PackageDescription

let package = Package(
    name: "MeldoParticipation",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoParticipation", targets: ["MeldoParticipation"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoParticipation",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
