import XCTest
import Foundation

/// Structural guard: Home render functions must read only precomputed value
/// snapshots / UI state, never live persistence or history traversal.
/// Scope is deliberately limited to three bodies; there are no allowlist entries.
final class HomeRenderPathGuardTests: XCTestCase {
    private static let forbidden = [
        "WorkoutRepository", "ModelContext", "orderedHRSamples", "hrSamplePoints", "orderedSets",
        "WeeklyStrengthAggregator", "WeeklyCardioAggregator", "WeeklyActivityDoseAggregator",
        "WorkoutDurationEstimator", "sessions", "cardio", "scheduledWorkouts", "FetchDescriptor"
    ]

    private var featuresDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cadence/Cadence/Features/Home")
    }

    /// Extracts the brace-balanced body following `marker`.
    private func body(of marker: String, in file: String) throws -> String {
        let text = try String(contentsOf: featuresDir.appendingPathComponent(file), encoding: .utf8)
        let range = try XCTUnwrap(text.range(of: marker), "\(marker) not found in \(file)")
        var depth = 0, started = false
        var out = ""
        for ch in text[range.upperBound...] {
            if ch == "{" { depth += 1; started = true }
            if started { out.append(ch) }
            if ch == "}" { depth -= 1; if started && depth == 0 { break } }
        }
        XCTAssertFalse(out.isEmpty, "empty body for \(marker)")
        return out
    }

    private func assertClean(_ marker: String, file: String) throws {
        let source = try body(of: marker, in: file)
            .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for token in Self.forbidden {
            let pattern = "\\b\(token)\\b"
            XCTAssertNil(source.range(of: pattern, options: .regularExpression),
                         "\(marker) in \(file) references forbidden persistence API `\(token)`")
        }
    }

    func testMakeDashboardHasNoPersistenceTraversal() throws {
        try assertClean("func makeDashboard()", file: "HomeView.swift")
    }

    func testTodayHeroCardHasNoPersistenceTraversal() throws {
        try assertClean("private var todayHeroCard: some View", file: "HomeView+DashboardContent.swift")
    }

    func testMuscleMapBodyHasNoPersistenceTraversal() throws {
        try assertClean("var body: some View", file: "HomeMuscleMapView.swift")
    }
}
