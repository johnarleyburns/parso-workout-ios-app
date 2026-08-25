import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct SessionView: View {
    @Bindable var session: WorkoutSession
    var isManualLog: Bool = false
    var onDone: (() -> Void)? = nil
    var initiallyExpandedExerciseID: UUID? = nil
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(AppSettings.self) var settings
    @Environment(AppModel.self) var model
    @Environment(ActiveWorkoutModel.self) var active

    @State var rest = RestTimerModel()
    @State var timers = WorkoutTimersModel()
    @State var pickerPresented = false
    @State var inlineExerciseID: UUID?
    @State var expandedExerciseID: UUID?
    @State var inlineExercise: Exercise?
    @State var inlineEditingSetID: UUID?
    @State var setEditorIdentity = UUID()
    @State var setEditorRoute: SetEditorRoute?
    @State var pendingRepsOverride: Int?
    @State var pendingPerformerID: UUID?
    @State var lastEffortMode: WatchEffortMode = .rpe
    @State var showWeightInfo = false
    @State var showDumbbellInfo = false
    @State var showKettlebellInfo = false
    @AppStorage("dumbbellInfoShown") var dumbbellInfoShown = false
    @AppStorage("kettlebellInfoShown") var kettlebellInfoShown = false
    @State var showDeleteConfirm = false
    @State var healthSaved = false
    @Query(sort: \Person.name) var allPeople: [Person]
    @State var addPartnerPresented = false
    @State var newPartnerName = ""
    @State var renamePresented = false
    @State var editedTitle = ""
    @State var datePickerPresented = false
    @State var endDatePickerPresented = false
    @State var exerciseToRemove: Exercise?
    @State var managePartnersPresented = false
    @State var watchdog = IdleWatchdog()
    @State var idlePromptShown = false
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var usePreviousPresented = false
    @State var swapTarget: ExerciseSwap.SwapTarget?
    @State var coolingDown = false
    @State var coolDownConfirm = false
    let idleTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State var hrSamples: [HRSamplePoint] = []
    @State var cache = SessionHistoryCache()
    /// Each performer's rep pattern across every movement they have logged, keyed
    /// by `SessionRenderModel.performerKey`. Refreshed with the render cache, so a
    /// partner's usual reps cost one bounded history walk per structural change
    /// rather than a fetch per keystroke (field test 2026-08-19 #3).
    @State var generalRepLadders: [String: [[Int]]] = [:]
    /// Exercise rows resolved by name for the planned-only cards. Looking these up
    /// with `findOrCreateExercise` inside `body` fetched — and could insert — on
    /// every redraw (field test 2026-08-19 #4).
    @State var plannedExerciseIndex: [String: Exercise] = [:]
    /// Exercise the scroll view should bring to the top on the next redraw.
    @State var scrollTarget: UUID?
    /// Set after a save; consumed once the render cache contains the exercise's
    /// card, which may only appear on the rebuild that the save triggered.
    @State var pendingScrollExerciseID: UUID?
    var refreshSignature: SessionRenderModel.Signature {
        SessionRenderModel.signature(session: session, prRule: settings.prRule, formula: settings.formula)
    }
    var rosterEntries: [RosterEntry] {
        roster.map { person in
            RosterEntry(personID: person.isMe ? nil : person.id,
                        name: person.isMe ? "Me" : person.name,
                        isMe: person.isMe)
        }
    }

    var attributedPartnerIDs: [UUID] {
        (session.sets ?? []).compactMap { set in
            guard let p = set.performedBy, !p.isMe else { return nil }
            return p.id
        }
    }

    var roster: [Person] {
        SessionRoster.roster(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)
    }

    var attributablePartners: [Person] {
        SessionRoster.attributablePartners(activePartnerIDs: session.activePartnerIDs,
                                           allPeople: allPeople,
                                           includingAttributed: attributedPartnerIDs)
    }

    var hasPartners: Bool {
        SessionRoster.canAttribute(activePartnerIDs: session.activePartnerIDs,
                                   allPeople: allPeople,
                                   attributedIDs: attributedPartnerIDs)
    }

    var recentPartners: [Person] {
        let sessions = (try? WorkoutRepository.allSessions(context)) ?? []
        var seen = Set<String>()
        var result: [Person] = []
        let scoped = Set(session.activePartnerIDs)
        for s in sessions.sorted(by: { $0.date > $1.date }) where s.id != session.id {
            for pid in s.activePartnerIDs {
                guard !seen.contains(pid), !scoped.contains(pid),
                      let p = allPeople.first(where: { $0.id.uuidString == pid }),
                      !p.isMe else { continue }
                seen.insert(pid)
                result.append(p)
            }
        }
        return result
    }


}

struct PreviousWorkoutPicker: View {
    let excluding: WorkoutSession
    let onPick: (WorkoutSession) -> Void
    @Environment(\.dismiss) var dismiss
    @Query(sort: \WorkoutSession.date, order: .reverse) var sessions: [WorkoutSession]

    var candidates: [WorkoutSession] {
        sessions.filter { $0.id != excluding.id && !$0.orderedSets.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView("No previous workouts", systemImage: "clock",
                                           description: Text("Log a workout first."))
                }
                ForEach(candidates) { s in
                    Button {
                        onPick(s); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title.isEmpty ? "Workout" : s.title)
                            Text(s.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(s.exercisesInOrder.count) exercises · \(s.orderedSets.count) sets")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("usePrevious.row")
                }
            }
            .navigationTitle("Use Previous Workout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("usePrevious.cancel")
                }
            }
        }
    }
}
