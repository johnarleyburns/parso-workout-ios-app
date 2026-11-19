#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct FITExportTests {
    private func makeStore() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @Test func fITRoundTripPreservesCardioInterchangeData() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let cardio = ExportCardio(
            id: UUID(), type: CardioType.run.rawValue, start: start,
            end: start.addingTimeInterval(600), distanceMeters: 5_000,
            activeEnergyKcal: 410, avgHeartRate: 148, source: CardioSource.watch.rawValue,
            maxHeartRate: 172,
            hrSamples: [ExportHRSample(t: 0, bpm: 140), ExportHRSample(t: 60, bpm: 155)],
            routeSamples: [ExportRouteSample(t: 0, lat: 37.0, lon: -122.0, elevation: 10),
                           ExportRouteSample(t: 60, lat: 37.001, lon: -122.001, elevation: 12)])
        let original = CadenceExport(sessions: [], cardio: [cardio])

        let data = try DataExport.encodeFIT(original)
        #expect(DataExport.isFIT(data))
        #expect(data[8..<12] == Data(".FIT".utf8))

        let decoded = try DataExport.decodeFIT(data)
        let imported = try #require(decoded.cardio.first)
        #expect(decoded.cardio.count == 1)
        let decodedAgain = try DataExport.decodeFIT(data)
        #expect(decoded.cardio.map(\.id) == decodedAgain.cardio.map(\.id),
                       "Repeated FIT imports must use stable IDs for deduplication")
        #expect(imported.type == CardioType.run.rawValue)
        #expect(abs(try #require(imported.distanceMeters) - 5_000) <= 1)
        #expect(abs(try #require(imported.activeEnergyKcal) - 410) <= 1)
        #expect(imported.hrSamples?.count == 2)
        #expect(imported.routeSamples?.count == 2)
        #expect(imported.source == CardioSource.iphone.rawValue)
        #expect(abs((imported.routeSamples?.first?.lat ?? 0) - 37.0) <= 0.00001)
        #expect(abs((imported.routeSamples?.first?.lon ?? 0) - -122.0) <= 0.00001)
        #expect(abs(imported.start.timeIntervalSince(start) - 0) <= 1)
        #expect(abs(try #require(imported.end).timeIntervalSince(start) - 600) <= 1)
    }

    @Test func decodeAnySniffsFITBeforeJSON() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let cardio = ExportCardio(id: UUID(), type: CardioType.cycle.rawValue,
                                  start: start, end: start.addingTimeInterval(300),
                                  distanceMeters: 2_000, activeEnergyKcal: nil,
                                  avgHeartRate: nil, source: CardioSource.iphone.rawValue)
        let data = try DataExport.encodeFIT(CadenceExport(sessions: [], cardio: [cardio]))
        #expect(try DataExport.decodeAny(data).cardio.count == 1)
    }

    @Test func repeatedFITImportIsIdempotentInStore() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let cardio = ExportCardio(id: UUID(), type: CardioType.run.rawValue,
                                  start: start, end: start.addingTimeInterval(300),
                                  distanceMeters: 2_000, activeEnergyKcal: 100,
                                  avgHeartRate: 140, source: CardioSource.iphone.rawValue)
        let data = try DataExport.encodeFIT(CadenceExport(sessions: [], cardio: [cardio]))
        let imported = try DataExport.decodeFIT(data)
        let context = try makeStore()

        #expect(try WorkoutRepository.merge(imported, in: context) == 1)
        #expect(try WorkoutRepository.merge(imported, in: context) == 0,
                       "Importing the same FIT file twice must not duplicate cardio")
    }

    @Test func fITRejectsCorruptedData() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let cardio = ExportCardio(id: UUID(), type: CardioType.walk.rawValue,
                                  start: start, end: start.addingTimeInterval(60),
                                  distanceMeters: 500, activeEnergyKcal: nil,
                                  avgHeartRate: nil, source: CardioSource.watch.rawValue)
        var data = try DataExport.encodeFIT(CadenceExport(sessions: [], cardio: [cardio]))
        data[data.count - 1] ^= 0xFF
        #expect(throws: (any Error).self) { try DataExport.decodeFIT(data) }
    }
}
#endif
