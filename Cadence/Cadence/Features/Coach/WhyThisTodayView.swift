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
                            let resolved = resolvedCitations(d.reason.citationIds)
                            if !resolved.isEmpty {
                                ForEach(resolved) { citation in
                                    CitationLink(citation: citation, compact: true)
                                }
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
                    CitationLink(citation: CitationRegistry.schoenfeld2021, compact: true)
                }
                Text("• \(Int(decision.weeklyBalance.moderateEquivalentMinutes)) moderate-equivalent aerobic minutes (target: 150)").font(.caption)
                CitationLink(citation: CitationRegistry.ekelundActivityMortality2016, compact: true)
                Text("• \(decision.weeklyBalance.consecutiveHardDays) consecutive hard days").font(.caption)
                CitationLink(citation: CitationRegistry.meeusenOvertraining2013, compact: true)
            }

            if !decision.warnings.isEmpty {
                Section("Coach Warnings") {
                    ForEach(decision.warnings) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.message).font(.caption)
                            let resolved = resolvedCitations(w.citationIds)
                            if !resolved.isEmpty {
                                ForEach(resolved) { citation in
                                    CitationLink(citation: citation, compact: true)
                                }
                            }
                        }
                    }
                }
            }

            if !decision.citationIds.isEmpty {
                Section("Evidence") {
                    let resolved = resolvedCitations(decision.citationIds)
                    ForEach(resolved) { citation in
                        CitationLink(citation: citation)
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

    private func resolvedCitations(_ ids: [String]) -> [Citation] {
        ids.compactMap { CitationRegistry.citation(forId: $0) }
    }
}
