// swift-tools-version: 6.2
// Noten: the student's own grades, averaged by the Rust core with the configured scale and weights.
import PackageDescription

let package = Package(
    name: "MeldoGrades",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoGrades", targets: ["MeldoGrades"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoGrades",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "MeldoGradesTests",
            dependencies: ["MeldoGrades"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
