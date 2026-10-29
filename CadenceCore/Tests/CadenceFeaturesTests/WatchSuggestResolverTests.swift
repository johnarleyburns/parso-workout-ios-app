import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchSuggestResolverTests: XCTestCase {
    private typealias F = CoachSuggestionFixtures
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let noon = Date(timeIntervalSince1970: 1_799_971_200 + 43_200)

    private func envelope(issued: Date? = nil) -> WatchCoachSuggestionEnvelope {
        let issued = issued ?? noon
        let snap = CoachSuggestionSnapshotBuilder.make(request: F.request(candidates: F.catalog, asOf: issued),
                                                       generatedAt: issued, calendar: cal)
        return .make(snapshot: snap, issuedAt: issued, calendar: cal)
    }

    private func resolve(_ e: WatchCoachSuggestionEnvelope?, now: Date? = nil,
                         history: WatchCoachHistoryState = .init()) -> WatchSuggestAvailability {
        WatchSuggestResolver.resolve(envelope: e, now: now ?? noon, historyState: history, calendar: cal)
    }

    func testWatchLaunchEqualsPhoneMaterializationForSameEnvelope() throws {
        let e = envelope()
        let option = try XCTUnwrap(CoachSuggestionService.generate(from: e.snapshot))
        let r = e.snapshot.request
        let phonePlan = SuggestedWorkoutPresenter.editablePlan(
            for: option, unit: r.unit, warmupMinutes: r.warmupMinutes, cooldownMinutes: r.cooldownMinutes)
        let phone = try XCTUnwrap(CoachWatchTodayBridge.suggestedStrengthSession(from: phonePlan))
        let launch = try XCTUnwrap(resolve(e).launch)
        XCTAssertEqual(launch.title, phone.label)
        XCTAssertEqual(launch.exerciseNames, phone.exerciseNames)
        XCTAssertEqual(launch.repLadder, phone.repLadder)
        XCTAssertEqual(launch.planPayload, phone.planPayload)
        XCTAssertEqual(CoachSuggestionService.generate(from: e.snapshot), option)
    }

    func testNeedsSyncStatesHaveNoLaunch() throws {
        func reason(_ a: WatchSuggestAvailability) -> WatchSuggestAvailability.Reason? {
            if case .needsSync(let r, _) = a { return r }
            return nil
        }
        XCTAssertEqual(reason(resolve(nil)), .noSnapshot)
        let e = envelope()
        XCTAssertEqual(reason(resolve(e, now: e.expiresAt)), .expired)
        // Midnight boundary: a yesterday envelope is not startable just after midnight.
        XCTAssertEqual(reason(resolve(e, now: e.expiresAt.addingTimeInterval(1))), .expired)
        XCTAssertNotNil(resolve(e, now: e.expiresAt.addingTimeInterval(-1)).launch)
        let invalidated = WatchCoachHistoryState(invalidatedAt: noon.addingTimeInterval(60), generation: 1)
        XCTAssertEqual(reason(resolve(e, now: noon.addingTimeInterval(120), history: invalidated)), .historyChanged)
        XCTAssertEqual(reason(resolve(nil, history: invalidated)), .historyChanged)
        // A snapshot delivered after the invalidation is usable again.
        let fresh = envelope(issued: noon.addingTimeInterval(300))
        XCTAssertNotNil(resolve(fresh, now: noon.addingTimeInterval(400), history: invalidated).launch)
        for a in [resolve(nil), resolve(e, now: e.expiresAt)] { XCTAssertNil(a.launch) }
    }

    func testCacheGeneratesOncePerFingerprintAndGeneration() {
        let cache = WatchSuggestResolutionCache()
        let e = envelope()
        for _ in 0..<5 { _ = cache.resolve(envelope: e, now: noon, calendar: cal) }
        XCTAssertEqual(cache.generationCount, 1)
        let g = WatchCoachHistoryState(invalidatedAt: noon.addingTimeInterval(-60), generation: 1)
        _ = cache.resolve(envelope: e, now: noon, historyState: g, calendar: cal)
        XCTAssertEqual(cache.generationCount, 2)
        _ = cache.resolve(envelope: envelope(issued: noon.addingTimeInterval(10)), now: noon, historyState: g, calendar: cal)
        XCTAssertEqual(cache.generationCount, 3)
        XCTAssertNil(cache.resolve(envelope: e, now: e.expiresAt, historyState: g, calendar: cal).launch)
    }

    func testNoLocalFallbackSourcesRemain() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CadenceFeatures")
        let banned = ["WatchLocalSuggestionGenerator", "makeLocal(", "Starter workout", "Suggested on Apple Watch"]
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.contains("WatchLocalSuggestionGenerator.swift"))
        for f in files {
            let text = try String(contentsOf: root.appendingPathComponent(f), encoding: .utf8)
            for b in banned { XCTAssertFalse(text.contains(b), "\(f) contains \(b)") }
        }
    }
}
