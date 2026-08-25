import XCTest
@testable import CadenceCore

/// strength-pivot P3 — weekly volume landmarks (MEV/MAV/MRV) and zone classification.
final class VolumeLandmarksTests: XCTestCase {

    func testBandsAreOrderedForEveryPartAndLevel() {
        for part in MuscleGroup.canonicalOrder {
            for level in ExperienceLevel.allCases {
                let b = VolumeLandmarks.bands(for: part, experience: level)
                XCTAssertLessThan(b.mev, b.mav, "\(part)/\(level): MEV !< MAV")
                XCTAssertLessThan(b.mav, b.mrv, "\(part)/\(level): MAV !< MRV")
            }
        }
    }

    func testExperienceScalesVolumeUp() {
        let beg = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .beginner)
        let int = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .intermediate)
        let adv = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .advanced)
        XCTAssertLessThan(beg.mev, int.mev)
        XCTAssertLessThan(int.mev, adv.mev)
        XCTAssertLessThan(beg.mrv, adv.mrv)
    }

    func testZoneClassification() {
        // Intermediate chest baseline: MEV 8, MAV 16, MRV 22.
        XCTAssertEqual(VolumeLandmarks.zone(sets: 4, for: MuscleGroup.chest, experience: .intermediate), .belowMEV)
        XCTAssertEqual(VolumeLandmarks.zone(sets: 12, for: MuscleGroup.chest, experience: .intermediate), .productive)
        XCTAssertEqual(VolumeLandmarks.zone(sets: 18, for: MuscleGroup.chest, experience: .intermediate), .approachingMRV)
        XCTAssertEqual(VolumeLandmarks.zone(sets: 25, for: MuscleGroup.chest, experience: .intermediate), .overMRV)
    }

    func testBoundaryIsInclusiveAtMEV() {
        let b = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .intermediate)
        // Exactly MEV is no longer below it.
        XCTAssertEqual(VolumeLandmarks.zone(sets: b.mev, for: MuscleGroup.chest, experience: .intermediate), .productive)
    }

    // MARK: Per-muscle-group bands (DB++ adoption phase 4)

    func testBandsAreOrderedForEveryGroupAndLevel() {
        for group in MuscleGroup.allCases {
            for level in ExperienceLevel.allCases {
                let b = VolumeLandmarks.bands(for: group, experience: level)
                XCTAssertLessThan(b.mev, b.mav, "\(group)/\(level): MEV !< MAV")
                XCTAssertLessThan(b.mav, b.mrv, "\(group)/\(level): MAV !< MRV")
            }
        }
    }

    /// Groups the coach does not target get deliberately low bands, so opting one
    /// in never demands a training block for it.
    func testUntrackedGroupsHaveGentlerBandsThanTrackedOnes() {
        let neck = VolumeLandmarks.bands(for: MuscleGroup.neck, experience: .intermediate)
        let chest = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .intermediate)
        XCTAssertLessThan(neck.mev, chest.mev)
        XCTAssertLessThan(neck.mrv, chest.mrv)
    }

    /// The transitional body-part band is the widest of its members, so a part
    /// holding a large muscle is not judged against a small one's ceiling.
    func testGroupBandsCoverEveryMuscleGroup() {
        let legs = VolumeLandmarks.bands(for: MuscleGroup.quadriceps, experience: .intermediate)
        let quads = VolumeLandmarks.bands(for: MuscleGroup.quadriceps, experience: .intermediate)
        let hipFlexors = VolumeLandmarks.bands(for: MuscleGroup.hipFlexors, experience: .intermediate)
        XCTAssertEqual(legs.mev, quads.mev)
        XCTAssertEqual(legs.mrv, quads.mrv)
        XCTAssertGreaterThan(legs.mev, hipFlexors.mev)
    }

    func testProductiveTargetSitsInsideTheAdaptiveBand() {
        for group in MuscleGroup.allCases {
            let b = VolumeLandmarks.bands(for: group, experience: .intermediate)
            let target = VolumeLandmarks.productiveTarget(for: group, experience: .intermediate)
            XCTAssertGreaterThanOrEqual(target, b.mev, "\(group)")
            XCTAssertLessThanOrEqual(target, b.mav, "\(group)")
        }
    }
}
