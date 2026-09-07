import XCTest
import SwiftData
@testable import CadenceCore

/// The explicit SwiftData schema is the source of truth used to generate the
/// CloudKit record schema. Every @Model must be listed here or its data cannot
/// be persisted and mirrored consistently.
@MainActor
final class CloudKitSchemaCoverageTests: XCTestCase {
    func testEveryPersistedModelIsIncludedInTheStoreSchema() {
        let expectedModels: [any PersistentModel.Type] = [
            WorkoutSession.self,
            Exercise.self,
            SetEntry.self,
            SessionTemplate.self,
            TemplateExercise.self,
            CardioWorkout.self,
            ReadinessEntry.self,
            HRSample.self,
            RouteSample.self,
            HRMDevice.self,
            Person.self,
            Assessment.self,
            PersistedPlan.self,
            PersistedPlanHeader.self,
            PersistedPlanWeek.self,
            PersistedPlanDay.self,
            PersistedPlanSession.self,
            PersistedPlanItem.self,
            PersistedPlanSet.self,
            PersistedClientRelationship.self
        ]

        // `Schema.entity(for:)` is unavailable on the package's macOS 14
        // deployment target, so the count check keeps this guard runnable in
        // the same host test matrix as the rest of CadenceCore.
        XCTAssertEqual(CadenceStore.schema.entities.count, expectedModels.count)
    }

    func testReadinessEntryCanBePersistedThroughTheSharedSchema() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let entry = ReadinessEntry(muscleSoreness: 4, fatigueEnergy: 5,
                                   sleepQuality: 3, stressMood: 4)
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ReadinessEntry>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.muscleSoreness, 4)
        XCTAssertEqual(fetched.first?.fatigueEnergy, 5)
    }

    func testEveryPersistedModelHasTheExpectedCloudKitAttributes() {
        let expected: [String: Set<String>] = [
            "Assessment": ["date", "exerciseName", "id", "inputAge",
                            "inputDistance", "inputEndingHR", "inputReps", "inputSex",
                            "inputTime", "inputWeight", "kind", "notes", "originDevice",
                            "protocolName", "updatedAt", "value"],
            "CardioWorkout": ["activeEnergy", "avgHeartRate", "customTitle", "deletedAt",
                               "distance", "end", "healthKitWorkoutUUID", "id",
                               "importedWorkoutKindRaw", "intervalDetailData", "isLogged", "laps",
                               "maxHeartRate", "notes", "originDevice", "source", "start",
                               "targetDistance", "targetLaps", "type", "updatedAt"],
            "Exercise": ["annotationConfidence", "category", "createdAt", "defaultBarWeightKg",
                         "directMusclesData", "equipment", "force", "id",
                         "imageName", "indirectMusclesData", "instructionsData", "isCustom",
                         "isFavorite", "isLateral", "level", "loadAccountingMode",
                         "loadAccountingUserOverride", "mechanics", "modalitiesData",
                         "movementPatternIDsData", "muscleGroupsData", "name", "originDevice",
                         "primaryMusclesData", "searchKeywordsData", "secondaryMusclesData",
                         "sourceExerciseID", "sportContextsData", "stabilizerMusclesData",
                         "trainingTypesData", "updatedAt", "volumeEligible"],
            "HRMDevice": ["id", "isDefault", "lastBattery", "lastConnectedAt", "name", "updatedAt"],
            "HRSample": ["bpm", "id", "t"],
            "PersistedClientRelationship": ["createdAt", "displayName", "goalRaw",
                                              "id", "notes", "shareURLString", "shareZoneID",
                                              "statusRaw", "updatedAt"],
            "PersistedPlan": ["deletedAt", "id", "originDevice", "payloadVersion",
                               "planData", "updatedAt"],
            "PersistedPlanDay": ["id", "weekID", "weekdayRaw"],
            "PersistedPlanHeader": ["authoredOnIdiomRaw", "createdAt", "goalRaw",
                                     "horizonData", "id", "notes", "originDevice", "provenanceData",
                                     "rationaleData", "statusRaw", "title", "updatedAt"],
            "PersistedPlanItem": ["id", "kindRaw", "order", "payloadData", "sessionID"],
            "PersistedPlanSession": ["completedAt", "dayID", "estimatedDurationMinutes",
                                      "goalRaw", "id", "note", "painData", "partnersData", "sessionRPE",
                                      "startedAt", "statusRaw", "title"],
            "PersistedPlanSet": ["id", "itemID", "payloadData", "setIndex"],
            "PersistedPlanWeek": ["id", "index", "intendedProgressionRaw", "isDeload",
                                  "planID"],
            "Person": ["createdAt", "id", "isMe", "name", "originDevice", "updatedAt"],
            "ReadinessEntry": ["date", "fatigueEnergy", "hasPainOrIllnessConcern", "id",
                                "muscleSoreness", "sleepQuality", "stressMood", "updatedAt"],
            "RouteSample": ["elevation", "id", "lat", "lon", "t"],
            "SessionTemplate": ["createdAt", "id", "name", "originDevice", "updatedAt"],
            "SetEntry": ["barWeightKg", "completedAt", "id", "isWarmup", "loadAccountingMode",
                          "loadMultiplier", "note", "order", "originDevice", "reps", "rpe", "updatedAt",
                          "usesBodyweight", "weight"],
            "TemplateExercise": ["exerciseName", "id", "order", "targetReps", "targetSets"],
            "WorkoutSession": ["activePartnerIDsData", "cooldownSeconds", "date", "deletedAt", "endedAt",
                                "enginePlanId", "enginePlanJSON", "engineRevisionId",
                                "healthKitWorkoutUUID", "id", "isLogged", "notes", "originDevice", "planKey",
                                "planSessionID", "plannedExerciseNamesData", "plannedPerformerPrescriptionsData",
                                "plannedPrescriptionsData", "plannedRepLadderData", "prescribedLoadKg",
                                "templateName", "title", "updatedAt", "warmupSeconds"]
        ]

        let actual = Dictionary(uniqueKeysWithValues: CadenceStore.schema.entities.map {
            ($0.name, Set($0.attributes.map(\.name)))
        })
        XCTAssertEqual(Set(actual.keys), Set(expected.keys))
        for (model, attributes) in expected {
            XCTAssertEqual(actual[model], attributes, "CloudKit attribute contract drifted for \(model)")
        }
    }
}
