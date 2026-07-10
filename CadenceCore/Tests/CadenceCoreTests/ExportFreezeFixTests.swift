import XCTest
import SwiftData
@testable import CadenceCore

/// Tests for the export-freeze fix: gzip compression, the summary card, the
/// comprehensive fixture round-trip, coach determinism, and scale.
final class ExportFreezeFixTests: XCTestCase {

    private func makeStore() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - Compression

    func testGzipRoundTrip() throws {
        let original = Data("The quick brown fox jumps over the lazy dog. ".utf8) as Data
        var payload = Data()
        for _ in 0..<1000 { payload.append(original) }
        let gz = try DataCompression.gzip(payload)
        XCTAssertEqual(gz[gz.startIndex], 0x1f)
        XCTAssertEqual(gz[gz.startIndex + 1], 0x8b)
        XCTAssertLessThan(gz.count, payload.count / 5, "repetitive payload should compress >5×")
        let inflated = try DataCompression.gunzip(gz)
        XCTAssertEqual(inflated, payload)
    }

    func testGzipEmpty() throws {
        let gz = try DataCompression.gzip(Data())
        XCTAssertEqual(try DataCompression.gunzip(gz), Data())
    }

    func testCRC32KnownVector() {
        // CRC32 of "123456789" is the standard 0xCBF43926.
        XCTAssertEqual(DataCompression.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testEncodeJSONGzippedRoundTripsViaDecodeAny() throws {
        let ctx = try makeStore()
        _ = try ExportRoundTripFixture.seed(into: ctx)
        let export = try WorkoutRepository.buildExport(ctx)
        let raw = try DataExport.encodeJSON(export)
        let gz = try DataExport.encodeJSONGzipped(export)
        XCTAssertLessThan(gz.count, raw.count, "gzip must be smaller than raw JSON")

        // decodeAny sniffs magic bytes: both gzip and plain JSON decode identically.
        let fromGz = try DataExport.decodeAny(gz)
        let fromPlain = try DataExport.decodeAny(raw)
        XCTAssertEqual(fromGz.sessions.count, fromPlain.sessions.count)
        XCTAssertEqual(fromGz.cardio.count, fromPlain.cardio.count)
        XCTAssertEqual(fromGz.assessments.count, fromPlain.assessments.count)
    }

    func testDecodeAnyAcceptsLegacyPlainJSONForever() throws {
        let json = """
        {"version":1,"exportedAt":"2025-06-01T00:00:00Z","sessions":[],"cardio":[]}
        """.data(using: .utf8)!
        let decoded = try DataExport.decodeAny(json)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(decoded.sessions.isEmpty)
    }

    // MARK: - Summary

    func testExportSummaryCountsEveryType() throws {
        let ctx = try makeStore()
        let prefs = try ExportRoundTripFixture.seed(into: ctx)
        let export = try WorkoutRepository.buildExport(ctx, coachPreferences: prefs.coachProfile?.exportDTO, preferences: prefs)
        let raw = try DataExport.encodeJSON(export)
        let gz = try DataExport.encodeJSONGzipped(export)
        let summary = ExportSummary.from(export, rawByteCount: raw.count, compressedByteCount: gz.count)

        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary.strengthSessionCount, 8, "8 strength structural variations")
        XCTAssertGreaterThan(summary.strengthSetCount, 8)
        // 9 base cardio types + 7 HIIT presets = 16 cardio workouts.
        XCTAssertEqual(summary.cardioCount, 16)
        XCTAssertEqual(summary.cardioByType["hiit"], 7)
        XCTAssertEqual(summary.cardioByType["run"], 2) // outdoor run + imported run
        XCTAssertGreaterThan(summary.hrSampleCount, 0)
        XCTAssertGreaterThan(summary.routeSampleCount, 0)
        XCTAssertEqual(summary.assessmentCount, AssessmentKind.allCases.count)
        XCTAssertNotNil(summary.firstWorkoutDate)
        XCTAssertNotNil(summary.lastWorkoutDate)
        XCTAssertGreaterThan(summary.daysCovered, 1)
        XCTAssertTrue(summary.includesPreferences)
        XCTAssertGreaterThan(summary.preferenceKeyCount, 10)
        XCTAssertTrue(summary.includesCoachProfile)
        XCTAssertGreaterThan(summary.coachPreferenceCount, 0)
        XCTAssertEqual(summary.rawByteCount, raw.count)
        XCTAssertEqual(summary.compressedByteCount, gz.count)
        XCTAssertLessThan(summary.compressedByteCount, summary.rawByteCount)
    }

    func testExportSummaryEmptyStore() throws {
        let ctx = try makeStore()
        let export = try WorkoutRepository.buildExport(ctx)
        let summary = ExportSummary.from(export)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.strengthSessionCount, 0)
        XCTAssertEqual(summary.cardioCount, 0)
        XCTAssertNil(summary.firstWorkoutDate)
    }

    // MARK: - Comprehensive lossless round-trip (§4.1)

    func testFixtureRoundTripsLosslessly() throws {
        let ref = Date(timeIntervalSince1970: 1_750_000_000)
        let ctxA = try makeStore()
        let prefs = try ExportRoundTripFixture.seed(into: ctxA, referenceDate: ref)
        let exportA = try WorkoutRepository.buildExport(ctxA, coachPreferences: prefs.coachProfile?.exportDTO, preferences: prefs)

        // Export → gzip → decodeAny → merge into fresh store → re-export.
        let gz = try DataExport.encodeJSONGzipped(exportA)
        let decoded = try DataExport.decodeAny(gz)

        let ctxB = try makeStore()
        _ = try WorkoutRepository.merge(decoded, in: ctxB)
        let exportB = try WorkoutRepository.buildExport(ctxB)

        // Every cardio type survives.
        let typesA = Dictionary(grouping: exportA.cardio, by: \.type).mapValues(\.count)
        let typesB = Dictionary(grouping: exportB.cardio, by: \.type).mapValues(\.count)
        XCTAssertEqual(typesA, typesB, "every cardio type + count must survive")

        // Strength sessions/sets identical.
        XCTAssertEqual(sortedSessions(exportB.sessions), sortedSessions(exportA.sessions),
                       "every strength structural variation must round-trip")
        // Cardio identical (HR + route + interval detail).
        XCTAssertEqual(sortedCardio(exportB.cardio), sortedCardio(exportA.cardio))
        // Assessments identical.
        XCTAssertEqual(exportB.assessments.sorted { $0.id.uuidString < $1.id.uuidString },
                       exportA.assessments.sorted { $0.id.uuidString < $1.id.uuidString })

        // Every HIIT preset preserved its interval detail.
        let hiitA = exportA.cardio.filter { $0.type == "hiit" }.compactMap(\.intervalDetailData).sorted()
        let hiitB = exportB.cardio.filter { $0.type == "hiit" }.compactMap(\.intervalDetailData).sorted()
        XCTAssertEqual(hiitA.count, 7)
        XCTAssertEqual(hiitA, hiitB, "all HIIT presets' interval detail must survive")

        // Preferences round-trip via the decoded blob.
        XCTAssertEqual(decoded.preferences?.unit, "pounds")
        XCTAssertEqual(decoded.preferences?.coachProfile?.aerobicPreferences.count, 2)
        XCTAssertEqual(decoded.preferences?.coachProfile?.avoidedTags, ["boring", "burpees"])
    }

    func testFixtureMergeIsIdempotent() throws {
        let ctxA = try makeStore()
        _ = try ExportRoundTripFixture.seed(into: ctxA)
        let export = try WorkoutRepository.buildExport(ctxA)
        let ctxB = try makeStore()
        let first = try WorkoutRepository.merge(export, in: ctxB)
        let second = try WorkoutRepository.merge(export, in: ctxB)
        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(second, 0, "re-import must be a no-op (dedup by id)")
    }

    // MARK: - Coach determinism (§4.2)

    func testCoachRecommendationsIdenticalAcrossExportImport() throws {
        let ref = Date(timeIntervalSince1970: 1_750_000_000)
        let ctxA = try makeStore()
        let prefs = try ExportRoundTripFixture.seed(into: ctxA, referenceDate: ref)

        func snapshot(_ ctx: ModelContext) throws -> CoachSnapshot {
            let sessions = try WorkoutRepository.allSessions(ctx)
            let cardio = try WorkoutRepository.allCardio(ctx)
            let assessments = try ctx.fetch(FetchDescriptor<Assessment>())
            return CoachSnapshotBuilder.build(
                sessions: sessions, cardio: cardio, assessments: assessments,
                hasPainToday: false, goal: .strength, experience: .advanced,
                formula: .epley,
                schedulePreferences: prefs.schedulePreferences ?? .default,
                profile: prefs.coachProfile ?? .empty,
                now: ref)
        }

        let snapA = try snapshot(ctxA)

        let export = try WorkoutRepository.buildExport(ctxA, coachPreferences: prefs.coachProfile?.exportDTO, preferences: prefs)
        let decoded = try DataExport.decodeAny(try DataExport.encodeJSONGzipped(export))
        let ctxB = try makeStore()
        _ = try WorkoutRepository.merge(decoded, in: ctxB)
        let snapB = try snapshot(ctxB)

        XCTAssertEqual(snapB.decision.primary.title, snapA.decision.primary.title,
                       "primary recommendation must be identical after export→import at pinned referenceDate")
        XCTAssertEqual(snapB.insights.map(\.title), snapA.insights.map(\.title),
                       "insight set must be identical after round-trip")
        XCTAssertEqual(snapB.behindPlan, snapA.behindPlan)
    }

    // MARK: - Scale (§4.3)

    func testLargeExportEncodesAndCompresses() throws {
        // Build the export DTO directly at scale (50 workouts × 3,600 HR + 3,600
        // route samples ≈ multi-MB). This exercises the encode + gzip path — the
        // stage that used to block the main thread — without paying the cost of
        // 360k SwiftData inserts, which are irrelevant to what's under test.
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        var cardio: [ExportCardio] = []
        for w in 0..<50 {
            let start = base.addingTimeInterval(Double(w) * 86_400)
            var hr: [ExportHRSample] = []
            var route: [ExportRouteSample] = []
            hr.reserveCapacity(3600); route.reserveCapacity(3600)
            for i in 0..<3600 {
                hr.append(ExportHRSample(t: Double(i), bpm: 140 + Double(i % 30)))
                route.append(ExportRouteSample(t: Double(i), lat: 37.0 + Double(i) * 1e-5,
                                               lon: -122.0, elevation: 10))
            }
            cardio.append(ExportCardio(id: UUID(), type: CardioType.run.rawValue, start: start,
                                       end: start.addingTimeInterval(3600), distanceMeters: 10000,
                                       activeEnergyKcal: nil, avgHeartRate: 150, source: CardioSource.iphone.rawValue,
                                       hrSamples: hr, routeSamples: route))
        }
        let export = CadenceExport(sessions: [], cardio: cardio)
        XCTAssertEqual(export.cardio.count, 50)
        let raw = try DataExport.encodeJSON(export)
        let gz = try DataExport.encodeJSONGzipped(export)
        XCTAssertGreaterThan(raw.count, 1_000_000, "50×3600 HR+route should be multi-MB raw")
        XCTAssertLessThan(gz.count, raw.count / 5, "gzip should be ≫5× smaller on sample-heavy data")
        // Round-trips back losslessly.
        let decoded = try DataExport.decodeAny(gz)
        XCTAssertEqual(decoded.cardio.reduce(0) { $0 + ($1.hrSamples?.count ?? 0) }, 50 * 3600)
    }

    // MARK: helpers

    private func sortedSessions(_ s: [ExportSession]) -> [ExportSession] {
        s.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private func sortedCardio(_ c: [ExportCardio]) -> [ExportCardio] {
        c.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
