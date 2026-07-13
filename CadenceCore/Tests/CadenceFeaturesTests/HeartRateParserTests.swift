import XCTest
import Foundation
import CadenceFeatures

/// Moved from Cadence/CadenceTests/CadenceTests.swift (test-pyramid Phase 2).
/// The BLE 0x2A37 parser now lives in CadenceFeatures.HeartRateParser.
final class HeartRateParserTests: XCTestCase {
    func testParses8BitFormat() {
        // flags=0x00 (8-bit), value=72
        XCTAssertEqual(HeartRateParser.parse(Data([0x00, 72])), 72)
    }

    func testParses16BitFormat() {
        // flags=0x01 (16-bit), value=300 (0x012C) little-endian
        XCTAssertEqual(HeartRateParser.parse(Data([0x01, 0x2C, 0x01])), 300)
    }

    func testRejectsEmpty() {
        XCTAssertNil(HeartRateParser.parse(Data()))
        XCTAssertNil(HeartRateParser.parse(Data([0x00])))
    }
}
