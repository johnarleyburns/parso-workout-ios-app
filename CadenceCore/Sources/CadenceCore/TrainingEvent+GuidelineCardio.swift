import Foundation

extension CardioIntensityProfile {
    /// Shared by Home's coach and weekly dashboard, including an explicit HRmax.
    public static func forHome(passiveSamples: [PassiveReadinessSample], userAge: Int?,
                               maximumHROverride: Double? = nil) -> CardioIntensityProfile {
        let values = passiveSamples.compactMap(\.restingHR).filter { $0 > 25 && $0 < 160 }.sorted()
        return .resolved(restingHR: values.isEmpty ? nil : values[values.count / 2],
                         userEnteredMaximumHR: maximumHROverride, age: userAge)
    }
}

extension TrainingEvent {
    /// Use the identical guideline accumulator as This Week. Legacy sessions
    /// without HR or a stored split remain unclassified rather than inventing credit.
    public static func guidelineCardio(_ cardio: CardioWorkout, userAge: Int? = nil,
                                       profile: CardioIntensityProfile) -> TrainingEvent {
        let base = from(cardio: cardio, userAge: userAge)
        let original: AerobicEventDetails
        switch base.kind {
        case .aerobic(let details), .intervals(let details): original = details
        default: return base
        }
        let split = WeeklyCardioAggregator.summarize([cardio], since: cardio.start, profile: profile)
        let intensity: AerobicEventDetails.IntensityClassification = split.unclassifiedMinutes > 0
            ? original.intensity : split.vigorousMinutes > 0
            && split.vigorousMinutes >= split.moderateMinutes ? .vigorous
            : (split.moderateMinutes > 0 ? .moderate : .easy)
        let details = AerobicEventDetails(
            modality: original.modality, impact: original.impact, duration: original.duration,
            intensity: intensity, intensityConfidence: split.unclassifiedMinutes > 0 ? .low : .high,
            easyMinutes: split.belowModerateMinutes, moderateMinutes: split.moderateMinutes,
            vigorousMinutes: split.vigorousMinutes,
            moderateEquivalentMinutes: split.moderateEquivalentMinutes,
            lowerBodyLoading: original.lowerBodyLoading, isInterval: original.isInterval)
        return TrainingEvent(id: base.id, start: base.start, end: base.end,
                             kind: original.isInterval ? .intervals(details) : .aerobic(details),
                             source: base.source, completion: base.completion)
    }
}
