import SwiftUI
import CadenceCore
import UniformTypeIdentifiers

/// Full data export + JSON restore (FR-6.2).
struct ExportView: View {
    @Environment(\.modelContext) private var context

    enum Fmt: String, CaseIterable, Identifiable { case json = "JSON", csv = "CSV"; var id: String { rawValue } }
    @State private var format: Fmt = .json
    @State private var preview = ""
    @State private var restoreText = ""
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Format", selection: $format) {
                    ForEach(Fmt.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("export.format")
                .onChange(of: format) { _, _ in rebuild() }

                ScrollView {
                    Text(preview.isEmpty ? "No data to export." : preview)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("export.preview")
                }
                .frame(height: 200)

                ShareLink(item: preview) { Label("Share Export", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("export.share")
            } header: {
                Text("Export")
            } footer: {
                Text("Your full history. JSON round-trips back into Cadence; CSV opens in any spreadsheet.")
            }

            Section {
                TextEditor(text: $restoreText)
                    .frame(minHeight: 100)
                    .font(.system(.caption, design: .monospaced))
                    .accessibilityIdentifier("export.importText")
                Button("Restore from JSON") {
                    restore()
                }
                .disabled(restoreText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("export.import")
                if let restoreMessage {
                    Text(restoreMessage).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("export.importResult")
                }
            } header: {
                Text("Restore")
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .task { rebuild() }
    }

    private func rebuild() {
        guard let export = try? WorkoutRepository.buildExport(context) else { preview = ""; return }
        switch format {
        case .json:
            preview = (try? DataExport.encodeJSON(export)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        case .csv:
            preview = DataExport.encodeCSV(export)
        }
    }

    private func restore() {
        guard let data = restoreText.data(using: .utf8),
              let export = try? DataExport.decodeJSON(data) else {
            restoreMessage = "Couldn’t read that JSON."
            return
        }
        let added = (try? WorkoutRepository.merge(export, in: context)) ?? 0
        restoreMessage = "Restored \(added) session\(added == 1 ? "" : "s")."
        rebuild()
    }
}
