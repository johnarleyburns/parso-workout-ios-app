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

    /// Picks the best-matching built-in routine for the current recommendations.
    /// Prefers routines the user has been doing recently, then routines in the same
    /// program group, then routines that cover the most recommended body parts /
    /// exercises. Never creates a custom ad-hoc plan.
    public static func pickRoutine(_ facts: TrainingFacts,
                                   recentPlanKeys: [String]) -> WorkoutPlan {
        let recs = run(facts)
        let presets = StrengthPresets.all
        guard let firstPreset = presets.first else {
            return StrengthPresets.fallback
        }

        let recentKeySet = Set(recentPlanKeys)
        let recentPrefixes: Set<String> = Set(recentPlanKeys.compactMap { key in
            guard key.hasPrefix("preset-") else { return nil }
            let parts = key.split(separator: "-")
            return parts.count >= 2 ? "\(parts[0])-\(parts[1])" : nil
        })

        var bestPlan = firstPreset
        var bestScore = Int.min

        for plan in presets {
            var score = 0

            let moveSet = Set(plan.movementNames.map { $0.lowercased() })
            let planParts = routineBodyParts(plan)

            for rec in recs {
                if let ex = rec.exercise, moveSet.contains(ex.lowercased()) {
                    score += 10
                } else if let part = rec.part, planParts.contains(part) {
                    score += 5
                }
            }

            if recentKeySet.contains(plan.id) {
                score += 20
            }

            if plan.id.hasPrefix("preset-") {
                let parts = plan.id.split(separator: "-")
                if parts.count >= 2 {
                    let prefix = "\(parts[0])-\(parts[1])"
                    if recentPrefixes.contains(prefix) { score += 10 }
                }
            }

            if score > bestScore {
                bestScore = score
                bestPlan = plan
            }
        }

        return bestPlan
    }

    private static func routineBodyParts(_ plan: WorkoutPlan) -> Set<BodyPart> {
        var parts = Set<BodyPart>()
        for name in plan.movementNames {
            if let t = ExerciseLibrary.byName[name.lowercased()] {
                parts.formUnion(ExerciseLibrary.bodyParts(of: t))
            }
        }
        return parts
    }
}
