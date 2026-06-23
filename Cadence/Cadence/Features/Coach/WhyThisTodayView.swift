import SwiftUI
import CadenceCore

struct WhyThisTodayView: View {
    let decision: CoachDecision

    var body: some View {
        List {
            Section("What you did") {
                ForEach(decision.observedFacts, id: \.label) { fact in
                    HStack {
                        Text(fact.label).font(.subheadline)
                        Spacer()
                        Text(fact.timestamp, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !decision.deferred.isEmpty {
                Section("What Coach ruled out") {
                    ForEach(decision.deferred) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.session.title).font(.headline)
                            Text(d.reason.message).font(.caption).foregroundStyle(.red)
                            if !d.reason.citationIds.isEmpty {
                                Text(d.reason.citationIds.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Why this won") {
                Text("Coach selected \(decision.primary.title.lowercased()) because:").font(.subheadline)
                if decision.primary.kind == .strength {
                    Text("• \(decision.weeklyBalance.strengthDays) strength days this week (target: 2+)").font(.caption)
                }
                Text("• \(Int(decision.weeklyBalance.moderateEquivalentMinutes)) moderate-equivalent aerobic minutes (target: 150)").font(.caption)
                Text("• \(decision.weeklyBalance.consecutiveHardDays) consecutive hard days").font(.caption)
            }

            if !decision.warnings.isEmpty {
                Section("Coach Warnings") {
                    ForEach(decision.warnings) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.message).font(.caption)
                            if !w.citationIds.isEmpty {
                                Text(w.citationIds.joined(separator: ", ")).font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            Section("Policy") {
                Text("Coach's recovery windows are conservative defaults. They are not a diagnosis or a universal physiological law. Actual recovery varies by person, sleep, nutrition, and stress.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Why this today")
        .navigationBarTitleDisplayMode(.inline)
    }
}
