import Testing
import Foundation
import CadenceFeatures
import CadenceWorkoutFeatures

/// Moved from Cadence/CadenceTests/CadenceTests.swift (test-pyramid Phase 2).
/// The BLE 0x2A37 parser now lives in CadenceFeatures.HeartRateParser.
struct HeartRateParserTests {
    @Test func parses8BitFormat() {
        // flags=0x00 (8-bit), value=72
        #expect(HeartRateParser.parse(Data([0x00, 72])) == 72)
    }

    @Test func parses16BitFormat() {
        // flags=0x01 (16-bit), value=300 (0x012C) little-endian
        #expect(HeartRateParser.parse(Data([0x01, 0x2C, 0x01])) == 300)
    }

    @Test func rejectsEmpty() {
        #expect(HeartRateParser.parse(Data()) == nil)
        #expect(HeartRateParser.parse(Data([0x00])) == nil)
    }
}
