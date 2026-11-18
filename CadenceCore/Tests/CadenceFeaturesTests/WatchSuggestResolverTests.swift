import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WatchSuggestResolverTests {
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

    @Test func watchLaunchEqualsPhoneMaterializationForSameEnvelope() throws {
        let e = envelope()
        let option = try #require(CoachSuggestionService.generate(from: e.snapshot))
        let r = e.snapshot.request
        let phonePlan = SuggestedWorkoutPresenter.editablePlan(
            for: option, unit: r.unit, warmupMinutes: r.warmupMinutes, cooldownMinutes: r.cooldownMinutes)
        let phone = try #require(CoachWatchTodayBridge.suggestedStrengthSession(from: phonePlan))
        let launch = try #require(resolve(e).launch)
        #expect(launch.title == phone.label)
        #expect(launch.exerciseNames == phone.exerciseNames)
        #expect(launch.repLadder == phone.repLadder)
        #expect(launch.planPayload == phone.planPayload)
        #expect(CoachSuggestionService.generate(from: e.snapshot) == option)
    }

    @Test func needsSyncStatesHaveNoLaunch() throws {
        func reason(_ a: WatchSuggestAvailability) -> WatchSuggestAvailability.Reason? {
            if case .needsSync(let r, _) = a { return r }
            return nil
        }
        #expect(reason(resolve(nil)) == .noSnapshot)
        let e = envelope()
        #expect(reason(resolve(e, now: e.expiresAt)) == .expired)
        // Midnight boundary: a yesterday envelope is not startable just after midnight.
        #expect(reason(resolve(e, now: e.expiresAt.addingTimeInterval(1))) == .expired)
        #expect(resolve(e, now: e.expiresAt.addingTimeInterval(-1)).launch != nil)
        let invalidated = WatchCoachHistoryState(invalidatedAt: noon.addingTimeInterval(60), generation: 1)
        #expect(reason(resolve(e, now: noon.addingTimeInterval(120), history: invalidated)) == .historyChanged)
        #expect(reason(resolve(nil, history: invalidated)) == .historyChanged)
        // A snapshot delivered after the invalidation is usable again.
        let fresh = envelope(issued: noon.addingTimeInterval(300))
        #expect(resolve(fresh, now: noon.addingTimeInterval(400), history: invalidated).launch != nil)
        for a in [resolve(nil), resolve(e, now: e.expiresAt)] { #expect(a.launch == nil) }
    }

    @Test func cacheGeneratesOncePerFingerprintAndGeneration() {
        let cache = WatchSuggestResolutionCache()
        let e = envelope()
        for _ in 0..<5 { _ = cache.resolve(envelope: e, now: noon, calendar: cal) }
        #expect(cache.generationCount == 1)
        let g = WatchCoachHistoryState(invalidatedAt: noon.addingTimeInterval(-60), generation: 1)
        _ = cache.resolve(envelope: e, now: noon, historyState: g, calendar: cal)
        #expect(cache.generationCount == 2)
        _ = cache.resolve(envelope: envelope(issued: noon.addingTimeInterval(10)), now: noon, historyState: g, calendar: cal)
        #expect(cache.generationCount == 3)
        #expect(cache.resolve(envelope: e, now: e.expiresAt, historyState: g, calendar: cal).launch == nil)
    }

    @Test func noLocalFallbackSourcesRemain() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CadenceWorkoutFeatures")
        let banned = ["WatchLocalSuggestionGenerator", "makeLocal(", "Starter workout", "Suggested on Apple Watch"]
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".swift") }
        #expect(!files.contains("WatchLocalSuggestionGenerator.swift"))
        for f in files {
            let text = try String(contentsOf: root.appendingPathComponent(f), encoding: .utf8)
            for b in banned { #expect(!text.contains(b), "\(f) contains \(b)") }
        }
    }
}
