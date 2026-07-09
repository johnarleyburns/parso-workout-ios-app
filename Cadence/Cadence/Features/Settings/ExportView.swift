import SwiftUI
import SwiftData
import CadenceCore
import UniformTypeIdentifiers
import os

/// Full data export + JSON restore (FR-6.2). Includes Coach preferences.
struct ExportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.cadenceModelContainer) private var container
    @Environment(AppSettings.self) private var settings

    enum Fmt: String, CaseIterable, Identifiable { case json = "JSON", csv = "CSV"; var id: String { rawValue } }
    @State private var format: Fmt = .json
    @State private var preview = ""
    @State private var exportError: String?
    @State private var isLoading = false
    @State private var restoreText = ""
    @State private var restoreMessage: String?

    private let logger = Logger(subsystem: "com.cladiron.cadence", category: "export")

    var body: some View {
        Form {
            Section {
                Picker("Format", selection: $format) {
                    ForEach(Fmt.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("export.format")
                .onChange(of: format) { _, _ in Task { await rebuild() } }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Building export...")
                        Spacer()
                    }
                    .frame(height: 200)
                    .accessibilityIdentifier("export.loading")
                } else {
                    ScrollView {
                        if let error = exportError {
                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("export.error")
                        } else {
                            Text(preview.isEmpty ? "No data to export." : preview)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("export.preview")
                        }
                    }
                    .frame(height: 200)
                }

                ShareLink(item: preview.isEmpty ? exportError ?? "" : preview) {
                    Label("Share Export", systemImage: "square.and.arrow.up")
                }
                    .disabled(isLoading)
                    .accessibilityIdentifier("export.share")
            } header: {
                Text("Export")
            } footer: {
                Text("A complete backup: strength history, cardio (with heart-rate and route data), fitness-test results, and all your preferences — including what the Coach has learned. Importing the JSON into a fresh install restores everything, as if nothing happened. CSV opens in any spreadsheet (strength sets only).")
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
        .task { await rebuildIfNeeded() }
    }

    private func rebuildIfNeeded() async {
        guard !isLoading else { return }
        await rebuild()
    }

    private func rebuild() async {
        guard let container else {
            exportError = "Database unavailable."
            return
        }
        isLoading = true
        exportError = nil
        defer { isLoading = false }

        let actor = ExportActor(modelContainer: container)
        let export: CadenceExport
        do {
            export = try await actor.buildExport(
                coachPreferences: settings.coachPreferenceProfile.exportDTO,
                preferences: settings.exportPreferences()
            )
        } catch {
            logger.error("Export build failed: \(error.localizedDescription)")
            exportError = "Export failed: \(error.localizedDescription)"
            preview = ""
            return
        }
        if export.sessions.isEmpty && export.cardio.isEmpty && export.assessments.isEmpty {
            preview = ""
            return
        }
        do {
            switch format {
            case .json:
                let data = try DataExport.encodeJSON(export)
                preview = String(data: data, encoding: .utf8) ?? ""
            case .csv:
                preview = DataExport.encodeCSV(export)
            }
        } catch {
            logger.error("Export encode failed: \(error.localizedDescription)")
            exportError = "Encode failed: \(error.localizedDescription)"
            preview = ""
        }
    }

    private func restore() {
        let data = restoreText.data(using: .utf8)
        guard let data,
              let export = try? DataExport.decodeJSON(data) else {
            restoreMessage = "Couldn't read that JSON."
            return
        }
        let added: Int
        do {
            added = try WorkoutRepository.merge(export, in: context)
        } catch {
            logger.error("Merge failed: \(error.localizedDescription)")
            restoreMessage = "Import failed: \(error.localizedDescription)"
            return
        }
        if let prefs = export.preferences { settings.applyImportedPreferences(prefs) }
        restoreMessage = "Restored \(added) workout\(added == 1 ? "" : "s")\(added == 0 && export.sessions.isEmpty && export.cardio.isEmpty && export.assessments.isEmpty ? " (file contained no data)" : "")\(export.preferences != nil ? " and your preferences" : "")."
        Task { await rebuild() }
    }
}
