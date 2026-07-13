import XCTest
@testable import CadenceCore

/// Bundled exercise imagery (revenue Phase 3, D3, NFR-3). These tests are the
/// safety net that catches a half-run image pipeline — the most likely failure
/// mode of this phase — and prove the app resolves photos with no network path.
final class ExerciseImageCatalogTests: XCTestCase {

    /// Every starter exercise that advertises an `imageName` must actually have
    /// bundled photography. A miss here means the pipeline did not fully run.
    func testEveryStarterExerciseWithImageNameHasBundledImages() {
        let named = ExerciseLibrary.starter.compactMap { $0.imageName }
        XCTAssertFalse(named.isEmpty, "starter catalog should have imaged exercises")
        for name in named {
            XCTAssertTrue(ExerciseImageCatalog.hasImages(forImageName: name),
                          "missing bundled images for '\(name)' — pipeline likely half-run")
        }
    }

    /// Every returned URL is a real on-disk file resolved from Bundle.module.
    func testReturnedURLsExistOnDisk() {
        let sample = ExerciseLibrary.starter.compactMap { $0.imageName }.prefix(50)
        for name in sample {
            for url in ExerciseImageCatalog.imageURLs(forImageName: name) {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                              "no file at \(url.path)")
            }
        }
    }

    /// No returned URL is a remote URL — the whole point of NFR-3.
    func testReturnedURLsAreAllFileURLs() {
        let sample = ExerciseLibrary.starter.compactMap { $0.imageName }.prefix(50)
        for name in sample {
            for url in ExerciseImageCatalog.imageURLs(forImageName: name) {
                XCTAssertTrue(url.isFileURL, "\(url) is not a file URL")
                XCTAssertNotEqual(url.scheme, "http")
                XCTAssertNotEqual(url.scheme, "https")
            }
        }
    }

    func testUnknownImageNameReturnsEmptyAndDoesNotCrash() {
        XCTAssertEqual(ExerciseImageCatalog.imageURLs(forImageName: "definitely-not-a-real-id"), [])
        XCTAssertFalse(ExerciseImageCatalog.hasImages(forImageName: "definitely-not-a-real-id"))
    }

    func testEmptyImageNameReturnsEmpty() {
        XCTAssertEqual(ExerciseImageCatalog.imageURLs(forImageName: ""), [])
    }

    /// The bundled image count matches the number of imported exercises with
    /// imagery — guards against a truncated pipeline run (873 exercises × 2 images).
    func testBundledImageCountMatchesImportedExercisesWithImagery() {
        let importedWithImages = ImportedExerciseLibrary.templates
            .compactMap { $0.imageName }
            .filter { ExerciseImageCatalog.hasImages(forImageName: $0) }
        XCTAssertEqual(importedWithImages.count, 873,
                       "expected all 873 imported exercises to have bundled imagery")
    }

    /// The public `ExerciseLibrary.imageURLs` bridge resolves to files too, and
    /// nil / empty names are handled.
    func testExerciseLibraryBridge() {
        XCTAssertEqual(ExerciseLibrary.imageURLs(forImageName: nil), [])
        XCTAssertEqual(ExerciseLibrary.imageURLs(forImageName: ""), [])
        if let name = ExerciseLibrary.starter.compactMap({ $0.imageName }).first {
            let urls = ExerciseLibrary.imageURLs(forImageName: name)
            XCTAssertFalse(urls.isEmpty)
            XCTAssertTrue(urls.allSatisfy { $0.isFileURL })
        }
    }
}
