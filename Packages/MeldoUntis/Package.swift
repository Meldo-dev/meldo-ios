// swift-tools-version: 6.2
// WebUntis: timetable, holidays, exams, homework, news and absences from the school, and the Entschuldigung.
import PackageDescription

let package = Package(
    name: "MeldoUntis",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoUntis", targets: ["MeldoUntis"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoUntis",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "MeldoUntisTests",
            dependencies: ["MeldoUntis"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
