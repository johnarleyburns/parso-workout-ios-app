import Foundation

/// The prescriptive half of the forward-chaining inference engine (§03), added in
/// P5. Runs `KnowledgeBase.p5Rules` over a `TrainingFacts` snapshot and returns a
/// ranked, de-duplicated list of cited `Recommendation`s — concrete next actions
/// (load/reps/RIR targets, deloads, added volume), not just observations. Pure and
/// deterministic, mirroring `InsightEngine`.
public enum RecommendationEngine {

    /// All recommendations, highest-priority first. Never empty — with no history
    /// the engine returns a single cold-start `starter` so the Coach card always has
    /// something cited and actionable to show.
    public static func run(_ facts: TrainingFacts) -> [Recommendation] {
        var produced: [(rulePriority: Int, rec: Recommendation)] = []
        for rule in KnowledgeBase.activeRecommendationRules {
            for rec in rule.produce(facts) {
                produced.append((rule.priority, rec))
            }
        }

        // De-dupe by recommendation id (first writer wins), then rank: higher rule
        // priority, then higher confidence, then id for a fully stable order.
        var seen = Set<String>()
        let unique = produced.filter { seen.insert($0.rec.id).inserted }
        let ranked = unique.sorted { a, b in
            if a.rulePriority != b.rulePriority { return a.rulePriority > b.rulePriority }
            if a.rec.confidence != b.rec.confidence { return a.rec.confidence > b.rec.confidence }
            return a.rec.id < b.rec.id
        }.map(\.rec)

        guard ranked.isEmpty else { return ranked }
        return [KnowledgeBase.starter(goal: facts.goal, experience: facts.experience)]
    }

    /// The single highest-ranked recommendation for the Coach card hero.
    public static func top(_ facts: TrainingFacts) -> Recommendation {
        run(facts).first ?? KnowledgeBase.starter(goal: facts.goal, experience: facts.experience)
    }
}
