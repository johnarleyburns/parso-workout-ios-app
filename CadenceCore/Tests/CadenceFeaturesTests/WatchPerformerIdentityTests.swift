import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

/// Issue #429: phone performer identity survives Watch workout starts.
@MainActor
final class WatchPerformerIdentityTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    private func payload(_ performers: [WatchSync.PerformerReference]?) -> WatchPlanPayload {
        WatchPlanPayload(strength: .init(exerciseNames: ["Bench Press"], performers: performers))
    }

    func testPayloadRoundTripPreservesIdentitiesAndDuplicateNames() throws {
        let a = UUID().uuidString, b = UUID().uuidString
        let refs: [WatchSync.PerformerReference] = [
            .owner(),
            .init(id: a, displayName: "Sam", isOwner: false),
            .init(id: b, displayName: "Sam", isOwner: false)]
        let original = payload(refs)
        let decoded = try XCTUnwrap(WatchPlanPayload(propertyList: original.propertyList))
        XCTAssertEqual(decoded.strength?.performers, refs)
    }

    func testLegacyPayloadDecodesWithoutPerformers() throws {
        let json = #"{"version":1,"strength":{"exerciseNames":["Squat"],"repLadder":[5],"prescriptions":[]},"cardio":[]}"#
        let decoded = try JSONDecoder().decode(WatchPlanPayload.self, from: Data(json.utf8))
        XCTAssertNil(decoded.strength?.performers)
    }

    func testPartnerMapsToPhoneUUIDNotLocalID() throws {
        let phoneID = UUID().uuidString
        let m = WatchStrengthFlowModel(context: context)
        m.start(title: "Push", planPayload: payload([.owner(), .init(id: phoneID, displayName: "Sam", isOwner: false)]),
                createSession: true)
        XCTAssertEqual(m.currentPerformerRemoteID, "owner")
        m.selectPerformer(at: 1)
        XCTAssertEqual(m.currentPerformerRemoteID, phoneID)
        XCTAssertNotEqual(m.activePerformer.localPerson?.id.uuidString, phoneID)
        XCTAssertEqual(m.activePerformer.displayName, "Sam")
    }

    func testDuplicateNamesStayDistinct() throws {
        let a = UUID().uuidString, b = UUID().uuidString
        let m = WatchStrengthFlowModel(context: context)
        m.start(title: "Push", planPayload: payload([
            .owner(),
            .init(id: a, displayName: "Sam", isOwner: false),
            .init(id: b, displayName: "Sam", isOwner: false)]), createSession: true)
        XCTAssertEqual(m.partners.count, 2)
        m.selectPerformer(at: 1)
        XCTAssertEqual(m.currentPerformerRemoteID, a)
        m.selectPerformer(at: 2)
        XCTAssertEqual(m.currentPerformerRemoteID, b)
    }

    func testLegacyNameOnlyStartGetsNonmatchingIdentity() throws {
        let m = WatchStrengthFlowModel(context: context)
        m.start(title: "Push", initialPartnerNames: ["  Sam "], createSession: true)
        m.selectPerformer(at: 1)
        XCTAssertEqual(m.currentPerformerRemoteID, "legacy-name:sam")
        XCTAssertNil(UUID(uuidString: m.currentPerformerRemoteID))
        m.selectPerformer(at: 0)
        XCTAssertEqual(m.currentPerformerRemoteID, "owner")
    }
}
