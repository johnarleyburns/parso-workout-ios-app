import CadenceFeatures
import Foundation
import CadenceCore

/// Phase B (field-test-fixes): hero copy from logged work, not planned
/// candidates. Extracted from CoachDecisionCardView so the logic is pure,
/// headlessly testable, and guaranteed to reflect what was actually trained.
public enum CoachHeroPresenter {

    public struct Content: Equatable {
        public let title: String
        public let subtitle: String

        public init(title: String, subtitle: String) {
            self.title = title
            self.subtitle = subtitle
        }
    }

    /// Computes the hero title and subtitle for the top coach card.
    ///
    /// - Parameters:
    ///   - primaryKind: The primary recommendation's kind
    ///   - primaryTitle: `decision.primary.title`
    ///   - primarySubtitle: `decision.primary.subtitle`
    ///   - todayPlannedCount: `decision.todayPlannedRecommendations.count`
    ///   - isCompleteState: True when plan-adherence considers today complete
    ///   - planAdherenceCompletedKind: Kind that completed the plan, if any
    ///   - completedDescription: Description for the completed state
    ///   - recentFactText: Optional first observed-fact summary
    ///   - hasTodayStrengthCompleted: True when a strength event was completed today
    ///   - todayLoggedExerciseNames: Exercise names from completed strength today, deduped
    public static func present(
        primaryKind: CoachSessionKind,
        primaryTitle: String,
        primarySubtitle: String,
        todayPlannedCount: Int,
        isCompleteState: Bool,
        planAdherenceCompletedKind: CoachSessionKind?,
        completedDescription: String?,
        recentFactText: String,
        hasTodayStrengthCompleted: Bool,
        todayLoggedExerciseNames: [String]
    ) -> Content {
        // ── Complete plan state ──────────────────────────────────────────
        if isCompleteState, let desc = completedDescription {
            let title: String
            switch planAdherenceCompletedKind {
            case .strength:
                title = {
                    #if os(Linux)
                    "You put in the work"
                    #else
                    String(localized: "You put in the work", bundle: FeatureLocalization.bundle)
                    #endif
                }()
            case .easyAerobic, .moderateAerobic:
                title = {
                    #if os(Linux)
                    "Cardio banked for today"
                    #else
                    String(localized: "Cardio banked for today", bundle: FeatureLocalization.bundle)
                    #endif
                }()
            case .vo2Intervals:
                title = {
                    #if os(Linux)
                    "Speed work in the books"
                    #else
                    String(localized: "Speed work in the books", bundle: FeatureLocalization.bundle)
                    #endif
                }()
            case .recovery:
                title = {
                    #if os(Linux)
                    "Recovery done for today"
                    #else
                    String(localized: "Recovery done for today", bundle: FeatureLocalization.bundle)
                    #endif
                }()
            case .rest:
                title = {
                    #if os(Linux)
                    "Rest earned for today"
                    #else
                    String(localized: "Rest earned for today", bundle: FeatureLocalization.bundle)
                    #endif
                }()
            case .assessment:
                title = {
                    #if os(Linux)
                    "Baseline in the books"
                    #else
                    String(localized: "Baseline in the books", bundle: FeatureLocalization.bundle)
                    #endif
                }()
            case nil:
                title = {
                    #if os(Linux)
                    "Today's workouts are completed"
                    #else
                    String(localized: "Today's workouts are completed", bundle: FeatureLocalization.bundle)
                    #endif
                }()
            }
            return Content(title: title, subtitle: desc)
        }

        // ── Single remaining planned recommendation (two-a-day) ──────────
        if todayPlannedCount == 1 {
            return Content(title: primaryTitle,
                           subtitle: primarySubtitle.isEmpty ? recentFactText : primarySubtitle)
        }

        // ── Strength already completed today, primary is not strength ────
        if hasTodayStrengthCompleted && primaryKind != .strength {
            let isAerobicPrimary: Bool = {
                switch primaryKind {
                case .easyAerobic, .moderateAerobic, .vo2Intervals: return true
                default: return false
                }
            }()
            if isAerobicPrimary {
                return Content(title: primaryTitle,
                               subtitle: primarySubtitle.isEmpty ? recentFactText : primarySubtitle)
            }
            let loggedText: String = {
                let names = Array(todayLoggedExerciseNames.prefix(3))
                switch names.count {
                case 0: return ""
                case 1: return {
                    #if os(Linux)
                    "\(names[0]) logged."
                    #else
                    String(localized: "\(names[0]) logged.", bundle: FeatureLocalization.bundle)
                    #endif
                }()
                case 2: return {
                    #if os(Linux)
                    "\(names[0]) and \(names[1]) logged."
                    #else
                    String(localized: "\(names[0]) and \(names[1]) logged.", bundle: FeatureLocalization.bundle)
                    #endif
                }()
                default: return {
                    #if os(Linux)
                    "\(names[0]), \(names[1]), and \(names[2]) logged."
                    #else
                    String(localized: "\(names[0]), \(names[1]), and \(names[2]) logged.", bundle: FeatureLocalization.bundle)
                    #endif
                }()
                }
            }()
            let subtitle = recentFactText.isEmpty
                ? loggedText
                : "\(loggedText) \(recentFactText)"
            return Content(title: {
                #if os(Linux)
                "Strength is done today"
                #else
                String(localized: "Strength is done today", bundle: FeatureLocalization.bundle)
                #endif
            }(),
                           subtitle: subtitle.trimmingCharacters(in: .whitespaces))
        }

        // ── Rest day ────────────────────────────────────────────────────
        if primaryKind == .rest {
            return Content(title: {
                #if os(Linux)
                "Rest is training too"
                #else
                String(localized: "Rest is training too", bundle: FeatureLocalization.bundle)
                #endif
            }(),
                           subtitle: primarySubtitle.isEmpty ? recentFactText : primarySubtitle)
        }

        // ── Default ─────────────────────────────────────────────────────
        return Content(title: primaryTitle,
                       subtitle: primarySubtitle.isEmpty ? recentFactText : primarySubtitle)
    }
}
