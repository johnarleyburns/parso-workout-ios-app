import Foundation

/// A lightweight, `Sendable` summary of an export's contents, computed off-main
/// alongside the encode so the Export screen can show a summary card instead of
/// rendering the (potentially tens-of-MB) payload in a SwiftUI `Text` — the root
/// cause of the export watchdog freeze. Unit-testable without any UI.
public struct ExportSummary: Codable, Equatable, Sendable {
    public var strengthSessionCount: Int
    public var strengthSetCount: Int
    public var cardioCount: Int
    /// Per-`CardioType` counts, keyed by the type's raw value (run, cycle, …).
    public var cardioByType: [String: Int]
    public var hrSampleCount: Int
    public var routeSampleCount: Int
    public var assessmentCount: Int
    /// Earliest / latest workout date across strength + cardio; nil when empty.
    public var firstWorkoutDate: Date?
    public var lastWorkoutDate: Date?
    /// Distinct calendar days that have at least one workout.
    public var daysCovered: Int
    public var includesPreferences: Bool
    public var preferenceKeyCount: Int
    public var includesCoachProfile: Bool
    public var coachPreferenceCount: Int
    public var coachEventCount: Int
    /// Encoded byte sizes (raw compact JSON and gzip-compressed).
    public var rawByteCount: Int
    public var compressedByteCount: Int

    public init(strengthSessionCount: Int = 0, strengthSetCount: Int = 0,
                cardioCount: Int = 0, cardioByType: [String: Int] = [:],
                hrSampleCount: Int = 0, routeSampleCount: Int = 0,
                assessmentCount: Int = 0, firstWorkoutDate: Date? = nil,
                lastWorkoutDate: Date? = nil, daysCovered: Int = 0,
                includesPreferences: Bool = false, preferenceKeyCount: Int = 0,
                includesCoachProfile: Bool = false, coachPreferenceCount: Int = 0,
                coachEventCount: Int = 0, rawByteCount: Int = 0, compressedByteCount: Int = 0) {
        self.strengthSessionCount = strengthSessionCount
        self.strengthSetCount = strengthSetCount
        self.cardioCount = cardioCount
        self.cardioByType = cardioByType
        self.hrSampleCount = hrSampleCount
        self.routeSampleCount = routeSampleCount
        self.assessmentCount = assessmentCount
        self.firstWorkoutDate = firstWorkoutDate
        self.lastWorkoutDate = lastWorkoutDate
        self.daysCovered = daysCovered
        self.includesPreferences = includesPreferences
        self.preferenceKeyCount = preferenceKeyCount
        self.includesCoachProfile = includesCoachProfile
        self.coachPreferenceCount = coachPreferenceCount
        self.coachEventCount = coachEventCount
        self.rawByteCount = rawByteCount
        self.compressedByteCount = compressedByteCount
    }

    /// True when the export carries no workouts or assessments.
    public var isEmpty: Bool {
        strengthSessionCount == 0 && cardioCount == 0 && assessmentCount == 0
    }

    /// Computes the summary from a decoded export. `rawByteCount` /
    /// `compressedByteCount` are passed in by the caller (which already encoded
    /// the payload) so we never re-encode here.
    public static func from(_ export: CadenceExport,
                            rawByteCount: Int = 0,
                            compressedByteCount: Int = 0,
                            calendar: Calendar = .current) -> ExportSummary {
        var cardioByType: [String: Int] = [:]
        var hr = 0, route = 0
        var days = Set<Date>()
        var minDate: Date?
        var maxDate: Date?

        func observe(_ date: Date) {
            days.insert(calendar.startOfDay(for: date))
            if minDate == nil || date < minDate! { minDate = date }
            if maxDate == nil || date > maxDate! { maxDate = date }
        }

        var setCount = 0
        for s in export.sessions {
            setCount += s.sets.count
            observe(s.date)
        }
        for c in export.cardio {
            cardioByType[c.type, default: 0] += 1
            hr += c.hrSamples?.count ?? 0
            route += c.routeSamples?.count ?? 0
            observe(c.start)
        }

        let prefs = export.preferences
        let prefKeys = prefs.map(preferenceKeyCount(_:)) ?? 0
        // The learned coach profile can travel either nested in preferences
        // (`coachProfile`, v4) or as the top-level `coachPreferences` DTO
        // (back-compat). Prefer the richer nested one when present.
        let profile = prefs?.coachProfile
        let dto = export.coachPreferences
        let coachPrefCount: Int
        let coachEvents: Int
        if let profile {
            coachPrefCount = profile.aerobicPreferences.count + profile.strengthPreferences.count
            coachEvents = profile.selectionEvents.count
        } else if let dto {
            coachPrefCount = dto.aerobicPreferences.count + dto.strengthPreferences.count
            coachEvents = dto.selectionEvents.count
        } else {
            coachPrefCount = 0
            coachEvents = 0
        }
        let includesCoach = profile != nil || dto != nil

        return ExportSummary(
            strengthSessionCount: export.sessions.count,
            strengthSetCount: setCount,
            cardioCount: export.cardio.count,
            cardioByType: cardioByType,
            hrSampleCount: hr,
            routeSampleCount: route,
            assessmentCount: export.assessments.count,
            firstWorkoutDate: minDate,
            lastWorkoutDate: maxDate,
            daysCovered: days.count,
            includesPreferences: prefs != nil,
            preferenceKeyCount: prefKeys,
            includesCoachProfile: includesCoach,
            coachPreferenceCount: coachPrefCount,
            coachEventCount: coachEvents,
            rawByteCount: rawByteCount,
            compressedByteCount: compressedByteCount)
    }

    /// Counts the non-nil scalar preference fields exported (excludes the nested
    /// coach profile / schedule, which are surfaced separately).
    private static func preferenceKeyCount(_ p: ExportPreferences) -> Int {
        var n = 0
        if p.unit != nil { n += 1 }
        if p.prRule != nil { n += 1 }
        if p.oneRepMaxFormula != nil { n += 1 }
        if p.stepGoal != nil { n += 1 }
        if p.weeklyCardioMinutesGoal != nil { n += 1 }
        if p.restSeconds != nil { n += 1 }
        if p.warmupMinutes != nil { n += 1 }
        if p.cooldownMinutes != nil { n += 1 }
        if p.autoStartRest != nil { n += 1 }
        if p.idleTimeoutMinutes != nil { n += 1 }
        if p.gpsHighAccuracy != nil { n += 1 }
        if p.autoPause != nil { n += 1 }
        if p.intervalColorBlind != nil { n += 1 }
        if p.spokenCues != nil { n += 1 }
        if p.plateRounding != nil { n += 1 }
        if p.autoSaveHealth != nil { n += 1 }
        if p.autoEndOnIdle != nil { n += 1 }
        if p.workoutSounds != nil { n += 1 }
        if p.preWorkoutCountdown != nil { n += 1 }
        if p.trainingGoal != nil { n += 1 }
        if p.experienceLevel != nil { n += 1 }
        if p.useHRMonitoring != nil { n += 1 }
        if p.recoveryAwareCoachV2 != nil { n += 1 }
        if p.favoriteRoutineIDs != nil { n += 1 }
        if p.hasCompletedOnboarding != nil { n += 1 }
        if p.schedulePreferences != nil { n += 1 }
        return n
    }
}
