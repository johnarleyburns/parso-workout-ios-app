import XCTest
import CadenceCore
@testable import CadenceExerciseImages

/// Guards the iPhone-only image pipeline without forcing the Watch target to
/// embed the full catalog through CadenceCore.
final class ExerciseImageCatalogTests: XCTestCase {

    func testEveryImportedExerciseWithImageNameHasBundledImages() {
        let named = ImportedExerciseLibrary.templates.compactMap(\.imageName)
        XCTAssertFalse(named.isEmpty, "imported catalog should have imaged exercises")
        for name in named {
            XCTAssertTrue(ExerciseImageCatalog.hasImages(forImageName: name),
                          "missing bundled images for '\(name)'")
        }
    }

    func testReturnedURLsExistAndAreLocal() {
        let sample = ImportedExerciseLibrary.templates.compactMap(\.imageName).prefix(50)
        for name in sample {
            for url in ExerciseImageCatalog.imageURLs(forImageName: name) {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                XCTAssertTrue(url.isFileURL)
                XCTAssertNotEqual(url.scheme, "http")
                XCTAssertNotEqual(url.scheme, "https")
            }
        }
    }

    func testUnknownAndEmptyImageNamesReturnEmpty() {
        XCTAssertEqual(ExerciseImageCatalog.imageURLs(forImageName: "definitely-not-a-real-id"), [])
        XCTAssertFalse(ExerciseImageCatalog.hasImages(forImageName: "definitely-not-a-real-id"))
        XCTAssertEqual(ExerciseImageCatalog.imageURLs(forImageName: ""), [])
    }

    func testBundledImageCountMatchesImportedExercisesWithImagery() {
        let importedWithImages = ImportedExerciseLibrary.templates
            .compactMap(\.imageName)
            .filter { ExerciseImageCatalog.hasImages(forImageName: $0) }
        XCTAssertEqual(importedWithImages.count, 873)
    }

    func testExerciseLibraryBridge() {
        XCTAssertEqual(ExerciseLibrary.imageURLs(forImageName: nil), [])
        XCTAssertEqual(ExerciseLibrary.imageURLs(forImageName: ""), [])
        let name = try! XCTUnwrap(ExerciseLibrary.starter.compactMap(\.imageName).first)
        XCTAssertFalse(ExerciseLibrary.imageURLs(forImageName: name).isEmpty)
    }
}
