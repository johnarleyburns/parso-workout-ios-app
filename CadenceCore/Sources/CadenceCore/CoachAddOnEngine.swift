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
                            title: "Easy walk", subtitle: "20–30 min · conversational pace",
                            durationMinutes: 25, modality: .walk, intensity: .easy,
                            launchPayload: .cardio(type: "walk", durationMinutes: 25)
                        ),
                        status: .warn,
                        message: "Pain or illness was reported. Keep any extra movement easy and stop if symptoms worsen.",
                        citationIds: ["meeusenOvertraining2013"]
                    )
                ],
                generatedAt: now
            )
        }

        // Encouraged: cardio is below target, and no hard strength already done today
        // that would make extra cardio a second hard session on the same day.
        if !hardDoneToday && (cardioDaysBelow || minutesBelow) {
            let session = CoachSession(
                id: "addon.easyCardioEncouraged",
                kind: .easyAerobic,
                title: "Add easy cardio",
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
                        return "\(gap) min to go on this week's aerobic target (\(Int(balance.moderateEquivalentMinutes))/150). Easy movement closes the gap."
                    }
                    let dayGap = max(0, cardioDayTarget - balance.cardioDays)
                    return "\(dayGap) cardio day\(dayGap == 1 ? "" : "s") to go this week (\(balance.cardioDays)/\(cardioDayTarget)). Easy movement closes the gap."
                }(),
                citationIds: ["ekelundActivityMortality2016"]
            )
        }

        // Neutral: cardio target met but user might want movement
        if primaryOption == nil && !hardDoneToday {
            let session = CoachSession(
                id: "addon.easyMoveNeutral",
                kind: .easyAerobic,
                title: "Easy movement",
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
                message: "All done for today — light movement is still fair game.",
                citationIds: ["ekelundActivityMortality2016"]
            ))
        }

        // Warn: another hard strength after strength was already done today
        if strengthDoneToday && !hasPainConcern {
            let session = CoachSession(
                id: "addon.hardStrengthWarn",
                kind: .strength,
                title: "Additional strength",
                subtitle: "This is more load than planned today.",
                launchPayload: .strengthPlan("fullBody")
            )
            secondary.append(CoachAddOnOption(
                id: "addon.warnStrength",
                session: session,
                status: .warn,
                message: "You already lifted today. Another session means recovery, not more strength, will be the limiting factor.",
                citationIds: ["meeusenOvertraining2013", "schoenfeld2021"]
            ))
        }

        // Warn: poor readiness
        if poorReadiness && !hardDoneToday {
            secondary.append(CoachAddOnOption(
                id: "addon.poorReadiness",
                session: CoachSession(
                    id: "addon.restWarn", kind: .rest,
                    title: "Rest or recovery",
                    subtitle: "Readiness is low — recovery may be the limiting factor.",
                    launchPayload: .rest
                ),
                status: .warn,
                message: "Readiness is low. Extra work may set back adaptation.",
                citationIds: ["sawMonitoring2016"]
            ))
        }

        // Warn: hard-day streak
        if hardStreak >= 4 {
            secondary.append(CoachAddOnOption(
                id: "addon.hardStreak",
                session: CoachSession(
                    id: "addon.restHardStreak", kind: .rest,
                    title: "Rest day",
                    subtitle: "\(hardStreak) consecutive hard days — recovery is the limiting factor.",
                    launchPayload: .rest
                ),
                status: .warn,
                message: "You've trained hard \(hardStreak) days in a row. You can continue, but keep it easy if performance drops.",
                citationIds: ["meeusenOvertraining2013"]
            ))
        }

        // Warn: HIIT/boxing after completion without remaining vigorous eligibility
        if hardDoneToday || hardStreak >= 3 {
            let hiitSession = CoachSession(
                id: "addon.hiitWarn",
                kind: .moderateAerobic,
                title: "HIIT or boxing",
                subtitle: "Vigorous intervals after a completed plan",
                durationMinutes: 25,
                modality: .boxing,
                intensity: .vigorous,
                launchPayload: .cardio(type: "boxing", durationMinutes: 25)
            )
            secondary.append(CoachAddOnOption(
                id: "addon.warnVigorous",
                session: hiitSession,
                status: .warn,
                message: "This is more load than planned today. You can continue, but keep it easy if performance drops.",
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
