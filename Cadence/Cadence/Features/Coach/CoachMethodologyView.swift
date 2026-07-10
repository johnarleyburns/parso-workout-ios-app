import SwiftUI
import CadenceCore

/// Explains every scientific principle the coach follows, organized by
/// the same domains as the scientific validation test suite. Each rule is
/// backed by the same peer-reviewed citations the coach uses at runtime.
///
/// Accessible from Settings → Coach → Coach Methodology.
struct CoachMethodologyView: View {
    var body: some View {
        List {
            preamble

            Section {
                painGate
                liftRecoveryGate
                consecutiveHardDays
                volumeWarnings
            } header: {
                domainHeader("Recovery & Safety", "The coach gates hard sessions behind recovery windows and flags overtraining risk.")
            }

            Section {
                aerobicFloor
                strengthFloor
                harderOptions
                frequencyDistribution
                twoADayCompletion
            } header: {
                domainHeader("Balance & Priority", "The coach closes the largest weekly deficit first — strength days or aerobic minutes — then surfaces harder options once the basics are covered.")
            }

            Section {
                modalityPreference
                highImpactAvoidance
                exercisePreference
            } header: {
                domainHeader("Preference Learning", "The coach learns from the alternatives you choose and respects your modality and impact-level preferences.")
            }

            Section {
                assessmentPrompt
                thresholdEligibility
                freshAssessmentSilence
            } header: {
                domainHeader("Assessment & Baseline", "The coach prompts for missing baselines so prescriptions stay grounded in your measured fitness rather than population defaults.")
            }

            Section {
                deletedSessionsExcluded
                futureEventsExcluded
                beginnerStructure
                normalRhythm
                deterministicOutput
            } header: {
                domainHeader("Data Integrity & Edge Cases", "Guarantees the coach behaves predictably — deleted or future-dated training never pollutes the recommendation.")
            }

            // Reuse the bottom sections from CoachAboutView so this page
            // can serve as the canonical methodology reference.
            publishedStudiesSection

            disclaimer
        }
        .navigationTitle("Coach Methodology")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach.methodology")
    }

    // MARK: - Preamble

    private var preamble: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Every coaching recommendation is grounded in peer-reviewed exercise science. This page documents the specific rules and citations the coach follows — the same rules verified by the automated scientific validation suite that ships with the source code.")
                    .font(.subheadline)
                Text("The coach is a deterministic, on-device rule engine. Identical inputs always produce identical outputs. There is no AI, no cloud service, and no black box.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Domain A: Recovery & Safety

    private var painGate: some View {
        principleRow(
            icon: "bandage",
            title: "Pain or illness blocks hard training",
            description: "When you report pain or illness concern, the coach recommends rest and surfaces a safety warning. Hard sessions (strength, HIIT, sprint intervals) are gated.",
            citations: ["meeusenOvertraining2013"]
        )
    }

    private var liftRecoveryGate: some View {
        principleRow(
            icon: "clock.arrow.2.circlepath",
            title: "48-hour same-lift recovery window",
            description: "After a hard session of a specific lift, that exact exercise is deferred for 48 hours. The coach may still recommend a strength session — just with different movements. High-fatigue work (failure, RPE ≥ 9, or very high volume) extends the window to 72 hours.",
            citations: ["parejaBlancoRecovery2020"]
        )
    }

    private var consecutiveHardDays: some View {
        principleRow(
            icon: "exclamationmark.triangle",
            title: "Consecutive hard-day warning",
            description: "Six or more consecutive hard training days trigger an overtraining-risk warning. The coach may elevate recovery or rest sessions as a counterbalance.",
            citations: ["meeusenOvertraining2013", "drewFinchInjury2016"]
        )
    }

    private var volumeWarnings: some View {
        principleRow(
            icon: "chart.bar.xaxis.ascending",
            title: "Per-body-part volume warnings",
            description: "When a single body part exceeds 20 working sets in a week, the coach warns about diminishing returns. The dose-response evidence supports a graded benefit up to this range; exceeding it yields smaller additional gains for most lifters.",
            citations: ["pellandDoseResponse2026", "volumeDoseResponse"]
        )
    }

    // MARK: - Domain B: Balance & Priority

    private var aerobicFloor: some View {
        principleRow(
            icon: "figure.walk.motion",
            title: "Aerobic deficit prioritizes cardio",
            description: "When your weekly strength target is met but aerobic minutes are below the 150-minute equivalent floor, the coach recommends easy or moderate aerobic work. Physical activity attenuates mortality risk — the recommendation is health-grounded, not just a performance metric.",
            citations: ["ekelundActivityMortality2016", "mooreLeisureActivity2012", "aremDoseResponse2015"]
        )
    }

    private var strengthFloor: some View {
        principleRow(
            icon: "dumbbell",
            title: "Strength deficit prioritizes lifting",
            description: "When your aerobic floor is met but you have not hit your strength days target, the coach recommends a strength session. The loading parameters (reps, sets, RIR) follow the repetition continuum for your chosen goal: strength, hypertrophy, or endurance.",
            citations: ["schoenfeld2021", "currierResistancePrescription2023"]
        )
    }

    private var harderOptions: some View {
        principleRow(
            icon: "flame",
            title: "VO\u{2082} and anaerobic intervals surface after base is built",
            description: "Once both the strength and aerobic floors are satisfied (strength \u{2265} 2 days, aerobic \u{2265} 75 min moderate-equivalent), the coach surfaces harder options: VO\u{2082}max intervals (4\u{00D7}4, etc.), threshold tempo work, and sprint intervals. These are never prescribed to someone still building their base.",
            citations: ["crowleyVO2Intensity2022", "poonHIIT2024", "hiitVo2max", "kaufmannThreshold2023", "slothSIT2013"]
        )
    }

    private var frequencyDistribution: some View {
        principleRow(
            icon: "calendar.badge.plus",
            title: "Strength volume distributed across the week",
            description: "The weekly plan spreads your remaining strength sessions across distinct days rather than stacking them on one day. Spreading weekly volume across multiple sessions improves per-set quality and recovery. The plan also auto-balances body-part coverage so you hit everything in a week.",
            citations: ["frequencyMeta", "ramosCampoSplit2024"]
        )
    }

    private var twoADayCompletion: some View {
        principleRow(
            icon: "checkmark.circle",
            title: "Two-a-day completion detection",
            description: "When you do both strength and cardio on the same day (with two-a-days enabled), the coach recognizes the day as complete and shows a \"Strength and cardio — both in the books\" message with a tomorrow preview. Concurrent training is well-supported when properly sequenced.",
            citations: ["schumannConcurrent2022", "murlasitsConcurrentSequence2018"]
        )
    }

    // MARK: - Domain C: Preference Learning

    private var modalityPreference: some View {
        principleRow(
            icon: "heart.text.square",
            title: "Modality preferences are learned and remembered",
            description: "When you pick an alternative aerobic modality (e.g. cycling over walking), the coach records your selection and surfaces that modality first on future eligible days. The preference survives app restarts and is included in JSON exports.",
            citations: []
        )
    }

    private var highImpactAvoidance: some View {
        principleRow(
            icon: "figure.run.square.stack",
            title: "High-impact avoidance",
            description: "If you consistently avoid high-impact sessions (e.g. running), the coach deprioritizes them in favor of low-impact alternatives (walk, cycle, swim, row) that fulfill the same training intent. The avoidance tag is learned from the sessions you skip.",
            citations: []
        )
    }

    private var exercisePreference: some View {
        principleRow(
            icon: "list.bullet.clipboard",
            title: "Exercise selection follows your training history",
            description: "Fresh strength sessions auto-populate the exercises you train most often per movement pattern. The coach scans your rolling 28-day history and picks the top lift for each pattern — making the default session feel personal without hard-coding a program.",
            citations: []
        )
    }

    // MARK: - Domain D: Assessment & Baseline

    private var assessmentPrompt: some View {
        principleRow(
            icon: "checklist",
            title: "Missing baselines trigger assessment prompts",
            description: "When you are actively training a system (e.g. strength) but have never completed a baseline test (e.g. e1RM or rep-max), the coach surfaces an assessment candidate. Load targets are more accurate when anchored to your own measured capacity.",
            citations: ["oneRMEstimation", "cooperVo2max"]
        )
    }

    private var thresholdEligibility: some View {
        principleRow(
            icon: "waveform.path.ecg.rectangle",
            title: "Threshold tempo requires an established base",
            description: "Threshold/tempo training is gated behind at least 90 moderate-equivalent aerobic minutes per week. Threshold work builds on aerobic capacity — prescribing it before a base is established undermines its effectiveness and increases injury risk for untrained individuals.",
            citations: ["kaufmannThreshold2023"]
        )
    }

    private var freshAssessmentSilence: some View {
        principleRow(
            icon: "checkmark.shield",
            title: "Recent assessments suppress redundant prompts",
            description: "Once you have a valid baseline for a system, the coach stops nagging for it. Field-based fitness tests show acceptable reliability within their validity windows; the coach respects that and only re-prompts when baselines go stale.",
            citations: ["fieldFitnessReliability2022"]
        )
    }

    // MARK: - Domain E: Data Integrity & Edge Cases

    private var deletedSessionsExcluded: some View {
        principleRow(
            icon: "trash.slash",
            title: "Soft-deleted sessions are fully excluded",
            description: "Deleting a workout (which performs a soft-delete locally to preserve import merge idempotency) removes it from weekly volume counts, recovery windows, and all coach computations. The coach never reasons over deleted data.",
            citations: []
        )
    }

    private var futureEventsExcluded: some View {
        principleRow(
            icon: "clock.badge.xmark",
            title: "Future-dated events are excluded",
            description: "Workouts with a future start date — whether from clock-skew or scheduled imports — are ignored in the rolling 72h/7d/28d windows and the weekly balance. The coach only counts completed work whose end time is in the past.",
            citations: []
        )
    }

    private var beginnerStructure: some View {
        principleRow(
            icon: "figure.strengthtraining.traditional",
            title: "Beginners get structured full-body programming",
            description: "When you have fewer than 5 logged sessions and your experience is set to beginner, the coach generates Full-body A and Full-body B candidate sessions with reduced exercise selection, lower complexity, and conservative volume — matching the loading recommendations for novice lifters.",
            citations: ["schoenfeld2021"]
        )
    }

    private var normalRhythm: some View {
        principleRow(
            icon: "rhombus",
            title: "Normal training rhythm is not flagged",
            description: "Two consecutive hard days does not trigger an overtraining warning. The 6-day threshold is intentionally conservative; 2–3 hard days followed by easier days is a normal, well-supported training rhythm for most lifters. The coach respects that cadence.",
            citations: ["meeusenOvertraining2013"]
        )
    }

    private var deterministicOutput: some View {
        principleRow(
            icon: "equal.circle",
            title: "Deterministic — same inputs, same recommendation",
            description: "The coach is a pure function: identical workout history, settings, preferences, and reference date always produce identical primary session, score breakdowns, warnings, and insights. There is no randomness, no model training, no indeterminism. This property is verified by the automated test suite that runs on every build.",
            citations: []
        )
    }

    // MARK: - Shared sections

    private var publishedStudiesSection: some View {
        Section {
            ForEach(CitationRegistry.all) { citation in
                VStack(alignment: .leading, spacing: 4) {
                    CitationLink(citation: citation,
                                 context: CitationRegistry.usageReason(forId: citation.id))
                    Text(citation.source)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Complete Bibliography")
        } footer: {
            Text("Every study the coach cites, with one-line explanations of how it is used. Every methodology rule above references one or more entries from this list.")
        }
    }

    private var disclaimer: some View {
        Section {
            Text("These rules are verified by an automated scientific validation suite — \(validationTestCount) black-box tests that feed curated workout histories to the coach and assert the recommendations match published evidence. The tests ship with the CadenceCore source package and run on every build via swift test.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    /// Exact count from CoachScientificValidationTests
    private var validationTestCount: Int { 21 }

    private func domainHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(subtitle)
                .font(.caption)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private func principleRow(icon: String, title: String, description: String,
                               citations citationIds: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(description).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Render a CitationLink for each cited study
            if !citationIds.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(citationIds, id: \.self) { id in
                        if let citation = CitationRegistry.citation(forId: id) {
                            CitationLink(
                                citation: citation,
                                context: CitationRegistry.usageReason(forId: id),
                                compact: false)
                        }
                    }
                }
                .padding(.leading, 36)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CoachMethodologyView()
    }
}
