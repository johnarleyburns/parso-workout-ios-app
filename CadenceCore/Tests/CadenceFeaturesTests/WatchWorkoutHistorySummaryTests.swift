import Foundation
import SwiftData
import Testing
import CadenceCore
@testable import CadenceFeatures

@MainActor
struct WatchWorkoutHistorySummaryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func points(_ n: Int) -> [HRSamplePoint] {
        (0..<n).map { HRSamplePoint(t: Double($0), bpm: 120 + Double($0 % 30)) }
    }

    private func cardio(id: UUID = UUID(), daysAgo: Double = 1, hr: Int = 0) -> CardioWorkout {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        let row = CardioWorkout(id: id, type: .run, start: start, end: start.addingTimeInterval(1_800),
                                distance: 5_000, activeEnergy: 400, avgHeartRate: 150, maxHeartRate: 175,
                                laps: 4, notes: "private note", updatedAt: start)
        row.hrSamples = points(hr).map { HRSample(t: $0.t, bpm: $0.bpm, cardio: row) }
        return row
    }

    @Test func normalizationCapsFiltersAndKeepsEnds() {
        let big = WatchWorkoutHistorySummary.normalized(points(5_000).reversed())
        #expect(big.count <= 120 && big.first?.t == 0 && big.last?.t == 4_999)
        #expect(zip(big, big.dropFirst()).allSatisfy { $0.t <= $1.t })
        let dirty = WatchWorkoutHistorySummary.normalized([
            .init(t: .nan, bpm: 100), .init(t: -1, bpm: 100), .init(t: 1, bpm: 0),
            .init(t: 2, bpm: .infinity), .init(t: 3, bpm: 110)])
        #expect(dirty == [.init(t: 3, bpm: 110)])
    }

    @Test func strengthBuilderPreservesOrderAndTotals() {
        let bench = Exercise(name: "Bench Press"), row = Exercise(name: "Row")
        let session = WorkoutSession(title: "Push", date: now, endedAt: now.addingTimeInterval(3_000))
        session.sets = [
            SetEntry(weight: 20, reps: 10, order: 0, isWarmup: true, exercise: bench),
            SetEntry(weight: 80, reps: 5, order: 1, rpe: 8, exercise: bench),
            SetEntry(weight: 60, reps: 8, order: 2, exercise: row)]
        let summary = WatchWorkoutHistorySummary.make(session: session)
        #expect(summary.exercises.map(\.name) == ["Bench Press", "Row"])
        #expect(summary.exercises[0].sets.map(\.isWarmup) == [true, false])
        #expect(summary.exercises[0].sets[1].rpe == 8)
        #expect(summary.workingSetCount == 2)
        #expect(summary.totalVolumeKg == session.totalVolume)
        #expect(summary.availability == .basic && summary.minuteSummary == nil)
    }

    @Test func cardioBuilderUsesStoredIntensityAndNeverInventsCredit() {
        let row = cardio(hr: 10)
        let stored = CardioMinuteSummary.manual(moderate: 7, vigorous: 3, sessionDuration: 1_800)
        row.intensitySummary = stored
        let summary = WatchWorkoutHistorySummary.make(cardio: row, profile: CardioIntensityProfile(maximumHR: 100))
        #expect(summary.minuteSummary == stored && summary.distanceMeters == 5_000 && summary.laps == 4)
        #expect(summary.durationSeconds == 1_800 && summary.averageBPM == 150 && summary.maximumBPM == 175)
        let none = WatchWorkoutHistorySummary.make(cardio: cardio(hr: 0))
        #expect(none.availability == .basic && none.minuteSummary == nil && none.hrSamples.isEmpty)
        let noCredit = WatchWorkoutHistorySummary.make(cardio: cardio(hr: 10))
        #expect(noCredit.availability == .heartRateOnly)
    }

    @Test func presentationParityAndHistoricalHasNoActions() {
        let summary = WatchWorkoutHistorySummary.make(cardio: cardio(hr: 300),
                                                      profile: CardioIntensityProfile(maximumHR: 190))
        let live = WatchWorkoutSummaryPresentation.make(summary: summary, unit: .kilograms, isHistorical: false)
        let past = WatchWorkoutSummaryPresentation.make(summary: summary, unit: .kilograms, isHistorical: true)
        #expect(past.actions.isEmpty && live.actions == [.save, .discard])
        #expect(live.hrSamples == past.hrSamples && live.minutes == past.minutes
                && live.coverage == past.coverage && live.durationSeconds == past.durationSeconds
                && live.showsHeartRateChart == past.showsHeartRateChart)
        let blank = WatchWorkoutSummaryPresentation.make(
            summary: WatchWorkoutHistorySummary.make(cardio: cardio()), unit: .kilograms, isHistorical: true)
        #expect(!blank.showsHeartRateChart && blank.minutes == nil && blank.coverage == nil
                && blank.omissions.contains(.heartRate))
    }

    @Test func routing() {
        let plan = WatchMyWorkouts.rows(plan: nil, history: [], cardio: [
            .init(id: UUID(), title: "Run", type: "run", start: now),
            .init(id: UUID(), title: "Run", type: "run", start: now.addingTimeInterval(-5), hasRichSummary: true)])
        guard case .cardioFallback = WatchMyWorkoutRoute.route(for: plan[0]) else { Issue.record("fallback"); return }
        guard case .cardioSummary = WatchMyWorkoutRoute.route(for: plan[1]) else { Issue.record("rich"); return }
        let session = WatchMyWorkouts.rows(plan: nil, history: [.init(id: UUID(), title: "A", date: now, setCount: 1)])
        guard case .strengthSummary = WatchMyWorkoutRoute.route(for: session[0]) else { Issue.record("strength"); return }
    }

    @Test func wireV2RoundTripV1CompatAndBadPayloads() throws {
        let row = cardio(hr: 400)
        let item = WatchCardioHistoryProjection.item(for: row)
        #expect(item.summaryData != nil && WatchSync.CardioHistoryItem.currentVersion == 2)
        _ = try PropertyListSerialization.data(fromPropertyList: item.propertyList, format: .binary, options: 0)
        #expect(WatchSync.CardioHistoryItem(propertyList: item.propertyList) == item)
        let decoded = WatchWorkoutHistorySummary.decode(item.summaryData!)
        #expect((decoded?.hrSamples.count ?? 999) <= 120)

        var v1 = item.propertyList; v1["v"] = 1; v1["summary"] = nil
        let old = try #require(WatchSync.CardioHistoryItem(propertyList: v1))
        #expect(old.summaryData == nil)

        var bad = item.propertyList; bad["summary"] = Data(repeating: 7, count: 20)
        #expect(WatchSync.CardioHistoryItem(propertyList: bad)?.summaryData == nil)
        bad["summary"] = Data(repeating: 7, count: WatchWorkoutHistorySummary.maxPayloadBytes + 1)
        #expect(WatchSync.CardioHistoryItem(propertyList: bad)?.summaryData == nil)
        bad["summary"] = "not data"
        #expect(WatchSync.CardioHistoryItem(propertyList: bad)?.summaryData == nil)

        let text = String(decoding: item.summaryData!, as: UTF8.self)
        #expect(!text.contains("private note") && !text.lowercased().contains("route")
                && !text.contains("activeEnergy") && !text.contains("bundle"))
    }

    @Test func summaryChangesFingerprintAndRetentionStaysBounded() {
        let id = UUID()
        let a = WatchCardioHistoryProjection.snapshot(from: [cardio(id: id, hr: 5)], now: now)
        let b = WatchCardioHistoryProjection.snapshot(from: [cardio(id: id, hr: 50)], now: now)
        #expect(a.fingerprint != b.fingerprint)
        let many = (0..<80).map { cardio(daysAgo: 0.5 + Double($0) * 0.01, hr: 200) }
        let snap = WatchCardioHistoryProjection.snapshot(from: many, now: now)
        #expect(snap.liveItems.count == 60)
        #expect(snap.liveItems.allSatisfy {
            ($0.summaryData.flatMap(WatchWorkoutHistorySummary.decode)?.hrSamples.count ?? 0) <= 120 })
    }

    @Test func storePersistsReplacesAndPendingCompletionHandsOff() throws {
        let context = ModelContext(try ModelContainer(
            for: WatchCardioHistoryRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let id = UUID()
        _ = try WatchCardioHistoryStore.apply(
            WatchCardioHistoryProjection.snapshot(from: [cardio(id: id, hr: 5)], now: now), in: context)
        let first = try #require(try context.fetch(FetchDescriptor<WatchCardioHistoryRecord>()).first?.summaryData)
        #expect(try WatchCardioHistoryStore.apply(
            WatchCardioHistoryProjection.snapshot(from: [cardio(id: id, hr: 50)], now: now), in: context) == 1)
        let second = try #require(try context.fetch(FetchDescriptor<WatchCardioHistoryRecord>()).first?.summaryData)
        #expect(first != second)

        let start = now.addingTimeInterval(-600)
        let completion = WatchCardioCompletion(id: id, type: .run, start: start, end: now,
                                               distanceMeters: 1_000, hrSamples: points(30),
                                               avgHeartRate: 130, maxHeartRate: 150, gpsEnabled: true)
        let local = WatchWorkoutHistorySummary.make(completion: completion, profile: CardioIntensityProfile(maximumHR: 190))
        #expect(local.id == id && local.availability == .full && local.distanceMeters == 1_000)
        // Same-ID mirror dedups the pending local representation.
        let rows = WatchMyWorkouts.rows(plan: nil, history: [], cardio: [
            .init(id: id, title: "Run", type: "run", start: start, hasRichSummary: true)])
        #expect(rows.count == 1)
    }
}
