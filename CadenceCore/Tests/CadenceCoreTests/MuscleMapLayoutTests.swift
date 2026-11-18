import Testing
@testable import CadenceCore

struct MuscleMapLayoutTests {
    @Test func sourceIsSplitIntoTwoAspectPreservingHalves() {
        #expect(abs(MuscleMapLayout.panelRatio -
                       MuscleMapLayout.panelPixelWidth / MuscleMapLayout.panelPixelHeight) <= 0.0001)
        #expect(MuscleMapLayout.panelRatio > 0)
        #expect(MuscleMapLayout.panelRatio < 1)
        #expect(abs(MuscleMapLayout.panelPixelWidth - 1024) <= 0.0001)
        #expect(abs(MuscleMapLayout.panelPixelHeight - 1782) <= 0.0001)
    }

    @Test func everyAnchorStaysInsideItsAssignedHalf() {
        for callout in MuscleMapLayout.callouts {
            #expect((0...1).contains(callout.anchorX), "\(callout.id)")
            #expect((0...1).contains(callout.anchorY), "\(callout.id)")
            switch callout.side {
            case .left:
                #expect(callout.anchorX < 0.5, "\(callout.id)")
            case .right:
                #expect(callout.anchorX > 0.5, "\(callout.id)")
            }
        }
    }

    @Test func calloutsAreDeterministicAndHaveBothSides() {
        let front = MuscleMapLayout.callouts(for: .front)
        let back = MuscleMapLayout.callouts(for: .back)
        #expect(front.count == 12)
        #expect(back.count == 13)
        #expect(!front.isEmpty)
        #expect(!back.isEmpty)
        #expect(front.contains { $0.side == .left })
        #expect(front.contains { $0.side == .right })
        #expect(back.contains { $0.side == .left })
        #expect(back.contains { $0.side == .right })
        let ids = MuscleMapLayout.callouts.map(\.id)
        #expect(ids.count == Set(ids).count)
        #expect(MuscleMapLayout.callouts ==
                       MuscleMapLayout.callouts(for: .front) + MuscleMapLayout.callouts(for: .back))
    }

    @Test func calloutsCoverEveryTrackedMuscleGroup() {
        let visible = Set(MuscleMapLayout.callouts.map(\.group))
        #expect(visible == Set(MuscleGroup.allCases))
    }

    @Test func specializedGroupsUseTheirOwnDefaultMapColours() {
        for group in [MuscleGroup.hipFlexors, .tibialis, .neck, .rotatorCuff] {
            #expect(MuscleMapLayout.colourGroup(for: group,
                visibleGroups: MuscleGroup.defaultTracked) == group)
            #expect(MuscleMapLayout.callouts.contains { $0.group == group })
        }
    }

    @Test func visibleCalloutsCanMatchTheVolumeScope() {
        let visible = MuscleMapLayout.callouts(
            for: .back,
            visibleGroups: MuscleGroup.defaultTracked)
        #expect(visible.contains { $0.group == .rotatorCuff })
        #expect(visible.contains { $0.group == .lats })
    }
}
