import SwiftUI
import CadenceCore

struct YourWeekView: View {
    let decision: CoachDecision
    let facts: CoachFacts

    var body: some View {
        let plan = WeeklyPlan.generate(from: facts)
        List {
            Section("Balanced fitness") {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "dumbbell.fill").foregroundStyle(.green)
                        Text("Strength").font(.subheadline)
                        Spacer()
                        Text("\(decision.weeklyBalance.strengthDays) of 2 days").font(.subheadline.bold())
                    }
                    ProgressView(value: min(1, Double(decision.weeklyBalance.strengthDays) / 2))
                        .tint(.green)

                    HStack {
                        Image(systemName: "heart.fill").foregroundStyle(.teal)
                        Text("Aerobic").font(.subheadline)
                        Spacer()
                        Text("\(Int(decision.weeklyBalance.moderateEquivalentMinutes)) of 150 min").font(.subheadline.bold())
                    }
                    ProgressView(value: min(1, decision.weeklyBalance.moderateEquivalentMinutes / 150))
                        .tint(.teal)
                }
                .padding(.vertical, 4)
            }

            Section("7-day outline") {
                let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                ForEach(Array(plan.days.enumerated()), id: \.offset) { i, day in
                    HStack {
                        Text(weekdays[i]).font(.caption).frame(width: 32, alignment: .leading)
                        Circle()
                            .fill(day.isCompleted ? (day.isHard ? Color.green : Color.teal) : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                        Text(day.label).font(.subheadline)
                        if day.isToday { Text("Today").font(.caption.bold()).foregroundStyle(.tint) }
                        Spacer()
                        if let kind = day.sessionKind {
                            Text(kindLabel(kind)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let vo2 = decision.weeklyBalance.vo2maxLatest {
                Section("VO₂max") {
                    HStack {
                        Text(String(format: "%.1f", vo2)).font(.title.bold()).foregroundStyle(.teal)
                        VStack(alignment: .leading) {
                            Text(decision.weeklyBalance.vo2maxProtocol ?? "Field test").font(.caption)
                            if let trend = decision.weeklyBalance.vo2maxTrend {
                                Text(trend == .rising ? "Improving" : trend == .declining ? "Declining" : "Stable")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Your week")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kindLabel(_ kind: CoachSessionKind) -> String {
        switch kind {
        case .strength: return "Hard"
        case .easyAerobic: return "Easy"
        case .moderateAerobic: return "Cardio"
        case .vo2Intervals: return "VO₂"
        case .recovery: return "Recovery"
        case .rest: return "Rest"
        case .assessment: return "Test"
        }
    }
}
