// swift-tools-version: 6.2
// Dokumente: scanned and imported PDFs by subject, stored in the Files app's Meldo folder.
import PackageDescription

let package = Package(
    name: "MeldoExams",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MeldoExams", targets: ["MeldoExams"]),
    ],
    dependencies: [
        .package(path: "../../MeldeCore"),
        .package(path: "../MeldoKit"),
        .package(path: "../MeldoState"),
        .package(path: "../MeldoUI"),
    ],
    targets: [
        .target(
            name: "MeldoExams",
            dependencies: ["MeldeCore", "MeldoKit", "MeldoState", "MeldoUI"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "MeldoExamsTests",
            dependencies: ["MeldoExams"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
