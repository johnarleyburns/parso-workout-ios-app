import Testing
@testable import CadenceCore

/// strength-pivot P3 — weekly volume landmarks (MEV/MAV/MRV) and zone classification.
struct VolumeLandmarksTests {

    @Test func bandsAreOrderedForEveryPartAndLevel() {
        for part in MuscleGroup.canonicalOrder {
            for level in ExperienceLevel.allCases {
                let b = VolumeLandmarks.bands(for: part, experience: level)
                #expect(b.mev < b.mav, "\(part)/\(level): MEV !< MAV")
                #expect(b.mav < b.mrv, "\(part)/\(level): MAV !< MRV")
            }
        }
    }

    @Test func experienceScalesVolumeUp() {
        let beg = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .beginner)
        let int = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .intermediate)
        let adv = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .advanced)
        #expect(beg.mev < int.mev)
        #expect(int.mev < adv.mev)
        #expect(beg.mrv < adv.mrv)
    }

    @Test func zoneClassification() {
        // Intermediate chest baseline: MEV 8, MAV 16, MRV 22.
        #expect(VolumeLandmarks.zone(sets: 4, for: MuscleGroup.chest, experience: .intermediate) == .belowMEV)
        #expect(VolumeLandmarks.zone(sets: 12, for: MuscleGroup.chest, experience: .intermediate) == .productive)
        #expect(VolumeLandmarks.zone(sets: 18, for: MuscleGroup.chest, experience: .intermediate) == .approachingMRV)
        #expect(VolumeLandmarks.zone(sets: 25, for: MuscleGroup.chest, experience: .intermediate) == .overMRV)
    }

    @Test func boundaryIsInclusiveAtMEV() {
        let b = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .intermediate)
        // Exactly MEV is no longer below it.
        #expect(VolumeLandmarks.zone(sets: b.mev, for: MuscleGroup.chest, experience: .intermediate) == .productive)
    }

    // MARK: Per-muscle-group bands (DB++ adoption phase 4)

    @Test func bandsAreOrderedForEveryGroupAndLevel() {
        for group in MuscleGroup.allCases {
            for level in ExperienceLevel.allCases {
                let b = VolumeLandmarks.bands(for: group, experience: level)
                #expect(b.mev < b.mav, "\(group)/\(level): MEV !< MAV")
                #expect(b.mav < b.mrv, "\(group)/\(level): MAV !< MRV")
            }
        }
    }

    /// Groups the coach does not target get deliberately low bands, so opting one
    /// in never demands a training block for it.
    @Test func specializedGroupsHaveGentlerBandsThanLargerGroups() {
        let neck = VolumeLandmarks.bands(for: MuscleGroup.neck, experience: .intermediate)
        let chest = VolumeLandmarks.bands(for: MuscleGroup.chest, experience: .intermediate)
        #expect(neck.mev < chest.mev)
        #expect(neck.mrv < chest.mrv)
    }

    /// The transitional body-part band is the widest of its members, so a part
    /// holding a large muscle is not judged against a small one's ceiling.
    @Test func groupBandsCoverEveryMuscleGroup() {
        let legs = VolumeLandmarks.bands(for: MuscleGroup.quadriceps, experience: .intermediate)
        let quads = VolumeLandmarks.bands(for: MuscleGroup.quadriceps, experience: .intermediate)
        let hipFlexors = VolumeLandmarks.bands(for: MuscleGroup.hipFlexors, experience: .intermediate)
        #expect(legs.mev == quads.mev)
        #expect(legs.mrv == quads.mrv)
        #expect(legs.mev > hipFlexors.mev)
    }

    @Test func productiveTargetSitsInsideTheAdaptiveBand() {
        for group in MuscleGroup.allCases {
            let b = VolumeLandmarks.bands(for: group, experience: .intermediate)
            let target = VolumeLandmarks.productiveTarget(for: group, experience: .intermediate)
            #expect(target >= b.mev, "\(group)")
            #expect(target <= b.mav, "\(group)")
        }
    }
}
