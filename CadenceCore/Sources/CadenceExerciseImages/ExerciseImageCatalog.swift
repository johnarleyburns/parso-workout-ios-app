import Foundation
import CadenceCore

/// The iPhone-only exercise photography catalog. It is deliberately a separate
/// target so the shared Core/Features targets can be linked by the Watch app
/// without embedding the full image catalog in its bundle.
public enum ExerciseImageCatalog {

    private static let positions = [0, 1]

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

public extension ExerciseLibrary {
    /// Local iPhone exercise-photo URLs. The Watch has its own smaller catalog.
    static func imageURLs(forImageName name: String?) -> [URL] {
        guard let name, !name.isEmpty else { return [] }
        return ExerciseImageCatalog.imageURLs(forImageName: name)
    }
}
