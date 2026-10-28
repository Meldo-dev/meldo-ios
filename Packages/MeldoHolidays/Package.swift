// swift-tools-version: 6.2
// Ferien: the holiday list and the countdown card on Start.
import PackageDescription

let package = Package(
    name: "MeldoHolidays",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoHolidays", targets: ["MeldoHolidays"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoHolidays",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
