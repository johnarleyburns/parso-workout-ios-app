import SwiftData
import UIKit
import CadenceCore
import CadenceFeatures

extension SessionView {
    func addSet(to exercise: Exercise, weightKg: Double, reps: Int,
                rpe: Double?, isWarmup: Bool, usesBodyweight: Bool = false,
                note: String?, performedBy: Person? = nil) {
        recordActivity()
        let person = (performedBy?.isMe ?? true) ? nil : performedBy
        let priorOwnerSamples = (exercise.sets ?? [])
            .filter { $0.session?.id != session.id && $0.isOwnerSet }
            .map { SetSample.from($0) }
        let priorPR = PRCalculator.best(priorOwnerSamples, rule: settings.prRule, formula: settings.formula)
        let priorPRSample = PRCalculator.bestSample(priorOwnerSamples, rule: settings.prRule, formula: settings.formula)
        let isPR = person == nil && WorkoutRepository.wouldBePR(
            exercise: exercise, weightKg: weightKg, reps: reps, isWarmup: isWarmup,
            rule: settings.prRule, formula: settings.formula)
        let when = session.isLogged ? session.date : Date()
        if (try? WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: weightKg,
                                          reps: reps, rpe: rpe, isWarmup: isWarmup,
                                          usesBodyweight: usesBodyweight, note: note,
                                          completedAt: when, performedBy: person, in: context)) != nil {
            postVolumeChange(date: when, delta: isWarmup || person != nil ? [:] : exercise.volumeCredits)
            refreshLiveVolume()
        }
        setLoggedRevision &+= 1
        if isPR {
            Haptics.prAchieved()
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "New best, \(exercise.name), \(Format.weight(weightKg, unit: settings.unit)) for \(reps)"))
            let sample = SetSample(weight: weightKg, reps: reps, date: when, isWarmup: isWarmup)
            let metric = PRCalculator.metric(sample, rule: settings.prRule, formula: settings.formula)
            let changeText: String = {
                guard let priorPR else { return "first \(settings.prRule.displayName.lowercased()) PR" }
                let delta = metric - priorPR
                let weeks = priorPRSample.map {
                    max(1, Int(ceil(max(0, when.timeIntervalSince($0.date)) / 604_800)))
                } ?? 1
                return "up \(Format.weight(abs(delta), unit: settings.unit)) in \(weeks) weeks"
            }()
            prMoment = PRMomentPresenter.moment(
                exercise: exercise.name,
                loadText: Format.weight(weightKg, unit: settings.unit),
                changeText: changeText,
                isNewPR: true,
                isWarmup: isWarmup,
                isPartnerSet: person != nil,
                performerName: person?.name)
            prEvent = PREvent(exerciseName: exercise.name, date: when,
                              kind: PRKind(rule: settings.prRule), value: metric,
                              reps: reps, weightKg: weightKg, previous: priorPR)
        } else {
            Haptics.setLogged()
            let performerText = person.map { " for \($0.name)" } ?? ""
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "Set logged, \(exercise.name), \(Format.weight(weightKg, unit: settings.unit)) for \(reps)\(performerText)"))
        }
        if active.strengthSession?.id == session.id {
            let exercises = session.exercisesInOrder
            if let currentIndex = exercises.firstIndex(where: { $0.id == exercise.id }),
               exercises.indices.contains(currentIndex + 1) {
                active.nextExercise = exercises[currentIndex + 1].name
            } else { active.nextExercise = nil }
        }
        if settings.autoStartRest && !isWarmup && !isManualLog && active.strengthSession?.id == session.id {
            rest.start(seconds: settings.restSeconds)
            syncRestAlarm(to: rest.endsAt)
        }
    }

    func syncRestAlarm(to endsAt: Date?) {
        active.restEndsAt = endsAt
        guard settings.restAlertMode == .alarm, let endsAt else {
            RestAlarmCoordinator.shared.cancel()
            return
        }
        RestAlarmCoordinator.shared.schedule(endsAt: endsAt)
    }

    func postVolumeChange(date: Date, delta: [MuscleGroup: Double]) {
        guard !delta.isEmpty else { return }
        NotificationCenter.default.post(
            name: .workoutVolumeChanged,
            object: WorkoutVolumeChange(sessionID: session.id, date: date, delta: delta))
    }
}
