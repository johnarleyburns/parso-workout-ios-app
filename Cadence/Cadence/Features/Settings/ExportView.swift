import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import UniformTypeIdentifiers
import os

/// Full data export + JSON restore (FR-6.2). Includes Coach preferences.
///
/// The export payload is **never** rendered as text — a monolithic SwiftUI
/// `Text` of a multi-MB JSON string laid out on the main thread was the cause of
/// the export watchdog freeze/crash. Instead we build the export off-main, write
/// it to a temp file, show a lightweight `ExportSummary` card, and share the file
/// URL. Restore reads a file via `.fileImporter` (magic-byte sniff: `.json.gz`,
/// `.gz`, plain `.json`, or standards-based `.fit`) and merges off-main.
struct ExportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.cadenceModelContainer) private var container
    @Environment(AppSettings.self) private var settings

    enum Fmt: String, CaseIterable, Identifiable {
        case json = "JSON", csv = "CSV", fit = "FIT"
        var id: String { rawValue }
    }
    @State private var format: Fmt = .json
    @State private var summary: ExportSummary?
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isLoading = false
    @State private var isEmpty = false

    @State private var isImporting = false
    @State private var restoreMessage: String?
    @State private var isRestoring = false

    @State private var buildTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.cladiron.cadence", category: "export")

    var body: some View {
        Form {
            Section {
                Picker("Format", selection: $format) {
                    ForEach(Fmt.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("export.format")
                .onChange(of: format) { _, _ in rebuild() }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Preparing export…")
                        Spacer()
                    }
                    .frame(height: 120)
                    .accessibilityIdentifier("export.loading")
                } else if let exportError {
                    Text(exportError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("export.error")
                } else if isEmpty {
                    Text("No data to export.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("export.summary")
                } else if let summary {
                    summaryCard(summary)
                        .accessibilityIdentifier("export.summary")
                }

                if let exportURL, !isLoading {
                    ShareLink(item: exportURL) {
                        Label("Share Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("export.share")
                }
            } header: {
                Text("Export")
            } footer: {
                Text(format == .fit
                     ? "FIT is a standards-based cardio/activity exchange file with workout timing, distance, calories, heart rate, and GPS route samples. It does not contain strength sets, assessments, or preferences; use JSON for a complete backup."
                     : "A complete backup: strength history, cardio (with heart-rate and route data), fitness-test results, and all your preferences — including what the Coach has learned. The JSON backup is compressed (.json.gz) and importing it into a fresh install restores everything, as if nothing happened. CSV opens in any spreadsheet (strength sets only).")
            }

            Section {
                Button {
                    isImporting = true
                } label: {
                    if isRestoring {
                        HStack { ProgressView(); Text("Restoring…") }
                    } else {
                        Label("Import from File", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isRestoring)
                .accessibilityIdentifier("export.import")
                if let restoreMessage {
                    Text(restoreMessage).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("export.importResult")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Choose a Cladiron backup (.json.gz or .json), or a FIT activity file. JSON restores the complete backup; FIT imports cardio activity data and merges it with your existing history.")
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: importContentTypes,
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .task { rebuildIfNeeded() }
    }

    private var importContentTypes: [UTType] {
        var types: [UTType] = [.json]
        types.append(.gzip)
        if let jsonGz = UTType(filenameExtension: "gz") { types.append(jsonGz) }
        if let fit = UTType(filenameExtension: "fit") { types.append(fit) }
        types.append(.data)
        return types
    }

    @ViewBuilder
    private func summaryCard(_ s: ExportSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("Strength", value: String(localized: "Sessions: \(s.strengthSessionCount) · Sets: \(s.strengthSetCount)"))
            if s.cardioCount > 0 {
                summaryRow("Cardio", value: String(localized: "\(s.cardioCount) workouts"))
                if !s.cardioByType.isEmpty {
                    Text(cardioBreakdown(s.cardioByType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if s.hrSampleCount > 0 || s.routeSampleCount > 0 {
                summaryRow(String(localized: "Samples"), value: "\(s.hrSampleCount) HR · \(s.routeSampleCount) route")
            }
            if s.assessmentCount > 0 {
                summaryRow(String(localized: "Fitness tests"), value: "\(s.assessmentCount)")
            }
            if let span = dateSpan(s) {
                summaryRow(String(localized: "Date range"), value: span)
            }
            if s.includesPreferences {
                summaryRow(String(localized: "Preferences"), value: "\(s.preferenceKeyCount) settings\(s.includesCoachProfile ? " · Coach profile" : "")")
            }
            Divider()
            summaryRow(String(localized: "Backup size"), value: sizeText(s))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }

    private func cardioBreakdown(_ byType: [String: Int]) -> String {
        ExportPresenter.cardioBreakdown(byType)
    }

    private func dateSpan(_ s: ExportSummary) -> String? {
        ExportPresenter.dateSpan(s)
    }

    private func sizeText(_ s: ExportSummary) -> String {
        ExportPresenter.sizeText(s, isCSV: format == .csv)
    }

    private func rebuildIfNeeded() {
        guard !isLoading else { return }
        rebuild()
    }

    private func rebuild() {
        guard let container else {
            exportError = String(localized: "Database unavailable.")
            return
        }
        buildTask?.cancel()
        isLoading = true
        exportError = nil
        isEmpty = false

        let fmt = format
        let coachDTO = settings.coachPreferenceProfile.exportDTO
        let prefs = settings.exportPreferences()

        buildTask = Task.detached(priority: .userInitiated) { [container] in
            let ctx = ModelContext(container)
            let export: CadenceExport
            do {
                export = try WorkoutRepository.buildExport(ctx,
                    coachPreferences: coachDTO,
                    preferences: prefs)
            } catch {
                await finish(error: String(localized: "Export failed: \(error.localizedDescription)"))
                return
            }
            if Task.isCancelled { return }

            let payload: CadenceExport
            switch fmt {
            case .json: payload = export
            case .csv: payload = CadenceExport(sessions: export.sessions)
            case .fit: payload = CadenceExport(sessions: [], cardio: export.cardio)
            }

            if payload.sessions.isEmpty && payload.cardio.isEmpty && payload.assessments.isEmpty {
                await MainActor.run {
                    self.summary = nil
                    self.exportURL = nil
                    self.isEmpty = true
                    self.isLoading = false
                }
                return
            }

            do {
                let url: URL
                let rawBytes: Int
                let compressedBytes: Int
                switch fmt {
                case .json:
                    let raw = try DataExport.encodeJSON(export)
                    let gz = try DataCompression.gzip(raw)
                    rawBytes = raw.count
                    compressedBytes = gz.count
                    url = try writeTempFile(gz, ext: "json.gz")
                case .csv:
                    let csv = DataExport.encodeCSV(export)
                    let data = Data(csv.utf8)
                    rawBytes = data.count
                    compressedBytes = 0
                    url = try writeTempFile(data, ext: "csv")
                case .fit:
                    let data = try DataExport.encodeFIT(export)
                    rawBytes = data.count
                    compressedBytes = 0
                    url = try writeTempFile(data, ext: "fit")
                }
                if Task.isCancelled { return }
                let summary = ExportSummary.from(payload, rawByteCount: rawBytes, compressedByteCount: compressedBytes)
                await MainActor.run {
                    self.summary = summary
                    self.exportURL = url
                    self.isEmpty = false
                    self.isLoading = false
                }
            } catch {
                await finish(error: String(localized: "Encode failed: \(error.localizedDescription)"))
            }
        }
    }

    @MainActor
    private func finish(error: String) {
        self.exportError = error
        self.summary = nil
        self.exportURL = nil
        self.isLoading = false
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let container else {
            restoreMessage = String(localized: "Database unavailable.")
            return
        }
        let url: URL
        switch result {
        case .success(let urls):
            guard let first = urls.first else { return }
            url = first
        case .failure(let error):
            restoreMessage = String(localized: "Couldn't open that file: \(error.localizedDescription)")
            return
        }

        isRestoring = true
        restoreMessage = nil
        let prefsSink = settings

        Task { [container] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = values.fileSize, fileSize > DataExport.maxImportBytes {
                    throw DataExport.ImportError.inputTooLarge
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let isFIT = DataExport.isFIT(data)
                let export = try DataExport.decodeAny(data)
                let ctx = ModelContext(container)
                let added = try WorkoutRepository.merge(export, in: ctx)
                await MainActor.run {
                    if let prefs = export.preferences { prefsSink.applyImportedPreferences(prefs) }
                    let noData = added == 0 && export.sessions.isEmpty && export.cardio.isEmpty
                        && export.assessments.isEmpty && export.suggestionExclusions.isEmpty
                    let exclusionCount = export.suggestionExclusions.count
                    self.restoreMessage = [
                        String(localized: "Restored \(added) workouts."),
                        noData ? String(localized: "The file contained no data.") : nil,
                        isFIT ? String(localized: "This was a FIT cardio activity; JSON is the full backup format.") : nil,
                        exclusionCount > 0 ? String(localized: "Also restored \(exclusionCount) suggestion preferences.") : nil,
                        export.preferences != nil ? String(localized: "Your preferences were restored too.") : nil
                    ].compactMap { $0 }.joined(separator: " ")
                    self.isRestoring = false
                    self.rebuild()
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Import failed: \(error.localizedDescription)")
                    self.restoreMessage = String(localized: "Import failed: \(error.localizedDescription)")
                    self.isRestoring = false
                }
            }
        }
    }
}

/// Writes `data` to a fresh temp file named `Cladiron-Export-<ISO8601>.<ext>`,
/// clearing any stale Cladiron exports first so the temp dir doesn't accumulate.
private func writeTempFile(_ data: Data, ext: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
    if let existing = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
        for f in existing where f.lastPathComponent.hasPrefix("Cladiron-Export-") {
            try? FileManager.default.removeItem(at: f)
        }
    }
    let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                            formatOptions: [.withFullDate])
    let url = dir.appendingPathComponent("Cladiron-Export-\(stamp).\(ext)")
    try data.write(to: url, options: .atomic)
    return url
}
