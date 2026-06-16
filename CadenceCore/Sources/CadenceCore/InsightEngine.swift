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
        guard facts.totalWorkingSets > 0 else { return [coldStart] }

        // Forward-chain every rule, then resolve to a stable ranked order.
        var produced: [(rulePriority: Int, insight: Insight)] = []
        for rule in KnowledgeBase.p3Rules {
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
        title: "Let's get a baseline",
        message: "Log a few workouts and your coach will start spotting volume, intensity, and progress trends from your own data.",
        detail: "Cadence's coaching is grounded in published resistance-training science — weekly volume dose-response, the load/rep continuum, and training frequency. Once you've logged some sets, those principles get applied to your actual history, with the citation behind every insight.",
        citation: CitationRegistry.volumeDoseResponse,
        severity: .info)
}
