import XCTest
@testable import CadenceCore

final class ClientShareStoreTests: XCTestCase {
    func testTrainerAndClientConvergeThroughOneSharedZone() async throws {
        let store = InMemoryClientShareStore()
        let invitation = try await store.createShare(
            trainerID: "trainer-apple-id", clientID: "client-apple-id",
            clientDisplayName: "Alex", at: Date(timeIntervalSince1970: 100))
        let trainerPhone = try await store.trainerConnection(for: invitation, deviceID: "iphone")
        let trainerIPad = try await store.trainerConnection(for: invitation, deviceID: "ipad")
        let client = try await store.accept(invitation, as: "client-apple-id", deviceID: "client-phone")

        let firstPlan = fixturePlan(title: "Week one", calculatedWeight: 72.5)
        let firstToken = try await store.writePlan(
            firstPlan, using: trainerPhone,
            sentAt: Date(timeIntervalSince1970: 110), editedAt: Date(timeIntervalSince1970: 110))

        let received = try await store.changes(using: client, since: nil)
        XCTAssertEqual(received.changes.count, 1)
        guard case let .plan(shared) = try XCTUnwrap(received.changes.first) else {
            return XCTFail("client should receive the trainer plan")
        }
        XCTAssertEqual(shared.plan, firstPlan)
        XCTAssertEqual(shared.sentAt, Date(timeIntervalSince1970: 110))
        XCTAssertEqual(firstToken, received.nextToken)

        // A later athlete e1RM change is not allowed to rewrite the sent
        // calculated weight; a new send is a separate plan revision.
        guard case let .strength(strength) = shared.plan.weeks[0].days[0]
            .sessions[0].orderedItems[0] else {
            return XCTFail("fixture should contain a strength item")
        }
        XCTAssertEqual(strength.sets[0].load,
                       .percent1RM(percent: 0.725, calculatedWeight: 72.5))

        let result = ClientShareResult(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            kind: .set, recordedAt: Date(timeIntervalSince1970: 200), payload: Data([1, 2]))
        let appended = try await store.append(result, using: client)
        XCTAssertTrue(appended)
        let trainerChanges = try await store.changes(using: trainerIPad, since: received.nextToken)
        XCTAssertEqual(trainerChanges.changes, [.result(result)])
    }

    func testResultsAreAppendOnlyAndDuplicateDeliveryIsIdempotent() async throws {
        let store = InMemoryClientShareStore()
        let invitation = try await store.createShare(
            trainerID: "trainer", clientID: "client", clientDisplayName: "Client", at: .init(timeIntervalSince1970: 1))
        _ = try await store.trainerConnection(for: invitation, deviceID: "trainer-phone")
        let client = try await store.accept(invitation, as: "client", deviceID: "client-phone")

        let second = ClientShareResult(sessionID: UUID(), kind: .set, payload: Data([2]))
        let first = ClientShareResult(sessionID: UUID(), kind: .set, payload: Data([1]))
        let appendedSecond = try await store.append(second, using: client)
        let appendedFirst = try await store.append(first, using: client)
        let replayed = try await store.append(first, using: client)
        XCTAssertTrue(appendedSecond)
        XCTAssertTrue(appendedFirst)
        XCTAssertFalse(replayed, "replayed result delivery must not create a second record")

        let page = try await store.changes(using: client, since: nil)
        XCTAssertEqual(page.changes, [.result(second), .result(first)],
                       "arrival order is preserved and neither result overwrites the other")

        let conflicting = ClientShareResult(id: first.id, sessionID: UUID(), kind: .cardio,
                                            payload: Data([9]))
        do {
            _ = try await store.append(conflicting, using: client)
            XCTFail("a reused result ID with different content must be rejected")
        } catch let error as ClientShareStoreError {
            XCTAssertEqual(error, .conflictingResultID)
        }
    }

    func testTrainerDevicesUseTheSameZoneAndLastWriterWinsForPlanEdits() async throws {
        let store = InMemoryClientShareStore()
        let invitation = try await store.createShare(
            trainerID: "trainer", clientID: "client", clientDisplayName: "Client", at: .init(timeIntervalSince1970: 1))
        let phone = try await store.trainerConnection(for: invitation, deviceID: "iphone")
        let ipad = try await store.trainerConnection(for: invitation, deviceID: "ipad")

        _ = try await store.writePlan(
            fixturePlan(title: "Phone draft", calculatedWeight: 70), using: phone,
            sentAt: .init(timeIntervalSince1970: 10), editedAt: .init(timeIntervalSince1970: 10))
        _ = try await store.writePlan(
            fixturePlan(title: "iPad draft", calculatedWeight: 75), using: ipad,
            sentAt: .init(timeIntervalSince1970: 10), editedAt: .init(timeIntervalSince1970: 20))

        let current = try await store.currentPlan(using: phone)
        XCTAssertEqual(current?.plan.title, "iPad draft")
        XCTAssertEqual(current?.lastEditedBy, "ipad")
        XCTAssertEqual(current?.revision, 2)
    }

    private func fixturePlan(title: String, calculatedWeight: Double) -> Plan {
        let set = PrescribedSet(
            setIndex: 0, kind: .working, repTarget: .exact(5),
            load: .percent1RM(percent: 0.725, calculatedWeight: calculatedWeight),
            targetRPE: 8, restSeconds: 150)
        let item = StrengthItem(exerciseKey: ExerciseKey(raw: "bench_press"), order: 0, sets: [set])
        let session = Session(title: "Upper", goal: .strength, items: [.strength(item)])
        let days = Weekday.mondayThroughSunday.map { weekday in
            PlanDay(weekday: weekday, sessions: weekday == .monday ? [session] : [])
        }
        return Plan(title: title, weeks: [PlanWeek(index: 0, days: days)])
    }
}

private extension Weekday {
    static var mondayThroughSunday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
