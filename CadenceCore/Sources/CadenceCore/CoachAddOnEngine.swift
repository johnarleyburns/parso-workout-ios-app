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

        let aerobicTarget = 150.0
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
                            title: {
                                #if os(Linux)
                                "Easy walk"
                                #else
                                String(localized: "Easy walk", bundle: .module)
                                #endif
                            }(), subtitle: "20–30 min · conversational pace",
                            durationMinutes: 25, modality: .walk, intensity: .easy,
                            launchPayload: .cardio(type: "walk", durationMinutes: 25)
                        ),
                        status: .warn,
                        message: {
                            #if os(Linux)
                            "Pain or illness was reported. Keep any extra movement easy and stop if symptoms worsen."
                            #else
                            String(localized: "Pain or illness was reported. Keep any extra movement easy and stop if symptoms worsen.", bundle: .module)
                            #endif
                        }(),
                        citationIds: ["meeusenOvertraining2013"]
                    )
                ],
                generatedAt: now
            )
        }

        // Encouraged: cardio is below target, and no hard strength already done today
        // that would make extra cardio a second hard session on the same day.
        if !hardDoneToday && !redundantCardioToday && minutesBelow {
            let session = CoachSession(
                id: "addon.easyCardioEncouraged",
                kind: .easyAerobic,
                title: {
                    #if os(Linux)
                    "Add easy cardio"
                    #else
                    String(localized: "Add easy cardio", bundle: .module)
                    #endif
                }(),
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
                    let gap = max(0, Int(aerobicTarget - balance.moderateEquivalentMinutes))
                    return {
                        #if os(Linux)
                        "\(gap) min to go on this week's aerobic target (\(Int(balance.moderateEquivalentMinutes))/150). Easy movement closes the gap."
                        #else
                        String(localized: "\(gap) min to go on this week's aerobic target (\(Int(balance.moderateEquivalentMinutes))/150). Easy movement closes the gap.", bundle: .module)
                        #endif
                    }()
                }(),
                citationIds: ["ekelundActivityMortality2016"]
            )
        }

        // Neutral: cardio target met but user might want movement
        if primaryOption == nil && !hardDoneToday {
            let session = CoachSession(
                id: "addon.easyMoveNeutral",
                kind: .easyAerobic,
                title: {
                    #if os(Linux)
                    "Easy movement"
                    #else
                    String(localized: "Easy movement", bundle: .module)
                    #endif
                }(),
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
                message: {
                    #if os(Linux)
                    "All done for today — light movement is still fair game."
                    #else
                    String(localized: "All done for today — light movement is still fair game.", bundle: .module)
                    #endif
                }(),
                citationIds: ["ekelundActivityMortality2016"]
            ))
        }

        // Warn: another hard strength after strength was already done today
        if strengthDoneToday && !hasPainConcern {
            let session = CoachSession(
                id: "addon.hardStrengthWarn",
                kind: .strength,
                title: {
                    #if os(Linux)
                    "Additional strength"
                    #else
                    String(localized: "Additional strength", bundle: .module)
                    #endif
                }(),
                subtitle: {
                    #if os(Linux)
                    "This is more load than planned today."
                    #else
                    String(localized: "This is more load than planned today.", bundle: .module)
                    #endif
                }(),
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
                message: {
                    #if os(Linux)
                    "You already lifted today. Another session means recovery, not more strength, will be the limiting factor."
                    #else
                    String(localized: "You already lifted today. Another session means recovery, not more strength, will be the limiting factor.", bundle: .module)
                    #endif
                }(),
                citationIds: ["meeusenOvertraining2013", "schoenfeld2021"]
            ))
        }

        // Warn: poor readiness
        if poorReadiness && !hardDoneToday {
            secondary.append(CoachAddOnOption(
                id: "addon.poorReadiness",
                session: CoachSession(
                    id: "addon.restWarn", kind: .rest,
                    title: {
                        #if os(Linux)
                        "Rest or recovery"
                        #else
                        String(localized: "Rest or recovery", bundle: .module)
                        #endif
                    }(),
                    subtitle: {
                        #if os(Linux)
                        "Readiness is low — recovery may be the limiting factor."
                        #else
                        String(localized: "Readiness is low — recovery may be the limiting factor.", bundle: .module)
                        #endif
                    }(),
                    launchPayload: .rest
                ),
                status: .warn,
                message: {
                    #if os(Linux)
                    "Readiness is low. Extra work may set back adaptation."
                    #else
                    String(localized: "Readiness is low. Extra work may set back adaptation.", bundle: .module)
                    #endif
                }(),
                citationIds: ["sawMonitoring2016"]
            ))
        }

        // Warn: hard-day streak
        if hardStreak >= 4 {
            secondary.append(CoachAddOnOption(
                id: "addon.hardStreak",
                session: CoachSession(
                    id: "addon.restHardStreak", kind: .rest,
                    title: {
                        #if os(Linux)
                        "Rest day"
                        #else
                        String(localized: "Rest day", bundle: .module)
                        #endif
                    }(),
                    subtitle: {
                        #if os(Linux)
                        "\(hardStreak) consecutive hard days — recovery is the limiting factor."
                        #else
                        String(localized: "\(hardStreak) consecutive hard days — recovery is the limiting factor.", bundle: .module)
                        #endif
                    }(),
                    launchPayload: .rest
                ),
                status: .warn,
                message: {
                    #if os(Linux)
                    "You've trained hard \(hardStreak) days in a row. You can continue, but keep it easy if performance drops."
                    #else
                    String(localized: "You've trained hard \(hardStreak) days in a row. You can continue, but keep it easy if performance drops.", bundle: .module)
                    #endif
                }(),
                citationIds: ["meeusenOvertraining2013", "drewFinchInjury2016"]
            ))
        }

        // Warn: HIIT/boxing after completion without remaining vigorous eligibility
        if hardDoneToday || hardStreak >= 3 {
            let hiitSession = CoachSession(
                id: "addon.hiitWarn",
                kind: .moderateAerobic,
                title: "HIIT or boxing",
                subtitle: {
                    #if os(Linux)
                    "Vigorous intervals after a completed plan"
                    #else
                    String(localized: "Vigorous intervals after a completed plan", bundle: .module)
                    #endif
                }(),
                durationMinutes: 25,
                modality: .boxing,
                intensity: .vigorous,
                launchPayload: .cardio(type: "boxing", durationMinutes: 25)
            )
            secondary.append(CoachAddOnOption(
                id: "addon.warnVigorous",
                session: hiitSession,
                status: .warn,
                message: {
                    #if os(Linux)
                    "This is more load than planned today. You can continue, but keep it easy if performance drops."
                    #else
                    String(localized: "This is more load than planned today. You can continue, but keep it easy if performance drops.", bundle: .module)
                    #endif
                }(),
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
