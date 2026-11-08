import Foundation
import CadenceCore

/// Display rows for the compact Today card showing the stable strength and
/// cardio recommendations side by side. Pure; no coach computation.
public enum TodayRecommendationBadge: Equatable, Sendable {
    case recommended, optionalToday, alsoPlannedToday

    public var label: String {
        switch self {
        case .recommended: return String(localized: "Recommended")
        case .optionalToday: return String(localized: "Optional today")
        case .alsoPlannedToday: return String(localized: "Also planned today")
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
            let session = slot.session
            return TodayRecommendationRow(
                modality: modality, session: session, badge: badge,
                modalityLabel: modality == .strength ? String(localized: "Strength") : String(localized: "Cardio"),
                systemImage: modality == .strength ? "dumbbell.fill" : "heart.fill",
                title: session.title,
                durationText: session.durationMinutes.map { String(localized: "\($0) min") },
                rationale: session.subtitle,
                citationIds: session.citationIds)
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
