// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CadenceCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v11),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CadenceCore", targets: ["CadenceCore"]),
        .library(name: "CadenceExerciseImages", targets: ["CadenceExerciseImages"]),
        // Headless app logic lifted out of SwiftUI Views so `swift test` can
        // exercise it without a simulator (test-pyramid plan, 2026-07-12).
        .library(name: "CadenceFeatures", targets: ["CadenceFeatures"]),
        // Shared deterministic seed catalog for previews + tests.
        .library(name: "CadenceFixtures", targets: ["CadenceFixtures"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/johnarleyburns/free-exercise-db-plusplus.git",
            exact: "1.17.1"
        )
    ],
    targets: [
        .target(
            name: "CadenceCore",
            dependencies: [
                .product(
                    name: "FreeExerciseDBPlusPlus",
                    package: "free-exercise-db-plusplus"
                )
            ],
            resources: [
                // Versioned Coach knowledge-base changelog (quarterly protocol packs).
                .copy("Resources/coach-kb-version.json"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CadenceExerciseImages",
            dependencies: ["CadenceCore"],
            resources: [.copy("Resources/ExerciseImages")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Foundation + SwiftData + Observation ONLY. No SwiftUI, no HealthKit,
        // no StoreKit, no UIKit — that is what keeps it testable on macOS.
        .target(name: "CadenceFeatures", dependencies: ["CadenceCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "CadenceFixtures", dependencies: ["CadenceCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore", "CadenceFeatures", "CadenceExerciseImages"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CadenceExerciseImagesTests",
            dependencies: ["CadenceCore", "CadenceExerciseImages"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CadenceFeaturesTests",
            dependencies: ["CadenceFeatures", "CadenceFixtures"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
