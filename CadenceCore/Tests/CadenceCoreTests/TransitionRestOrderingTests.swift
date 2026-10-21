import Foundation
import Testing
@testable import CadenceCore

@Suite struct TransitionRestOrderingTests {
    private func strength(_ name: String, order: Int, transition: Int?,
                          rest: Int = 90, group: SupersetGroupID? = nil) -> StrengthItem {
        StrengthItem(exerciseKey: ExerciseKey(raw: name), order: order,
                     defaultRestSeconds: rest,
                     sets: (0..<3).map { PrescribedSet(setIndex: $0, repTarget: .exact(5)) },
                     schemeApplied: nil, supersetGroup: group, laterality: nil,
                     progression: nil, performerOverrides: nil,
                     transitionRestSeconds: transition)
    }

    private func session(_ items: [StrengthItem]) -> Session {
        Session(title: "S", items: items.map { .strength($0) })
    }

    private func keys(_ s: Session) -> [String] {
        s.orderedItems.compactMap { if case let .strength(i) = $0 { return i.exerciseKey.raw } else { return nil } }
    }

    @Test func movesLongestTransitionLastAndSavesRest() {
        let s = session([strength("squat", order: 0, transition: 300),
                         strength("curl", order: 1, transition: 60),
                         strength("row", order: 2, transition: 120)])
        let r = TransitionRestOrdering.optimize(s)
        #expect(keys(r.session) == ["curl", "row", "squat"])
        #expect(r.transitionRestBeforeSeconds == 360)
        #expect(r.transitionRestAfterSeconds == 180)
        #expect(r.savedSeconds == 180)
    }

    @Test func deterministicAndIdempotent() {
        let s = session([strength("a", order: 0, transition: 200),
                         strength("b", order: 1, transition: 200),
                         strength("c", order: 2, transition: 100)])
        let r1 = TransitionRestOrdering.optimize(s)
        #expect(r1 == TransitionRestOrdering.optimize(s))
        #expect(TransitionRestOrdering.optimize(r1.session).session == r1.session)
    }

    @Test func pinnedAndSupersetConstraintsPreserved() {
        let g = SupersetGroupID(raw: "g1")
        let a = strength("a", order: 0, transition: 400)
        let b = strength("b", order: 1, transition: 50, group: g)
        let c = strength("c", order: 2, transition: 50, group: g)
        let d = strength("d", order: 3, transition: 10)
        let s = session([a, b, c, d])
        let pinned = TransitionRestOrdering.optimize(s, pinnedItemIDs: [a.id])
        #expect(keys(pinned.session) == ["a", "d", "b", "c"])
        let free = TransitionRestOrdering.optimize(s)
        #expect(keys(free.session) == ["b", "c", "d", "a"])
        let lastPinned = TransitionRestOrdering.optimize(s, pinnedItemIDs: [d.id])
        #expect(lastPinned.session == s)
    }

    @Test func contentAndSetRestUnchanged() {
        let items = [strength("a", order: 0, transition: 300, rest: 120),
                     strength("b", order: 1, transition: 30, rest: 45)]
        let r = TransitionRestOrdering.optimize(session(items))
        for case let .strength(i) in r.session.items {
            let orig = items.first { $0.id == i.id }!
            var o = orig; o.order = i.order
            #expect(i == o)
            #expect(i.totalBetweenSetRestSeconds == orig.totalBetweenSetRestSeconds)
        }
    }
}
