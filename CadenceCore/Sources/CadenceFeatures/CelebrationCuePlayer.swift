import Foundation

/// The small testable seam between `CuePolicy.cue(for:)` and the app's actual
/// haptic/sound firing. The firing surface itself (`Haptics`, `IntervalCues`'s
/// tone/speech) lives in the `Cadence` app target — it imports UIKit/AVFoundation
/// and can't be headlessly `swift test`-ed — so this wrapper exists purely to
/// make the *decision* step ("given this celebration style and event, what
/// should fire, and should it include sound?") unit-testable from
/// `CadenceFeaturesTests` without needing a device or simulator.
///
/// Call sites (`SessionView+SetActions.swift`, `InlineSetEditorView.swift`,
/// `IntervalCues.completed()`, `RecordAssessmentView.swift`) construct one of
/// these from the persisted `AppSettings.celebrationStyle`, ask for a
/// `Decision`, and then: always fire `Haptics.play(decision.kind)`, and only
/// play the accompanying sound/speech when `decision.playsSound` is true. That
/// last wiring step is SwiftUI view code and isn't itself exercised by
/// `swift test` — see each call site's manual-verification note.
public struct CelebrationCuePlayer: Equatable, Sendable {
    /// What should fire for a given `CueEvent`, and whether the sound/speech
    /// accompaniment (as opposed to just the haptic) should play alongside it.
    public struct Decision: Equatable, Sendable {
        public let kind: CueKind
        /// `.full` plays both haptic and sound/speech; `.quiet` keeps the
        /// haptic but drops the sound/speech. (`.off` never reaches here for a
        /// celebration-kind event — `decide(for:)` returns `nil` instead.)
        public let playsSound: Bool

        public init(kind: CueKind, playsSound: Bool) {
            self.kind = kind
            self.playsSound = playsSound
        }
    }

    public let policy: CuePolicy

    public init(policy: CuePolicy) {
        self.policy = policy
    }

    public init(celebrationStyle: CelebrationStyle) {
        self.policy = CuePolicy(celebrationStyle: celebrationStyle)
    }

    /// The cue to fire for `event`, or `nil` when the policy suppresses it
    /// entirely (e.g. `.off` for a celebration-kind event).
    public func decide(for event: CueEvent) -> Decision? {
        guard let kind = policy.cue(for: event) else { return nil }
        return Decision(kind: kind, playsSound: policy.celebrationStyle == .full)
    }
}
