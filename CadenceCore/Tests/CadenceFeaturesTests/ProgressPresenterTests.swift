import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceFixtures

@MainActor
final class ProgressPresenterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testStrengthSeriesFromSeededHistory() throws {
        let ctx = try makeContext()
        Fixtures.history(into: ctx)
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        let series = ProgressPresenter.strengthSeries(sessions: sessions, formula: .epley)
        XCTAssertTrue(series.contains { $0.exercise == "Bench Press" })
        XCTAssertTrue(series.contains { $0.exercise == "Back Squat" })
    }

    func testTrendLabel() {
        XCTAssertEqual(ProgressPresenter.trendLabel(.rising, delta: 5, unit: .kilograms), "up 5 kg")
        XCTAssertEqual(ProgressPresenter.trendLabel(.declining, delta: -5, unit: .kilograms), "down 5 kg")
        XCTAssertEqual(ProgressPresenter.trendLabel(.flat, delta: 0, unit: .kilograms), "no change")
    }

    func testStrengthTrendSummaryEmpty() {
        XCTAssertEqual(ProgressPresenter.strengthTrendSummary(series: [], unit: .kilograms),
                       "No lifts tracked yet.")
    }

    func testStrengthTrendSummaryCountsTrackedLifts() {
        let pts = [E1RMPoint(weekStart: Date(timeIntervalSince1970: 0), e1rm: 100),
                   E1RMPoint(weekStart: Date(timeIntervalSince1970: 7 * 86_400), e1rm: 110)]
        let series = [E1RMSeries(exercise: "Bench Press", points: pts)]
        let summary = ProgressPresenter.strengthTrendSummary(series: series, unit: .kilograms)
        XCTAssertTrue(summary.hasPrefix("1 lifts tracked."))
        XCTAssertTrue(summary.contains("Bench Press"))
    }

    func testIntensityReadStrength() {
        let heavy = IntensityDistribution(heavy: 0.6, moderate: 0.3, light: 0.1, sampleCount: 10)
        let light = IntensityDistribution(heavy: 0.1, moderate: 0.3, light: 0.6, sampleCount: 10)
        XCTAssertTrue(ProgressPresenter.intensityRead(heavy, goal: .strength).contains("aligned"))
        XCTAssertTrue(ProgressPresenter.intensityRead(light, goal: .strength).contains("Lighter"))
    }

    func testEffortReadInRange() {
        let target = Double(TrainingGoal.strength.targetRIR)
        let read = ProgressPresenter.effortRead(target, goal: .strength)
        XCTAssertEqual(read, "In the effective range for \(TrainingGoal.strength.displayName.lowercased()).")
    }

    func testEffortReadTooFarFromFailure() {
        let target = Double(TrainingGoal.strength.targetRIR)
        let read = ProgressPresenter.effortRead(target + 2, goal: .strength)
        XCTAssertTrue(read.contains("further from failure"))
    }
}
