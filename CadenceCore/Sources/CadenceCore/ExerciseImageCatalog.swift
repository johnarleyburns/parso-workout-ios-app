import Foundation

/// Bundled exercise photography. Resolves entirely from `Bundle.module` — there
/// is no network path, by design (NFR-3), and `scripts/check-no-network.sh`
/// fails CI if one is ever reintroduced.
///
/// Images are downscaled HEICs produced once by
/// `scripts/build-exercise-images.sh` from free-exercise-db at the same pinned
/// commit as `free-exercise-db.json`, laid out as
/// `Resources/ExerciseImages/<imageName>/{0,1}.heic`. The `<imageName>` key is the
/// same id stored on `ExerciseTemplate.imageName` / `Exercise.imageName`.
public enum ExerciseImageCatalog {

    /// The two image positions bundled per exercise, in display order.
    static let positions = [0, 1]

    /// Local file URLs for an exercise's bundled images, in display order.
    /// Empty when the exercise has no bundled photography.
    public static func imageURLs(forImageName name: String) -> [URL] {
        guard !name.isEmpty else { return [] }
        return positions.compactMap { position in
            Bundle.module.url(forResource: "\(position)",
                              withExtension: "heic",
                              subdirectory: "ExerciseImages/\(name)")
        }
    }

    public static func hasImages(forImageName name: String) -> Bool {
        !imageURLs(forImageName: name).isEmpty
    }
}
