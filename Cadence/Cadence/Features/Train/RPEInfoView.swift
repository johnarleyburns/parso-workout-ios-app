import SwiftUI
import CadenceCore

/// Explains RPE (Rate of Perceived Exertion) and the RIR-based scale
/// so the user knows how to estimate it on every set.
struct RPEInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rate of Perceived Exertion — how hard a set felt, from 1 (very light) to 10 (maximal effort).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("How to estimate") {
                    ForEach(rpeScale, id: \.rpe) { row in
                        HStack(spacing: 12) {
                            Text("RPE \(row.rpe)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 48, alignment: .leading)
                                .foregroundStyle(rpeColor(row.rpe))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.label).font(.subheadline)
                                Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    HStack {
                        Text("RIR").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("Reps in Reserve — how many more reps you could have done")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("RIR = 10 − RPE (e.g., RPE 8 ≈ 2 RIR). Most working sets fall between RPE 7–9 (1–3 RIR).")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    CitationLink(citation: CitationRegistry.rpeAutoregulation)
                }
            }
            .navigationTitle("What is RPE?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private struct RPERow {
        let rpe: Int
        let label: String
        let detail: String
    }

    private let rpeScale: [RPERow] = [
        .init(rpe: 10, label: "Maximal", detail: "Couldn't do another rep (0 RIR)"),
        .init(rpe: 9, label: "Very hard", detail: "Could do 1 more rep (1 RIR)"),
        .init(rpe: 8, label: "Hard", detail: "Could do 2 more reps (2 RIR)"),
        .init(rpe: 7, label: "Moderately hard", detail: "Could do 3 more reps (3 RIR)"),
        .init(rpe: 6, label: "Moderate", detail: "Could do 4+ more reps"),
        .init(rpe: 5, label: "Light", detail: "Warm-up feel, easy"),
        .init(rpe: 4, label: "Very light", detail: "Barely any effort"),
        .init(rpe: 3, label: "Minimal", detail: "Movement practice"),
        .init(rpe: 2, label: "Trivial", detail: "No effort at all"),
        .init(rpe: 1, label: "Rest", detail: "No exertion"),
    ]

    private func rpeColor(_ rpe: Int) -> Color {
        switch rpe {
        case 9...10: return .red
        case 7...8:  return .orange
        case 5...6:  return .yellow
        default:     return .secondary
        }
    }
}
