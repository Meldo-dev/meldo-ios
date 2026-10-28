// swift-tools-version: 6.2
// Google Drive: sync between the student's devices and an encrypted backup.
import PackageDescription

let package = Package(
    name: "MeldoDrive",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoDrive", targets: ["MeldoDrive"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoDrive",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "MeldoDriveTests",
            dependencies: ["MeldoDrive"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
