import CadenceFeatures
import Foundation
import CadenceCore

/// Display rows for the compact Today card showing the stable strength and
/// cardio recommendations side by side. Pure; no coach computation.
public enum TodayRecommendationBadge: Equatable, Sendable {
    case recommended, optionalToday, alsoPlannedToday

    public var label: String {
        switch self {
        case .recommended: return {
            #if os(Linux)
            "Recommended"
            #else
            String(localized: "Recommended")
            #endif
        }()
        case .optionalToday: return {
            #if os(Linux)
            "Optional today"
            #else
            String(localized: "Optional today")
            #endif
        }()
        case .alsoPlannedToday: return {
            #if os(Linux)
            "Also planned today"
            #else
            String(localized: "Also planned today")
            #endif
        }()
        }
    }
}

public struct TodayRecommendationRow: Equatable, Sendable, Identifiable {
    public let modality: DailyRecommendationModality
    public let session: CoachSession
    public let badge: TodayRecommendationBadge
    public let modalityLabel: String
    public let systemImage: String
    public let title: String
    public let durationText: String?
    public let rationale: String
    public let citationIds: [String]
    public var id: DailyRecommendationModality { modality }
    public var startIdentifier: String { "home.todayRecommendation.\(modality.rawValue).start" }
}

public enum TodayRecommendationRowsPresenter {
    public static func rows(slots: [DailyRecommendationSlot], allowsTwoADays: Bool) -> [TodayRecommendationRow] {
        return DailyRecommendationModality.allCases.compactMap { modality in
            // The slot's label alone is not sufficient: a stale or malformed
            // snapshot must never put a cardio session in the Strength row (or
            // vice versa). Keep the modality boundary at the rendering and
            // routing point as a final safety check.
            guard let slot = slots.first(where: {
                $0.modality == modality && session($0.session, matches: modality)
            }) else { return nil }
            let badge: TodayRecommendationBadge = !slot.isCompanion
                ? .recommended
                : (allowsTwoADays ? .alsoPlannedToday : .optionalToday)
            let matchedSession = slot.session
            return TodayRecommendationRow(
                modality: modality, session: matchedSession, badge: badge,
                modalityLabel: modality == .strength ? {
                    #if os(Linux)
                    "Strength"
                    #else
                    String(localized: "Strength")
                    #endif
                }() : {
                    #if os(Linux)
                    "Cardio"
                    #else
                    String(localized: "Cardio")
                    #endif
                }(),
                systemImage: modality == .strength ? "dumbbell.fill" : "heart.fill",
                title: matchedSession.title,
                durationText: matchedSession.durationMinutes.map { minutes in
                    #if os(Linux)
                    "\(minutes) min"
                    #else
                    String(localized: "\(minutes) min")
                    #endif
                },
                rationale: matchedSession.subtitle,
                citationIds: matchedSession.citationIds)
        }
    }

    private static func session(_ session: CoachSession,
                                matches modality: DailyRecommendationModality) -> Bool {
        switch modality {
        case .strength:
            session.kind == .strength
        case .cardio:
            session.isAerobic
        }
    }
}
