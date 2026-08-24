// swift-tools-version: 6.0
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
                // Public-domain (Unlicense) exercise data from free-exercise-db++
                // (schema 0.3.0, see CREDITS.md): an evidence-audited annotation
                // layer that carries every free-exercise-db record verbatim under
                // `source` and adds muscle roles, volume eligibility, movement
                // classification and per-pattern literature references. Decoded by
                // `ExerciseDatabase` and transformed by `ImportedExerciseLibrary`.
                .copy("Resources/free-exercise-db-plusplus.json"),
                .copy("Resources/free-exercise-db-plusplus.LICENSE"),
                // Bundled exercise photography, downscaled to HEIC by
                // scripts/build-exercise-images.sh from free-exercise-db at pinned
                // commit b0eed06 — the same upstream data DB++ carries in `source`. Loaded from
                // Bundle.module — there is NO runtime network path (NFR-3), enforced
                // by scripts/check-no-network.sh.
                .copy("Resources/ExerciseImages"),
                // Versioned Coach knowledge-base changelog (quarterly protocol packs).
                .copy("Resources/coach-kb-version.json"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Foundation + SwiftData + Observation ONLY. No SwiftUI, no HealthKit,
        // no StoreKit, no UIKit — that is what keeps it testable on macOS.
        .target(name: "CadenceFeatures", dependencies: ["CadenceCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "CadenceFixtures", dependencies: ["CadenceCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CadenceFeaturesTests",
            dependencies: ["CadenceFeatures", "CadenceFixtures"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
