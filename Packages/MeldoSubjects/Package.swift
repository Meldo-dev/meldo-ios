// swift-tools-version: 6.2
// Fächer: the subject list and editor.
import PackageDescription

let package = Package(
    name: "MeldoSubjects",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoSubjects", targets: ["MeldoSubjects"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoSubjects",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
