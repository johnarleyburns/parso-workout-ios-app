import Foundation

/// Free (non-gated) coach *insight* noticing that intense cardio is already in
/// the books today ("coach suggests" plan, Phase 2). It observes — it never
/// blocks or downgrades anything: strength stays fully available, and the
/// easy-cardio add-on suppression happens in `CoachAddOnEngine` separately.
public enum SameDayLoadInsight {

    /// An insight when today already holds ≥1 intense cardio session (or ≥2
    /// cardio sessions of any intensity). nil otherwise.
    public static func insight(facts: CoachFacts) -> Insight? {
        let cardioToday = facts.todayCompletedEvents.filter(\.isAerobic)
        let intense = cardioToday.filter(\.isHard)
        guard !intense.isEmpty || cardioToday.count >= 2 else { return nil }

        let counted = intense.isEmpty ? cardioToday : intense
        let names = counted.compactMap { event -> String? in
            switch event.kind {
            case .aerobic(let d), .intervals(let d): return d.modality.displayName
            default: return nil
            }
        }
        let list = summarize(names)
        let count = counted.count
        let sessionsPhrase = intense.isEmpty
            ? "\(count) cardio sessions"
            : "\(count) intense session\(count == 1 ? "" : "s")"

        return Insight(
            id: "sameDayLoad.intenseCardio",
            kind: .intensity,
            title: "Hard work already banked today",
            message: "You've already logged \(list) today — \(sessionsPhrase). No extra cardio needed.",
            detail: "Intense sessions like HIIT and boxing count as real training load, so the coach won't push more easy cardio on top of them. Anything you still choose to do is yours to call — just weigh that recovery, not more work, is what turns today's load into fitness.",
            citation: CitationRegistry.meeusenOvertraining2013,
            severity: .info)
    }

    private static func summarize(_ names: [String]) -> String {
        switch names.count {
        case 0: return "intense cardio"
        case 1: return names[0]
        case 2: return "\(names[0]) + \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " + " + names[names.count - 1]
        }
    }
}
