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

    /// Issue #619: the Cardio picker renders an injected, value-only weekly
    /// credit display. The whole file is scanned (not one body) so no helper
    /// view can aggregate, fetch, or reach HealthKit either. The lowercase
    /// `cardio` / `sessions` tokens above name HomeView's `@Query` arrays and
    /// are left out here because the picker's own user copy says "cardio";
    /// every persistence/HealthKit/aggregation API token is still banned.
    func testCardioPickerConsumesInjectedCreditWithoutAggregationFetchOrHealthKit() throws {
        let file = "CardioPickerView.swift"
        let source = try String(contentsOf: featuresDir.appendingPathComponent(file), encoding: .utf8)
            .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let forbidden = Self.forbidden.filter { $0 != "cardio" && $0 != "sessions" } + [
            "AppModel", "HealthKit", "HKHealthStore", "HKQuery", "HKSampleQuery", "health",
            "Query", "modelContext", "WeeklyCardioSummary", "summarize",
            "HomeDashboardState", "HomeDashboardPresenter", "CardioWeeklyCreditPresenter"
        ]
        for token in forbidden {
            XCTAssertNil(source.range(of: "\\b\(token)\\b", options: .regularExpression),
                         "\(file) references forbidden render-path API `\(token)`")
        }
        XCTAssertNotNil(source.range(of: "\\bCardioWeeklyCreditDisplay\\b", options: .regularExpression),
                        "\(file) must render the injected CardioWeeklyCreditDisplay value")
        XCTAssertNotNil(source.range(of: "\\bCardioPickerLayoutPresenter\\b", options: .regularExpression),
                        "\(file) must take its section order from CardioPickerLayoutPresenter")
    }

    /// Both Home entry points into the start-mode picker (the Start Workout
    /// sheet and the Cardio tile sheet) pass the already-published dashboard
    /// credit rather than letting the picker compute its own.
    func testHomeCardioPickerEntryPointsInjectTheCachedDashboardCredit() throws {
        let text = try String(contentsOf: featuresDir.appendingPathComponent("HomeView+Dashboard.swift"),
                              encoding: .utf8)
        let injection = "CardioWeeklyCreditPresenter.make(detail: dashboard.cardioDetail)"
        XCTAssertEqual(text.components(separatedBy: injection).count - 1, 2,
                       "SelectWorkoutView and the Cardio tile CardioPickerView must both inject \(injection)")
    }
}
