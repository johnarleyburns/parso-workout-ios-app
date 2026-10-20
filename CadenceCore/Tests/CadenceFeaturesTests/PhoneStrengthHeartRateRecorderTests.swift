import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class PhoneStrengthHeartRateRecorderTests: XCTestCase {
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

    func testCaptureSurvivesViewlessLifecycleAndRecreation() throws {
        let (ctx, session) = try makeSession()
        let active = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        active.startStrength(session)
        let now = start.addingTimeInterval(3700)
        for i in 0..<720 { // 60 minutes at 5s, no SessionView anywhere
            XCTAssertEqual(active.heartRateRecorder?.record(obs(Double(i) * 5), now: now), .accepted)
        }
        session.endedAt = start.addingTimeInterval(3600)
        XCTAssertTrue(active.heartRateRecorder!.finalize(profile: CardioIntensityProfile(restingHR: 60, maximumHR: 190)))
        try ctx.save()
        // Recreate from the store: samples and summary survive.
        let reloaded = try XCTUnwrap(ctx.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(reloaded.hrSamplePoints.count, 720)
        XCTAssertNotNil(reloaded.intensitySummary)
    }

    func testAdoptionDoesNotDoubleCount() throws {
        let (_, session) = try makeSession()
        let first = PhoneStrengthHeartRateRecorder(session: session)
        let now = start.addingTimeInterval(600)
        for i in 0..<10 { first.record(obs(Double(i) * 5), now: now) }
        XCTAssertTrue(first.flush())
        let adopted = PhoneStrengthHeartRateRecorder(session: session)
        XCTAssertEqual(adopted.snapshot.count, 10)
        XCTAssertEqual(adopted.record(obs(20), now: now), .duplicate)
        XCTAssertEqual(adopted.record(obs(60), now: now), .accepted)
        XCTAssertEqual(adopted.snapshot.count, 11)
    }

    func testHeartbeatResendAndIdentityDeduplicate() throws {
        let (_, session) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: session)
        let now = start.addingTimeInterval(600)
        XCTAssertEqual(r.record(obs(10, id: "a"), now: now), .accepted)
        for _ in 0..<100 { XCTAssertEqual(r.record(obs(10), now: now), .duplicate) }
        XCTAssertEqual(r.record(obs(12, id: "a"), now: now), .duplicate)
        XCTAssertEqual(r.snapshot.count, 1)
        // Equal BPM at a different real timestamp is a new measurement.
        XCTAssertEqual(r.record(obs(15), now: now), .accepted)
        XCTAssertEqual(r.snapshot.count, 2)
    }

    func testRejectsInvalidAndOutOfWindow() throws {
        let (_, session) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: session)
        let now = start.addingTimeInterval(600)
        XCTAssertEqual(r.record(obs(10, .nan), now: now), .rejected(.invalidBPM))
        XCTAssertEqual(r.record(obs(10, 500), now: now), .rejected(.invalidBPM))
        XCTAssertEqual(r.record(obs(-100), now: now), .rejected(.beforeSession))
        XCTAssertEqual(r.record(obs(900), now: now), .rejected(.afterSession))
        session.endedAt = start.addingTimeInterval(300)
        XCTAssertEqual(r.record(obs(500), now: now), .rejected(.afterSession))
        XCTAssertTrue(r.snapshot.isEmpty)
    }

    func testReorderedObservationsAreOrdered() throws {
        let (_, session) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: session)
        let now = start.addingTimeInterval(600)
        for t in [30.0, 10, 20] { r.record(obs(t), now: now) }
        XCTAssertEqual(r.snapshot.map(\.t), [10, 20, 30])
    }

    func testPersistenceFailureIsPendingAndRetained() throws {
        let (_, session) = try makeSession()
        struct Boom: Error {}
        var fail = true
        let r = PhoneStrengthHeartRateRecorder(session: session, save: { if fail { throw Boom() } })
        r.record(obs(10), now: start.addingTimeInterval(600))
        XCTAssertFalse(r.finalize(profile: CardioIntensityProfile()))
        XCTAssertTrue(r.persistencePending)
        XCTAssertEqual(r.snapshot.count, 1)
        XCTAssertTrue(session.hrSamplesData.isEmpty)
        fail = false
        XCTAssertTrue(r.finalize(profile: CardioIntensityProfile()))
        XCTAssertFalse(r.persistencePending)
        XCTAssertEqual(session.hrSamplePoints.count, 1)
    }

    func testStorageIsBounded() throws {
        let (_, session) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: session, save: {})
        let now = start.addingTimeInterval(100_000)
        for i in 0...(PhoneStrengthHeartRateRecorder.maximumStoredSamples + 10) {
            r.record(obs(Double(i), Double(100 + i % 50)), now: now)
        }
        XCTAssertLessThanOrEqual(r.snapshot.count, PhoneStrengthHeartRateRecorder.maximumStoredSamples)
    }

    func testRecordersAreKeyedToTheirSession() throws {
        let (ctx, a) = try makeSession()
        let b = WorkoutSession(title: "B", date: start)
        ctx.insert(b)
        let ra = PhoneStrengthHeartRateRecorder(session: a)
        let rb = PhoneStrengthHeartRateRecorder(session: b)
        ra.record(obs(10), now: start.addingTimeInterval(60))
        XCTAssertEqual(ra.sessionID, a.id)
        XCTAssertTrue(rb.snapshot.isEmpty)
    }
}
