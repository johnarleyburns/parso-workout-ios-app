import SwiftUI
import CadenceCore

/// One-time Gmail-draft importer (FR-6.1, UC-7).
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var text = ""
    @State private var result: ImportResult?
    @State private var importedCount: Int?

    private static let sample = """
    # Push Day 2024-01-15
    Bench Press 100kg 3x5
    Overhead Press 60kg 5,5,4
    Incline DB Press 30kg 8x3 PR

    # Pull Day 2024-01-17
    Deadlift 180kg 5x1
    Barbell Row 80kg 3x8
    """

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("import.text")
                Button("Load Sample") { text = Self.sample }
                    .accessibilityIdentifier("import.sample")
            } header: {
                Text("Paste your workout log")
            } footer: {
                Text("Format: a header line (e.g. “# Push Day 2024-01-15”), then “Exercise weight setsxreps”. PR/last-time markers are ignored and recomputed.")
            }

            Section {
                Button("Parse") {
                    result = GmailImporter.parse(text, defaultUnit: settings.unit)
                    importedCount = nil
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("import.parse")
            }

            if let result {
                Section("Preview") {
                    Text("\(result.sessions.count) session\(result.sessions.count == 1 ? "" : "s") · \(result.totalSets) sets")
                        .font(.headline)
                        .accessibilityIdentifier("import.preview")
                    ForEach(Array(result.sessions.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.subheadline.weight(.semibold))
                            Text(s.exercises.map { "\($0.name) (\($0.sets.count))" }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !result.issues.isEmpty {
                        Text("\(result.issues.count) line\(result.issues.count == 1 ? "" : "s") couldn’t be parsed and will be skipped.")
                            .font(.caption).foregroundStyle(.orange)
                            .accessibilityIdentifier("import.issues")
                    }
                }

                if importedCount == nil {
                    Section {
                        Button("Import \(result.sessions.count) Session\(result.sessions.count == 1 ? "" : "s")") {
                            let n = (try? WorkoutRepository.apply(result.sessions, in: context)) ?? 0
                            importedCount = n
                        }
                        .disabled(result.sessions.isEmpty)
                        .accessibilityIdentifier("import.confirm")
                    }
                }
            }

            if let importedCount {
                Section {
                    Label("Imported \(importedCount) session\(importedCount == 1 ? "" : "s")",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("import.done")
                }
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
    }
}
