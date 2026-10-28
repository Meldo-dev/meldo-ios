// swift-tools-version: 6.2
// Stundenplan: the week laid out like WebUntis, and the lesson editor.
import PackageDescription

let package = Package(
    name: "MeldoTimetable",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoTimetable", targets: ["MeldoTimetable"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoTimetable",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
