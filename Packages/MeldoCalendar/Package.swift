// swift-tools-version: 6.2
// Kalender: exams, tasks, absences and Meldungen by day.
import PackageDescription

let package = Package(
    name: "MeldoCalendar",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoCalendar", targets: ["MeldoCalendar"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoCalendar",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
