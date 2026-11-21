import Testing
import Foundation
import CadencePhoneFeatures

/// Structural guard: Home render functions must read only precomputed value
/// snapshots / UI state, never live persistence or history traversal.
/// Scope is deliberately limited to three bodies; there are no allowlist entries.
struct HomeRenderPathGuardTests {
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
        let range = try #require(text.range(of: marker), "\(marker) not found in \(file)")
        var depth = 0, started = false
        var out = ""
        for ch in text[range.upperBound...] {
            if ch == "{" { depth += 1; started = true }
            if started { out.append(ch) }
            if ch == "}" { depth -= 1; if started && depth == 0 { break } }
        }
        #expect(!out.isEmpty, "empty body for \(marker)")
        return out
    }

    private func assertClean(_ marker: String, file: String) throws {
        let source = try body(of: marker, in: file)
            .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for token in Self.forbidden {
            let pattern = "\\b\(token)\\b"
            #expect(source.range(of: pattern, options: .regularExpression) == nil,
                         "\(marker) in \(file) references forbidden persistence API `\(token)`")
        }
    }

    @Test func makeDashboardHasNoPersistenceTraversal() throws {
        try assertClean("func makeDashboard()", file: "HomeView.swift")
    }

    @Test func todayHeroCardHasNoPersistenceTraversal() throws {
        try assertClean("private var todayHeroCard: some View", file: "HomeView+DashboardContent.swift")
    }

    @Test func muscleMapBodyHasNoPersistenceTraversal() throws {
        try assertClean("var body: some View", file: "HomeMuscleMapView.swift")
    }

    /// The muscle list used to be a disabled `List` nested inside the Home
    /// scroll view. Nested scroll containers make Home scrolling stutter, so
    /// the list must remain plain rows laid out by the outer scroll view.
    @Test func muscleListNeverNestsASecondScrollContainer() throws {
        let source = try body(of: "private var muscleList: some View", in: "HomeMuscleMapView.swift")
        #expect(source.range(of: "\\bList\\s*\\{", options: .regularExpression) == nil,
                "Home must not embed a List inside its ScrollView")
        #expect(!source.contains(".scrollDisabled"))
    }

    /// Both Home entry points into the start-mode picker (the Start Workout
    /// sheet and the Cardio tile sheet) pass the already-published dashboard
    /// credit rather than letting the picker compute its own. The lowercase
    /// `cardio` token is excluded below because SF Symbols names it directly
    /// (the "Other" row's "figure.mixed.cardio" icon) — every real
    /// persistence/HealthKit/aggregation API token is still banned.
    @Test func fullCardioCatalogHasNoPersistenceTraversal() throws {
        let file = "CardioTypePickerView.swift"
        let source = try body(of: "var body: some View", in: file)
            .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for token in Self.forbidden where token != "cardio" {
            let pattern = "\\b\(token)\\b"
            #expect(source.range(of: pattern, options: .regularExpression) == nil,
                         "body in \(file) references forbidden persistence API `\(token)`")
        }
    }
}
