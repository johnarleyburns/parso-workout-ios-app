// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CadenceCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CadenceCore", targets: ["CadenceCore"]),
        // Headless app logic lifted out of SwiftUI Views so `swift test` can
        // exercise it without a simulator (test-pyramid plan, 2026-07-12).
        .library(name: "CadenceFeatures", targets: ["CadenceFeatures"]),
        // Shared deterministic seed catalog for previews + tests.
        .library(name: "CadenceFixtures", targets: ["CadenceFixtures"])
    ],
    targets: [
        .target(
            name: "CadenceCore",
            resources: [
                // Public-domain (Unlicense) exercise data from free-exercise-db,
                // vendored at pinned commit b0eed06 (see CREDITS.md). Transformed
                // on-device into our taxonomy by `ImportedExerciseLibrary`.
                // Images loaded at runtime from raw.githubusercontent.com.
                .copy("Resources/free-exercise-db.json"),
                // Versioned Coach knowledge-base changelog (quarterly protocol packs).
                .copy("Resources/coach-kb-version.json"),
            ]
        ),
        // Foundation + SwiftData + Observation ONLY. No SwiftUI, no HealthKit,
        // no StoreKit, no UIKit — that is what keeps it testable on macOS.
        .target(name: "CadenceFeatures", dependencies: ["CadenceCore"]),
        .target(name: "CadenceFixtures", dependencies: ["CadenceCore"]),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"]),
        .testTarget(
            name: "CadenceFeaturesTests",
            dependencies: ["CadenceFeatures", "CadenceFixtures"]
        )
    ]
)
