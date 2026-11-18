#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadenceFixtures
import CadencePhoneFeatures

@MainActor
struct ProgressPresenterTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test func strengthSeriesFromSeededHistory() throws {
        let ctx = try makeContext()
        Fixtures.history(into: ctx)
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        let series = ProgressPresenter.strengthSeries(sessions: sessions, formula: .epley)
        #expect(series.contains { $0.exercise == "Bench Press" })
        #expect(series.contains { $0.exercise == "Back Squat" })
    }

    @Test func trendLabel() {
        #expect(ProgressPresenter.trendLabel(.rising, delta: 5, unit: .kilograms) == "up 5 kg")
        #expect(ProgressPresenter.trendLabel(.declining, delta: -5, unit: .kilograms) == "down 5 kg")
        #expect(ProgressPresenter.trendLabel(.flat, delta: 0, unit: .kilograms) == "no change")
    }

    @Test func strengthTrendSummaryEmpty() {
        #expect(ProgressPresenter.strengthTrendSummary(series: [], unit: .kilograms)
                       == "No lifts tracked yet.")
    }

    @Test func strengthTrendSummaryCountsTrackedLifts() {
        let pts = [E1RMPoint(weekStart: Date(timeIntervalSince1970: 0), e1rm: 100),
                   E1RMPoint(weekStart: Date(timeIntervalSince1970: 7 * 86_400), e1rm: 110)]
        let series = [E1RMSeries(exercise: "Bench Press", points: pts)]
        let summary = ProgressPresenter.strengthTrendSummary(series: series, unit: .kilograms)
        #expect(CatalogPlural.renderings("%lld lifts tracked. ", 1).contains { summary.hasPrefix($0) }, "\(summary)")
        #expect(CatalogPlural.english("%lld lifts tracked. ", 1) == "1 lift tracked. ")
        #expect(summary.contains("Bench Press"))
    }

    @Test func intensityReadStrength() {
        let heavy = IntensityDistribution(heavy: 0.6, moderate: 0.3, light: 0.1, sampleCount: 10)
        let light = IntensityDistribution(heavy: 0.1, moderate: 0.3, light: 0.6, sampleCount: 10)
        #expect(ProgressPresenter.intensityRead(heavy, goal: .strength).contains("aligned"))
        #expect(ProgressPresenter.intensityRead(light, goal: .strength).contains("Lighter"))
    }

    @Test func effortReadInRange() {
        let target = Double(TrainingGoal.strength.targetRIR)
        let read = ProgressPresenter.effortRead(target, goal: .strength)
        #expect(read == "In the effective range for \(TrainingGoal.strength.displayName.lowercased()).")
    }

    @Test func effortReadTooFarFromFailure() {
        let target = Double(TrainingGoal.strength.targetRIR)
        let read = ProgressPresenter.effortRead(target + 2, goal: .strength)
        #expect(read.contains("further from failure"))
    }
}
#endif
