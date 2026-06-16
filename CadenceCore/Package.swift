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
        .library(name: "CadenceCore", targets: ["CadenceCore"])
    ],
    targets: [
        .target(
            name: "CadenceCore",
            resources: [
                // Public-domain (Unlicense) exercise data from free-exercise-db,
                // vendored at pinned commit b0eed06 (see CREDITS.md). Transformed
                // on-device into our taxonomy by `ImportedExerciseLibrary`.
                .copy("Resources/free-exercise-db.json"),
                // Public-domain demonstration images (downscaled to 400px), one per
                // exercise id, loaded on-device via `ExerciseLibrary.imageURL`.
                .copy("Resources/exercise-images")
            ]
        ),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"])
    ]
)
