import Foundation
import Testing

/// Static guard: live workout UI must reflow at accessibility Dynamic Type
/// sizes rather than shrink text with `minimumScaleFactor < 1` (issue #259).
@Suite struct LiveWorkoutReflowGuardTests {
    private static var featuresDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cadence/Cadence/Features")
    }

    @Test func liveWorkoutRootsDoNotShrinkText() throws {
        let features = Self.featuresDir
        var files: [URL] = [features.appendingPathComponent("Shared/WorkoutElapsedHeader.swift")]
        for dir in ["Train", "Intervals"] {
            let enumerator = FileManager.default.enumerator(at: features.appendingPathComponent(dir),
                                                            includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift" { files.append(url) }
            }
        }
        let app = features.deletingLastPathComponent()
        for rel in ["Coach/CoachDecisionCardView.swift", "Coach/CoachRow.swift",
                    "Home/HomeTodayHeroCard.swift", "Home/MuscleFocusThumbnail.swift",
                    "Progress/ProgressStrengthChartView.swift"] {
            files.append(features.appendingPathComponent(rel))
        }
        files.append(app.appendingPathComponent("App/RootTabView.swift"))
        #expect(files.count > 7)
        let pattern = try Regex(#"minimumScaleFactor\(\s*(0?\.\d+|0)\s*\)"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.firstMatch(of: pattern) == nil,
                    "\(file.lastPathComponent) shrinks text with minimumScaleFactor < 1")
        }
    }

    /// Issue #305: every Watch source file must reflow, not shrink text.
    @Test func watchSourcesDoNotShrinkText() throws {
        let watchDir = Self.featuresDir.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cadence Watch App Watch App")
        let enumerator = FileManager.default.enumerator(at: watchDir, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL { if url.pathExtension == "swift" { files.append(url) } }
        #expect(files.count > 10)
        let pattern = try Regex(#"minimumScaleFactor\(\s*(0?\.\d+|0)\s*\)"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.firstMatch(of: pattern) == nil,
                    "\(file.lastPathComponent) shrinks text with minimumScaleFactor < 1")
        }
    }
}
