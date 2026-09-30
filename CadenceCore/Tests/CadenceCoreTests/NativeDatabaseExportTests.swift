import XCTest
import SwiftData
@testable import CadenceCore

/// JSON v8 must be a complete, lossless archive of the native store, not only
/// of the convenience session/cardio DTOs. This test deliberately seeds every
/// persisted entity and verifies a fresh-store round trip byte-for-byte at the
/// decoded row-payload level.
@MainActor
final class NativeDatabaseExportTests: XCTestCase {
    func testEveryNativeEntityRoundTripsWithoutLossOrDuplicateRows() throws {
        let source = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let date = Date(timeIntervalSince1970: 1_735_689_600)

        let person = Person(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                            name: "Partner", updatedAt: date)
        let exercise = Exercise(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                name: "Cable Press", updatedAt: date)
        let session = WorkoutSession(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                                     title: "Native archive", date: date, updatedAt: date)
        let set = SetEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                           weight: 57, reps: 8, order: 0, completedAt: date,
                           updatedAt: date, session: session, exercise: exercise,
                           performedBy: person)
        session.sets = [set]
        exercise.sets = [set]
        person.sets = [set]

        let template = SessionTemplate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                                       name: "Template", updatedAt: date)
        let templateExercise = TemplateExercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            exerciseName: exercise.name, template: template)
        template.exercises = [templateExercise]

        let cardio = CardioWorkout(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
                                   start: date, end: date.addingTimeInterval(600),
                                   updatedAt: date)
        let heartRate = HRSample(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
                                 t: 15, bpm: 142, cardio: cardio)
        let route = RouteSample(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
                                t: 15, lat: 41.88, lon: -87.63, elevation: 12, cardio: cardio)
        cardio.hrSamples = [heartRate]
        cardio.routeSamples = [route]

        let readiness = ReadinessEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                                       updatedAt: date)
        let device = HRMDevice(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                               name: "Chest strap", updatedAt: date)
        let assessment = Assessment(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                                    date: date, value: 42, updatedAt: date)
        let plan = PersistedPlan(id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
                                 planData: Data([1, 2, 3]), updatedAt: date)
        let header = PersistedPlanHeader(id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
                                         title: "Plan", updatedAt: date)
        let week = PersistedPlanWeek(id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
                                     planID: plan.id)
        let day = PersistedPlanDay(id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
                                   weekID: week.id)
        let planSession = PersistedPlanSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!, dayID: day.id,
            title: "Plan session")
        let item = PersistedPlanItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!, sessionID: planSession.id,
            payloadData: Data([4, 5]))
        let planSet = PersistedPlanSet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!, itemID: item.id,
            payloadData: Data([6, 7]))
        let relationship = PersistedClientRelationship(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!, displayName: "Client",
            updatedAt: date)
        let exclusion = ExerciseSuggestionExclusion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            exerciseKey: "custom:cable-press", exerciseNameSnapshot: exercise.name,
            updatedAt: date)
        let scheduled = ScheduledWorkout(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            scheduledDate: date, scheduledDayKey: "2025-01-01", title: "Scheduled",
            updatedAt: date)

        let rows: [any PersistentModel] = [
            person, exercise, session, set, template, templateExercise, cardio, heartRate,
            route, readiness, device, assessment, plan, header, week, day, planSession, item,
            planSet, relationship, exclusion, scheduled
        ]
        rows.forEach { source.insert($0) }
        try source.save()

        let original = try NativeDatabaseExport.build(from: source)
        XCTAssertEqual(original.entityNamesPresent, Set(ExportNativeDatabase.entityNames))
        XCTAssertEqual(original.records.count, ExportNativeDatabase.entityNames.count)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExportNativeDatabase.self, from: encoded)
        let destination = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        XCTAssertEqual(try NativeDatabaseExport.merge(decoded, in: destination), original.records.count)
        XCTAssertEqual(try NativeDatabaseExport.merge(decoded, in: destination), 0,
                       "re-importing the same v8 archive must be idempotent")

        let roundTripped = try NativeDatabaseExport.build(from: destination)
        let expected = sorted(original.records)
        let actual = sorted(roundTripped.records)
        XCTAssertEqual(expected.count, actual.count)
        for (lhs, rhs) in zip(expected, actual) {
            XCTAssertEqual(lhs.entity, rhs.entity)
            XCTAssertEqual(lhs.id, rhs.id)
            XCTAssertEqual(lhs.updatedAt, rhs.updatedAt)
            XCTAssertEqual(canonicalJSON(lhs.payload), canonicalJSON(rhs.payload),
                           "native payload changed for \(lhs.entity)")
        }
    }

    private func sorted(_ records: [ExportNativeRecord]) -> [ExportNativeRecord] {
        records.sorted {
            if $0.entity != $1.entity { return $0.entity < $1.entity }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func canonicalJSON(_ data: Data) -> AnyHashable {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let canonical = try? JSONSerialization.data(withJSONObject: object,
                                                           options: [.sortedKeys, .fragmentsAllowed]) else {
            return AnyHashable(data)
        }
        return AnyHashable(canonical)
    }
}
