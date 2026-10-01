import Foundation

public enum CoachAddOnEngine {

    public static func run(facts: CoachFacts,
                           schedulePreferences: CoachSchedulePreferences = .default,
                           hasPainConcern: Bool = false) -> CoachAddOnRecommendation {
        let balance = facts.weeklyBalance
        let now = facts.referenceDate
        let todayCompleted = facts.todayCompletedEvents

        let strengthDoneToday = todayCompleted.contains(where: \.isStrength)
        let hardDoneToday = todayCompleted.contains(where: \.isHard)
        // Same-day cardio load ("coach suggests" plan, Phase 2): once intense
        // cardio — or a second cardio session — is already logged today, pushing
        // "Add easy cardio" is a nag, not coaching. hardDoneToday already covers
        // vigorous sessions (Phase 1 classifies HIIT/boxing as hard); the count
        // guard covers stacked easier sessions.
        let cardioToday = todayCompleted.filter(\.isAerobic)
        let redundantCardioToday = cardioToday.contains(where: \.isHard) || cardioToday.count >= 2

        let cardioDayTarget = schedulePreferences.cardioDaysPerWeek
        let aerobicTarget = 150.0
        let cardioDaysBelow = balance.cardioDays < cardioDayTarget
        let minutesBelow = balance.moderateEquivalentMinutes < aerobicTarget
        let poorReadiness = facts.readiness?.isPoor ?? false
        let hardStreak = balance.consecutiveHardDays

        var primaryOption: CoachAddOnOption?
        var secondary: [CoachAddOnOption] = []

        // Gate: pain/illness → no add-ons, warn against anything hard
        if hasPainConcern {
            return CoachAddOnRecommendation(
                primaryOption: nil,
                secondaryOptions: [
                    CoachAddOnOption(
                        id: "addon.postPainWarn",
                        session: CoachSession(
                            id: "addon.easyWalk", kind: .easyAerobic,
                            title: String(localized: "Easy walk", bundle: .module), subtitle: "20–30 min · conversational pace",
                            durationMinutes: 25, modality: .walk, intensity: .easy,
                            launchPayload: .cardio(type: "walk", durationMinutes: 25)
                        ),
                        status: .warn,
                        message: String(localized: "Pain or illness was reported. Keep any extra movement easy and stop if symptoms worsen.", bundle: .module),
                        citationIds: ["meeusenOvertraining2013"]
                    )
                ],
                generatedAt: now
            )
        }

        // Encouraged: cardio is below target, and no hard strength already done today
        // that would make extra cardio a second hard session on the same day.
        if !hardDoneToday && !redundantCardioToday && (cardioDaysBelow || minutesBelow) {
            let session = CoachSession(
                id: "addon.easyCardioEncouraged",
                kind: .easyAerobic,
                title: String(localized: "Add easy cardio", bundle: .module),
                subtitle: "20–30 min · walk, cycle, swim, or row",
                durationMinutes: 25,
                modality: .walk,
                intensity: .easy,
                launchPayload: .cardio(type: "walk", durationMinutes: 25)
            )
            primaryOption = CoachAddOnOption(
                id: "addon.encouragedCardio",
                session: session,
                status: .encouraged,
                message: {
                    if minutesBelow {
                        let gap = max(0, Int(aerobicTarget - balance.moderateEquivalentMinutes))
                        return String(localized: "\(gap) min to go on this week's aerobic target (\(Int(balance.moderateEquivalentMinutes))/150). Easy movement closes the gap.", bundle: .module)
                    }
                    let dayGap = max(0, cardioDayTarget - balance.cardioDays)
                    return String(localized: "\(dayGap) cardio days to go this week (\(balance.cardioDays)/\(cardioDayTarget)). Easy movement closes the gap.", bundle: .module)
                }(),
                citationIds: ["ekelundActivityMortality2016"]
            )
        }

        // Neutral: cardio target met but user might want movement
        if primaryOption == nil && !hardDoneToday {
            let session = CoachSession(
                id: "addon.easyMoveNeutral",
                kind: .easyAerobic,
                title: String(localized: "Easy movement", bundle: .module),
                subtitle: "15–20 min · walk or mobility",
                durationMinutes: 20,
                modality: .walk,
                intensity: .easy,
                launchPayload: .cardio(type: "walk", durationMinutes: 20)
            )
            secondary.append(CoachAddOnOption(
                id: "addon.neutralMovement",
                session: session,
                status: .neutral,
                message: String(localized: "All done for today — light movement is still fair game.", bundle: .module),
                citationIds: ["ekelundActivityMortality2016"]
            ))
        }

        // Warn: another hard strength after strength was already done today
        if strengthDoneToday && !hasPainConcern {
            let session = CoachSession(
                id: "addon.hardStrengthWarn",
                kind: .strength,
                title: String(localized: "Additional strength", bundle: .module),
                subtitle: String(localized: "This is more load than planned today.", bundle: .module),
                exercises: CoachSession.fullBodyStrengthExercises(
                    facts: facts,
                    desiredSetsPerExercise: schedulePreferences.desiredSetsPerExercise
                ),
                launchPayload: .strengthPlan("fullBody")
            )
            secondary.append(CoachAddOnOption(
                id: "addon.warnStrength",
                session: session,
                status: .warn,
                message: String(localized: "You already lifted today. Another session means recovery, not more strength, will be the limiting factor.", bundle: .module),
                citationIds: ["meeusenOvertraining2013", "schoenfeld2021"]
            ))
        }

        // Warn: poor readiness
        if poorReadiness && !hardDoneToday {
            secondary.append(CoachAddOnOption(
                id: "addon.poorReadiness",
                session: CoachSession(
                    id: "addon.restWarn", kind: .rest,
                    title: String(localized: "Rest or recovery", bundle: .module),
                    subtitle: String(localized: "Readiness is low — recovery may be the limiting factor.", bundle: .module),
                    launchPayload: .rest
                ),
                status: .warn,
                message: String(localized: "Readiness is low. Extra work may set back adaptation.", bundle: .module),
                citationIds: ["sawMonitoring2016"]
            ))
        }

        // Warn: hard-day streak
        if hardStreak >= 4 {
            secondary.append(CoachAddOnOption(
                id: "addon.hardStreak",
                session: CoachSession(
                    id: "addon.restHardStreak", kind: .rest,
                    title: String(localized: "Rest day", bundle: .module),
                    subtitle: String(localized: "\(hardStreak) consecutive hard days — recovery is the limiting factor.", bundle: .module),
                    launchPayload: .rest
                ),
                status: .warn,
                message: String(localized: "You've trained hard \(hardStreak) days in a row. You can continue, but keep it easy if performance drops.", bundle: .module),
                citationIds: ["meeusenOvertraining2013", "drewFinchInjury2016"]
            ))
        }

        // Warn: HIIT/boxing after completion without remaining vigorous eligibility
        if hardDoneToday || hardStreak >= 3 {
            let hiitSession = CoachSession(
                id: "addon.hiitWarn",
                kind: .moderateAerobic,
                title: "HIIT or boxing",
                subtitle: String(localized: "Vigorous intervals after a completed plan", bundle: .module),
                durationMinutes: 25,
                modality: .boxing,
                intensity: .vigorous,
                launchPayload: .cardio(type: "boxing", durationMinutes: 25)
            )
            secondary.append(CoachAddOnOption(
                id: "addon.warnVigorous",
                session: hiitSession,
                status: .warn,
                message: String(localized: "This is more load than planned today. You can continue, but keep it easy if performance drops.", bundle: .module),
                citationIds: ["meeusenOvertraining2013"]
            ))
        }

        return CoachAddOnRecommendation(
            primaryOption: primaryOption,
            secondaryOptions: secondary,
            generatedAt: now
        )
    }
}
