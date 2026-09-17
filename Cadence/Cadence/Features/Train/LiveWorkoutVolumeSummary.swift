import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct LiveWorkoutVolumeState: Equatable, Sendable {
    var current: [MuscleGroup: Double] = [:]
    var weekly: [MuscleGroup: Double] = [:]
    var planned: [MuscleGroup: Double] = [:]

    var groups: [MuscleGroup] {
        MuscleGroup.canonicalOrder.filter {
            (current[$0] ?? 0) > 0 || (weekly[$0] ?? 0) > 0 || (planned[$0] ?? 0) > 0
        }
    }
}

struct LiveWorkoutVolumeSet: Sendable {
    let date: Date
    let isWarmup: Bool
    let isOwner: Bool
    let credits: [MuscleGroup: Double]
}

enum LiveWorkoutVolumeCalculator {
    static func sets(from workout: WorkoutSession) -> [LiveWorkoutVolumeSet] {
        workout.orderedSets.map { set in
            LiveWorkoutVolumeSet(date: set.completedAt,
                                 isWarmup: set.isWarmup,
                                 isOwner: set.isOwnerSet,
                                 credits: set.exercise?.volumeCredits
                                    ?? ExerciseLibrary.template(matching: set.exercise?.name ?? "")?.volumeCredits
                                    ?? [:])
        }
    }

    static func totals(_ sets: [LiveWorkoutVolumeSet], since start: Date? = nil)
    -> [MuscleGroup: Double] {
        sets.reduce(into: [:]) { result, set in
            guard !set.isWarmup, set.isOwner, start.map({ set.date >= $0 }) ?? true else { return }
            for (group, credit) in set.credits where credit > 0 {
                result[group, default: 0] += credit
            }
        }
    }

    static func plannedTotals(_ prescriptions: [PlannedExercisePrescription],
                              creditsByName: [String: [MuscleGroup: Double]]) -> [MuscleGroup: Double] {
        prescriptions.reduce(into: [:]) { result, prescription in
            guard let credits = creditsByName[prescription.exerciseName.lowercased()] else { return }
            let count = prescription.sets.filter { !$0.isWarmup }.count
            guard count > 0 else { return }
            for (group, credit) in credits where credit > 0 {
                result[group, default: 0] += Double(count) * credit
            }
        }
    }

    static func weekStart(now: Date = Date()) -> Date {
        WeeklyStats.weekStart(now: now)
    }
}

enum WorkoutVolumeSummaryPresentation: Equatable {
    case active
    case planned
}

struct LiveWorkoutVolumeSummary: View {
    let state: LiveWorkoutVolumeState
    @Binding var expanded: Bool
    var presentation: WorkoutVolumeSummaryPresentation = .active
    var accessibilityPrefix: String = "session"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Volume Summary").font(.headline)
                Spacer()
                Text(presentation == .planned ? "Planned" : "This workout")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if state.groups.isEmpty {
                Text(presentation == .planned
                     ? "Add a volume-eligible strength exercise to see planned muscle-group volume here."
                     : "Save a working set to see muscle-group volume here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(expanded ? groupsForDisplay : Array(groupsForDisplay.prefix(4)), id: \.self) { group in
                    row(group)
                }
                Button(expanded ? "Show less" : "Show more…") {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier(expanded
                                         ? "\(accessibilityPrefix).volume.showLess"
                                         : "\(accessibilityPrefix).volume.showMore")
            }
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
        .accessibilityIdentifier("\(accessibilityPrefix).volumeSummary")
    }

    /// Show only groups that have volume in this workout/plan. Sort the actual
    /// workout contribution first, then use a stable alphabetical tie-breaker;
    /// weekly background volume must not pull an otherwise empty group into view.
    private var groupsForDisplay: [MuscleGroup] {
        let values: (MuscleGroup) -> Double = { group in
            presentation == .planned ? (state.planned[group] ?? 0) : (state.current[group] ?? 0)
        }
        return MuscleGroup.canonicalOrder
            .filter { values($0) > 0 }
            .sorted {
                let left = values($0), right = values($1)
                if left != right { return left > right }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private func row(_ group: MuscleGroup) -> some View {
        let current = state.current[group] ?? 0
        let weekly = state.weekly[group] ?? 0
        let planned = state.planned[group] ?? 0
        let workout = presentation == .planned ? planned : current
        let scale = max(4, workout, weekly, planned)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(group.displayName).font(.caption.weight(.medium))
                Spacer()
                Text("\(format(workout)) sets")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: proxy.size.width * min(1, weekly / scale))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: proxy.size.width * min(1, workout / scale))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 1)
                        .offset(x: proxy.size.width * min(1, 4 / scale))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(accessibilityPrefix).volume.\(group.rawValue)")
        .accessibilityValue("\(format(current)) sets")
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

extension SessionView {
    func refreshLiveVolume() {
        guard active.strengthSession?.id == session.id else { return }
        let currentSets = liveVolumeSets(from: session)
        let weekStart = LiveWorkoutVolumeCalculator.weekStart()
        let weeklySets = allWorkoutSessions
            .filter { $0.deletedAt == nil && $0.countsAsStrengthHistory }
            .flatMap { liveVolumeSets(from: $0) }
        let creditsByName = plannedCreditsByName()
        let prescriptions = session.plannedPrescriptions
        Task.detached(priority: .userInitiated) {
            let current = LiveWorkoutVolumeCalculator.totals(currentSets)
            let weekly = LiveWorkoutVolumeCalculator.totals(weeklySets, since: weekStart)
            let planned = LiveWorkoutVolumeCalculator.plannedTotals(
                prescriptions, creditsByName: creditsByName)
            let next = LiveWorkoutVolumeState(current: current, weekly: weekly, planned: planned)
            await MainActor.run { [next] in
                liveVolumeState = next
            }
        }
    }

    private func liveVolumeSets(from workout: WorkoutSession) -> [LiveWorkoutVolumeSet] {
        LiveWorkoutVolumeCalculator.sets(from: workout)
    }

    func plannedCreditsByName() -> [String: [MuscleGroup: Double]] {
        var result: [String: [MuscleGroup: Double]] = [:]
        for exercise in session.exercisesInOrder {
            result[exercise.name.lowercased()] = exercise.volumeCredits
        }
        for prescription in session.plannedPrescriptions {
            if result[prescription.exerciseName.lowercased()] == nil {
                result[prescription.exerciseName.lowercased()] =
                    ExerciseLibrary.template(matching: prescription.exerciseName)?.volumeCredits ?? [:]
            }
        }
        return result
    }
}
