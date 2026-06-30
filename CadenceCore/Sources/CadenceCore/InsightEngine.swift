import Foundation

/// The forward-chaining inference engine (§03), read-only slice for P3. Runs the
/// `KnowledgeBase.p3Rules` over a `TrainingFacts` snapshot and returns a ranked,
/// de-duplicated list of cited `Insight`s. Pure and deterministic: identical facts
/// always yield identical, idempotent output.
public enum InsightEngine {

    /// All insights, highest-priority first. Never empty — a user with no logged
    /// history gets a single cold-start insight so the Coach card always has
    /// something cited to show.
    public static func run(_ facts: TrainingFacts) -> [Insight] {
        // Cold-start only when there's nothing at all to reason about — no logged
        // sets and no assessment history.
        guard facts.totalWorkingSets > 0 || !facts.assessments.isEmpty else { return [coldStart] }

        // Forward-chain every rule, then resolve to a stable ranked order.
        var produced: [(rulePriority: Int, insight: Insight)] = []
        for rule in KnowledgeBase.activeRules {
            for insight in rule.produce(facts) {
                produced.append((rule.priority, insight))
            }
        }

        // De-dupe by insight id (first writer wins), then rank: attention before
        // info, then higher rule priority, then id for a fully stable order.
        var seen = Set<String>()
        let unique = produced.filter { seen.insert($0.insight.id).inserted }
        return unique.sorted { a, b in
            if a.insight.severity != b.insight.severity {
                return a.insight.severity > b.insight.severity
            }
            if a.rulePriority != b.rulePriority {
                return a.rulePriority > b.rulePriority
            }
            return a.insight.id < b.insight.id
        }.map(\.insight)
    }

    /// The single highest-ranked insight for the Coach card hero, if any.
    public static func top(_ facts: TrainingFacts) -> Insight? {
        run(facts).first
    }

    /// Shown before there's any logged history to reason about.
    static let coldStart = Insight(
        id: "coldStart",
        kind: .coldStart,
        title: "Log your first working sets",
        message: "Need 1 completed strength workout with working sets before Coach can read volume, intensity, or lift trends.",
        detail: "Workout history and assessment baselines are different. Logged sets let Coach analyze training patterns; separate tests such as e1RM or VO₂ field tests unlock measured baselines for percentage targets and retest comparisons.",
        citation: CitationRegistry.volumeDoseResponse,
        severity: .info)
}
