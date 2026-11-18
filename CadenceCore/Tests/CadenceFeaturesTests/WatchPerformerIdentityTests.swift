#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

/// Issue #429: phone performer identity survives Watch workout starts.
@MainActor
final class WatchPerformerIdentityTests {
    private var context: ModelContext!

    init() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    private func payload(_ performers: [WatchSync.PerformerReference]?) -> WatchPlanPayload {
        WatchPlanPayload(strength: .init(exerciseNames: ["Bench Press"], performers: performers))
    }

    @Test func payloadRoundTripPreservesIdentitiesAndDuplicateNames() throws {
        let a = UUID().uuidString, b = UUID().uuidString
        let refs: [WatchSync.PerformerReference] = [
            .owner(),
            .init(id: a, displayName: "Sam", isOwner: false),
            .init(id: b, displayName: "Sam", isOwner: false)]
        let original = payload(refs)
        let decoded = try #require(WatchPlanPayload(propertyList: original.propertyList))
        #expect(decoded.strength?.performers == refs)
    }

    @Test func legacyPayloadDecodesWithoutPerformers() throws {
        let json = #"{"version":1,"strength":{"exerciseNames":["Squat"],"repLadder":[5],"prescriptions":[]},"cardio":[]}"#
        let decoded = try JSONDecoder().decode(WatchPlanPayload.self, from: Data(json.utf8))
        #expect(decoded.strength?.performers == nil)
    }

    @Test func partnerMapsToPhoneUUIDNotLocalID() throws {
        let phoneID = UUID().uuidString
        let m = WatchStrengthFlowModel(context: context)
        m.start(title: "Push", planPayload: payload([.owner(), .init(id: phoneID, displayName: "Sam", isOwner: false)]),
                createSession: true)
        #expect(m.currentPerformerRemoteID == "owner")
        m.selectPerformer(at: 1)
        #expect(m.currentPerformerRemoteID == phoneID)
        #expect(m.activePerformer.localPerson?.id.uuidString != phoneID)
        #expect(m.activePerformer.displayName == "Sam")
    }

    @Test func duplicateNamesStayDistinct() throws {
        let a = UUID().uuidString, b = UUID().uuidString
        let m = WatchStrengthFlowModel(context: context)
        m.start(title: "Push", planPayload: payload([
            .owner(),
            .init(id: a, displayName: "Sam", isOwner: false),
            .init(id: b, displayName: "Sam", isOwner: false)]), createSession: true)
        #expect(m.partners.count == 2)
        m.selectPerformer(at: 1)
        #expect(m.currentPerformerRemoteID == a)
        m.selectPerformer(at: 2)
        #expect(m.currentPerformerRemoteID == b)
    }

    @Test func legacyNameOnlyStartGetsNonmatchingIdentity() throws {
        let m = WatchStrengthFlowModel(context: context)
        m.start(title: "Push", initialPartnerNames: ["  Sam "], createSession: true)
        m.selectPerformer(at: 1)
        #expect(m.currentPerformerRemoteID == "legacy-name:sam")
        #expect(UUID(uuidString: m.currentPerformerRemoteID) == nil)
        m.selectPerformer(at: 0)
        #expect(m.currentPerformerRemoteID == "owner")
    }
}
#endif
