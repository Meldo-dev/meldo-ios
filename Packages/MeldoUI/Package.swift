// swift-tools-version: 6.2
// The design system, the rows and sheets several features show, and the feature registry
// the navigation is built from.
import PackageDescription

let package = Package(
    name: "MeldoUI",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoUI", targets: ["MeldoUI"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
    ],
    targets: [
        .target(
            name: "MeldoUI",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)
