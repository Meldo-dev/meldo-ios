// swift-tools-version: 6.2
// Microsoft Teams: assignments from the student's classes become homework.
import PackageDescription

let package = Package(
    name: "MeldoTeams",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoTeams", targets: ["MeldoTeams"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoTeams",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "MeldoTeamsTests",
            dependencies: ["MeldoTeams"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
