import XCTest
@testable import CadenceCore

/// strength-pivot P3 — weekly volume landmarks (MEV/MAV/MRV) and zone classification.
final class VolumeLandmarksTests: XCTestCase {

    func testBandsAreOrderedForEveryPartAndLevel() {
        for part in BodyPart.allCases {
            for level in ExperienceLevel.allCases {
                let b = VolumeLandmarks.bands(for: part, experience: level)
                XCTAssertLessThan(b.mev, b.mav, "\(part)/\(level): MEV !< MAV")
                XCTAssertLessThan(b.mav, b.mrv, "\(part)/\(level): MAV !< MRV")
            }
        }
    }

    func testExperienceScalesVolumeUp() {
        let beg = VolumeLandmarks.bands(for: .chest, experience: .beginner)
        let int = VolumeLandmarks.bands(for: .chest, experience: .intermediate)
        let adv = VolumeLandmarks.bands(for: .chest, experience: .advanced)
        XCTAssertLessThan(beg.mev, int.mev)
        XCTAssertLessThan(int.mev, adv.mev)
        XCTAssertLessThan(beg.mrv, adv.mrv)
    }

    func testZoneClassification() {
        // Intermediate chest baseline: MEV 8, MAV 16, MRV 22.
        XCTAssertEqual(VolumeLandmarks.zone(sets: 4, for: .chest, experience: .intermediate), .belowMEV)
        XCTAssertEqual(VolumeLandmarks.zone(sets: 12, for: .chest, experience: .intermediate), .productive)
        XCTAssertEqual(VolumeLandmarks.zone(sets: 18, for: .chest, experience: .intermediate), .approachingMRV)
        XCTAssertEqual(VolumeLandmarks.zone(sets: 25, for: .chest, experience: .intermediate), .overMRV)
    }

    func testBoundaryIsInclusiveAtMEV() {
        let b = VolumeLandmarks.bands(for: .chest, experience: .intermediate)
        // Exactly MEV is no longer below it.
        XCTAssertEqual(VolumeLandmarks.zone(sets: b.mev, for: .chest, experience: .intermediate), .productive)
    }
}
