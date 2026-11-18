#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

@MainActor
struct PhoneStrengthHeartRateRecorderTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func makeSession() throws -> (ModelContext, WorkoutSession) {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Push", date: start)
        ctx.insert(s)
        try ctx.save()
        return (ctx, s)
    }

    private func obs(_ offset: TimeInterval, _ bpm: Double = 130, id: String? = nil) -> HeartRateObservation {
        HeartRateObservation(source: .watchHealthKit, observedAt: start.addingTimeInterval(offset), bpm: bpm, sampleID: id)
    }

    @Test func captureSurvivesViewlessLifecycleAndRecreation() throws {
        let (ctx, session) = try makeSession()
        let active = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        active.startStrength(session)
        let now = start.addingTimeInterval(3700)
        for i in 0..<720 { // 60 minutes at 5s, no SessionView anywhere
            #expect(active.heartRateRecorder?.record(obs(Double(i) * 5), now: now) == .accepted)
        }
        session.endedAt = start.addingTimeInterval(3600)
        #expect(active.heartRateRecorder!.finalize(profile: CardioIntensityProfile(restingHR: 60, maximumHR: 190)))
        try ctx.save()
        // Recreate from the store: samples and summary survive.
        let reloaded = try #require(ctx.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(reloaded.hrSamplePoints.count == 720)
        #expect(reloaded.intensitySummary != nil)
    }

    @Test func adoptionDoesNotDoubleCount() throws {
        let (_, session) = try makeSession()
        let first = PhoneStrengthHeartRateRecorder(session: session)
        let now = start.addingTimeInterval(600)
        for i in 0..<10 { first.record(obs(Double(i) * 5), now: now) }
        #expect(first.flush())
        let adopted = PhoneStrengthHeartRateRecorder(session: session)
        #expect(adopted.snapshot.count == 10)
        #expect(adopted.record(obs(20), now: now) == .duplicate)
        #expect(adopted.record(obs(60), now: now) == .accepted)
        #expect(adopted.snapshot.count == 11)
    }

    @Test func heartbeatResendAndIdentityDeduplicate() throws {
        let (_, session) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: session)
        let now = start.addingTimeInterval(600)
        #expect(r.record(obs(10, id: "a"), now: now) == .accepted)
        for _ in 0..<100 { #expect(r.record(obs(10), now: now) == .duplicate) }
        #expect(r.record(obs(12, id: "a"), now: now) == .duplicate)
        #expect(r.snapshot.count == 1)
        // Equal BPM at a different real timestamp is a new measurement.
        #expect(r.record(obs(15), now: now) == .accepted)
        #expect(r.snapshot.count == 2)
    }

    @Test func rejectsInvalidAndOutOfWindow() throws {
        let (_, session) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: session)
        let now = start.addingTimeInterval(600)
        #expect(r.record(obs(10, .nan), now: now) == .rejected(.invalidBPM))
        #expect(r.record(obs(10, 500), now: now) == .rejected(.invalidBPM))
        #expect(r.record(obs(-100), now: now) == .rejected(.beforeSession))
        #expect(r.record(obs(900), now: now) == .rejected(.afterSession))
        session.endedAt = start.addingTimeInterval(300)
        #expect(r.record(obs(500), now: now) == .rejected(.afterSession))
        #expect(r.snapshot.isEmpty)
    }

    @Test func reorderedObservationsAreOrdered() throws {
        let (_, session) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: session)
        let now = start.addingTimeInterval(600)
        for t in [30.0, 10, 20] { r.record(obs(t), now: now) }
        #expect(r.snapshot.map(\.t) == [10, 20, 30])
    }

    @Test func persistenceFailureIsPendingAndRetained() throws {
        let (_, session) = try makeSession()
        struct Boom: Error {}
        var fail = true
        let r = PhoneStrengthHeartRateRecorder(session: session, save: { if fail { throw Boom() } })
        r.record(obs(10), now: start.addingTimeInterval(600))
        #expect(!r.finalize(profile: CardioIntensityProfile()))
        #expect(r.persistencePending)
        #expect(r.snapshot.count == 1)
        #expect(session.hrSamplesData.isEmpty)
        fail = false
        #expect(r.finalize(profile: CardioIntensityProfile()))
        #expect(!r.persistencePending)
        #expect(session.hrSamplePoints.count == 1)
    }

    @Test func storageIsBounded() throws {
        let (_, session) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: session, save: {})
        let now = start.addingTimeInterval(100_000)
        for i in 0...(PhoneStrengthHeartRateRecorder.maximumStoredSamples + 10) {
            r.record(obs(Double(i), Double(100 + i % 50)), now: now)
        }
        #expect(r.snapshot.count <= PhoneStrengthHeartRateRecorder.maximumStoredSamples)
    }

    @Test func recordersAreKeyedToTheirSession() throws {
        let (ctx, a) = try makeSession()
        let b = WorkoutSession(title: "B", date: start)
        ctx.insert(b)
        let ra = PhoneStrengthHeartRateRecorder(session: a)
        let rb = PhoneStrengthHeartRateRecorder(session: b)
        ra.record(obs(10), now: start.addingTimeInterval(60))
        #expect(ra.sessionID == a.id)
        #expect(rb.snapshot.isEmpty)
    }
}
#endif
