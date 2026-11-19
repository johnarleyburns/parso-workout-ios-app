// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CadenceCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .watchOS(.v11),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CadenceWorkoutFeatures", targets: ["CadenceWorkoutFeatures"]),
        .library(name: "CadencePhoneFeatures", targets: ["CadencePhoneFeatures"]),
        .library(name: "CadencePortability", targets: ["CadencePortability"]),
        .library(name: "CadenceCore", targets: ["CadenceCore"]),
        // Foundation-only planning domain; builds and tests on Linux.
        .library(name: "CadencePlanning", targets: ["CadencePlanning"]),
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
            exact: "1.19.0"
        )
    ],
    targets: [
        // Foundation ONLY — never SwiftUI, SwiftData, HealthKit, UIKit,
        // WatchConnectivity, CoreLocation, StoreKit, or app model types.
        .target(name: "CadencePortability", dependencies: [
            "CadenceCore",
            .product(name: "FreeExerciseDBPlusPlus", package: "free-exercise-db-plusplus"),
            .product(name: "FreeExerciseDBPlusPlusFIT", package: "free-exercise-db-plusplus")
        ], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CadencePortabilityTests", dependencies: ["CadencePortability"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "CadencePlanning", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "CadenceCore",
            dependencies: [
                "CadencePlanning",
                .product(
                    name: "FreeExerciseDBPlusPlus",
                    package: "free-exercise-db-plusplus"
                )
            ],
            resources: [
                // Versioned Coach knowledge-base changelog (quarterly protocol packs).
                .copy("Resources/coach-kb-version.json"),
                // DB++ names remain the canonical identifiers; this sidecar is
                // the user-facing localized label layer.
                .copy("Resources/exercise-names.i18n.json"),
                // UI copy produced by Core (labels, summaries, errors), looked
                // up with `bundle: .module`.
                .process("Resources/Localizable.xcstrings"),
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
        .target(
            name: "CadenceFeatures",
            dependencies: [],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(name: "CadenceWorkoutFeatures", dependencies: ["CadenceCore", "CadenceFeatures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        // Phone-only dashboards, backup/export, assessment presentation and
        // full plan editing. Never linked into the Watch target.
        .target(name: "CadencePhoneFeatures",
                dependencies: ["CadenceCore", "CadenceFeatures", "CadenceWorkoutFeatures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CadencePlatformTests", dependencies: ["CadenceFeatures"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "CadenceFixtures", dependencies: ["CadenceCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CadencePlanningTests",
            dependencies: ["CadencePlanning"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "CadenceCoreTests", dependencies: [
            "CadencePlanning", "CadenceCore", "CadenceFeatures", "CadenceExerciseImages",
            // Only WeightSuggestionTests.swift needs this, and that file is
            // itself `#if canImport(SwiftData)`-gated (Apple platforms only),
            // so CadenceWorkoutFeatures need not build on Linux for the rest
            // of this target's 83 SwiftData-free tests to compile and run.
            .target(name: "CadenceWorkoutFeatures", condition: .when(platforms: [.iOS, .macOS, .watchOS])),
        ], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CadenceExerciseImagesTests",
            dependencies: ["CadenceCore", "CadenceExerciseImages"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CadenceFeaturesTests",
            dependencies: ["CadenceFeatures", "CadenceWorkoutFeatures", "CadencePhoneFeatures", "CadenceFixtures"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
