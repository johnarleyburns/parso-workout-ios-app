import Foundation
import Testing
import CadenceCore
@testable import CadenceExerciseImages

/// Guards the iPhone-only image pipeline without forcing the Watch target to
/// embed the full catalog through CadenceCore.
struct ExerciseImageCatalogTests {

    @Test func everyImportedExerciseWithImageNameHasBundledImages() {
        let named = ImportedExerciseLibrary.templates.compactMap(\.imageName)
        #expect(!named.isEmpty, "imported catalog should have imaged exercises")
        for name in named {
            #expect(ExerciseImageCatalog.hasImages(forImageName: name),
                          "missing bundled images for '\(name)'")
        }
    }

    @Test func returnedURLsExistAndAreLocal() {
        let sample = ImportedExerciseLibrary.templates.compactMap(\.imageName).prefix(50)
        for name in sample {
            for url in ExerciseImageCatalog.imageURLs(forImageName: name) {
                #expect(FileManager.default.fileExists(atPath: url.path))
                #expect(url.isFileURL)
                #expect(url.scheme != "http")
                #expect(url.scheme != "https")
            }
        }
    }

    @Test func unknownAndEmptyImageNamesReturnEmpty() {
        #expect(ExerciseImageCatalog.imageURLs(forImageName: "definitely-not-a-real-id") == [])
        #expect(!ExerciseImageCatalog.hasImages(forImageName: "definitely-not-a-real-id"))
        #expect(ExerciseImageCatalog.imageURLs(forImageName: "") == [])
    }

    @Test func bundledImageCountMatchesImportedExercisesWithImagery() {
        let importedWithImages = ImportedExerciseLibrary.templates
            .compactMap(\.imageName)
            .filter { ExerciseImageCatalog.hasImages(forImageName: $0) }
        #expect(importedWithImages.count == 873)
    }

    @Test func exerciseLibraryBridge() throws {
        #expect(ExerciseLibrary.imageURLs(forImageName: nil) == [])
        #expect(ExerciseLibrary.imageURLs(forImageName: "") == [])
        let name = try #require(ExerciseLibrary.starter.compactMap(\.imageName).first)
        #expect(!ExerciseLibrary.imageURLs(forImageName: name).isEmpty)
    }
}
