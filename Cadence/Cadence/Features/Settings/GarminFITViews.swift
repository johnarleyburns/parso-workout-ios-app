import SwiftUI
import SwiftData
import CadenceCore
import UniformTypeIdentifiers

/// `.fit` content type shared by the exporter and importer.
let garminFITContentType: UTType = UTType(filenameExtension: "fit") ?? .data

/// Write-only document wrapping already-encoded FIT bytes for `fileExporter`.
struct GarminFITDocument: FileDocument {
    static var readableContentTypes: [UTType] { [garminFITContentType] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private func message(for failure: GarminFITBridge.Failure) -> String {
    switch failure {
    case .invalidWorkout(.notFinished): String(localized: "Finish this workout before exporting it to a FIT file.")
    case .invalidWorkout(.deleted): String(localized: "This workout was deleted, so it can't be exported.")
    case .invalidWorkout(.noCompletedSets): String(localized: "Log at least one completed, non-warm-up set with an exercise, then export again.")
    case .serialization: String(localized: "Cladiron couldn't build the FIT file for this workout. Nothing was saved.")
    case .notFIT: String(localized: "That file isn't a FIT file. Choose a .fit activity file.")
    case .malformed: String(localized: "That FIT file looks damaged or incomplete, so nothing was imported.")
    case .tooLarge: String(localized: "That file is too large to import safely.")
    case .sidecarRequired: String(localized: "This FIT file was not made by Cladiron, so it has no exact workout data. Strict import never guesses sets and reps from a generic activity, and nothing was imported.")
    case .invalidSidecar: String(localized: "This FIT file's Cladiron workout data is invalid, so nothing was imported.")
    case .cancelled: String(localized: "Import cancelled. Nothing was changed.")
    case .writeFailed: String(localized: "Cladiron couldn't save the workout. Nothing was changed.")
    }
}

/// Export Garmin FIT action for one completed workout.
struct GarminFITExportButton: View {
    let session: WorkoutSession
    @State private var document: GarminFITDocument?
    @State private var filename = "Cladiron.fit"
    @State private var isExporting = false
    @State private var status: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                prepare()
            } label: {
                Label("Export Garmin FIT", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export Garmin FIT file")
            .accessibilityHint("Saves this workout as a .fit activity file on this device")
            .accessibilityIdentifier("fit.export")
            if let status {
                Text(status).font(.caption).foregroundStyle(isError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(isError ? "fit.export.error" : "fit.export.success")
            }
        }
        .fileExporter(isPresented: $isExporting, document: document,
                      contentType: garminFITContentType, defaultFilename: filename) { result in
            switch result {
            case .success:
                isError = false
                status = String(localized: "Saved. The file holds standard Garmin Activity, Session, Lap and Event messages plus a DB++ developer-field sidecar so Cladiron can re-import this workout exactly.")
            case .failure(let error):
                isError = true
                status = (error as? CocoaError)?.code == .userCancelled
                    ? String(localized: "Export cancelled. No file was written.")
                    : String(localized: "The file couldn't be written. Check the destination and try again.")
            }
            document = nil
        }
    }

    private func prepare() {
        do {
            let file = try GarminFITBridge.export(session: session)
            document = GarminFITDocument(data: file.data)
            filename = file.filename
            status = nil
            isExporting = true
        } catch let failure as GarminFITBridge.Failure {
            isError = true
            status = message(for: failure)
        } catch {
            isError = true
            status = message(for: .serialization)
        }
    }
}

/// Import Garmin FIT entry (strict, lossless-only) with preview + confirmation.
struct GarminFITImportSection: View {
    @Environment(\.modelContext) private var context
    var onImported: () -> Void = {}

    @State private var isPicking = false
    @State private var isWorking = false
    @State private var task: Task<Void, Never>?
    @State private var preview: GarminFITBridge.Preview?
    @State private var duplicateExists = false
    @State private var result: String?
    @State private var isError = false
    @State private var receipt: GarminFITBridge.Receipt?

    var body: some View {
        Section {
            if isWorking {
                HStack {
                    ProgressView()
                    Text("Reading FIT file…")
                    Spacer()
                    Button("Cancel") { task?.cancel() }.accessibilityIdentifier("fit.import.cancel")
                }
            } else {
                Button { isPicking = true } label: {
                    Label("Import Garmin FIT", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("fit.import")
            }
            if let preview { previewCard(preview) }
            if let result {
                Text(result).font(.caption).foregroundStyle(isError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(isError ? "fit.import.error" : "fit.import.result")
                if !isError, receipt?.replacedSessionID == nil, receipt != nil {
                    Button("Undo Import") { undo() }.accessibilityIdentifier("fit.import.undo")
                }
            }
        } header: {
            Text("Garmin FIT")
        } footer: {
            Text("Works offline on this device. Only FIT files exported by Cladiron (with the DB++ sidecar) import as strength workouts, exactly. Generic Garmin recordings without the sidecar are never guessed into sets and reps.")
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [garminFITContentType],
                      allowsMultipleSelection: false) { picked in handlePick(picked) }
    }

    @ViewBuilder
    private func previewCard(_ p: GarminFITBridge.Preview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(p.sourceFilename).font(.headline).accessibilityIdentifier("fit.preview.filename")
            Text("Start: \(p.start.formatted(date: .abbreviated, time: .shortened))")
            if let end = p.end { Text("End: \(end.formatted(date: .abbreviated, time: .shortened))") }
            Text("\(p.exerciseCount) exercises · \(p.setCount) sets")
            Label("Lossless: exact Cladiron workout data found", systemImage: "checkmark.seal")
                .accessibilityIdentifier("fit.preview.fidelity")
            ForEach(p.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            if duplicateExists {
                Text("A workout with this ID is already in your history. Choose what to do.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Keep Both (new copy, original ID noted)") { apply(.keepBoth) }
                    .accessibilityIdentifier("fit.import.keepBoth")
                Button("Replace Existing", role: .destructive) { apply(.replace) }
                    .accessibilityIdentifier("fit.import.replace")
            } else {
                Button("Import Workout") { apply(.cancel) }.accessibilityIdentifier("fit.import.confirm")
            }
            Button("Cancel", role: .cancel) { preview = nil }.accessibilityIdentifier("fit.import.dismiss")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func handlePick(_ picked: Result<[URL], Error>) {
        preview = nil; result = nil; receipt = nil
        guard case .success(let urls) = picked, let url = urls.first else {
            if case .failure = picked { fail(.malformed) }
            return
        }
        isWorking = true
        task = Task {
            let outcome: Result<GarminFITBridge.Preview, GarminFITBridge.Failure>
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= GarminFITBridge.maxFileBytes else { throw GarminFITBridge.Failure.tooLarge }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                outcome = .success(try await GarminFITBridge.previewOffMain(data: data, filename: url.lastPathComponent))
            } catch let failure as GarminFITBridge.Failure {
                outcome = .failure(failure)
            } catch {
                outcome = .failure(.malformed)
            }
            isWorking = false
            switch outcome {
            case .success(let p):
                preview = p
                duplicateExists = GarminFITBridge.existingSession(for: p, in: context) != nil
            case .failure(let failure):
                fail(failure)
            }
        }
    }

    private func apply(_ decision: GarminFITBridge.DuplicateDecision) {
        guard let preview else { return }
        do {
            let applied = try GarminFITBridge.apply(preview, to: context, duplicate: decision)
            receipt = applied
            isError = false
            result = applied == nil ? String(localized: "Nothing was imported.")
                : String(localized: "Imported exactly as exported. Your history now includes this workout.")
            self.preview = nil
            if applied != nil { onImported() }
        } catch let failure as GarminFITBridge.Failure {
            fail(failure)
        } catch {
            fail(.writeFailed)
        }
    }

    private func undo() {
        guard let receipt else { return }
        do {
            try GarminFITBridge.undo(receipt, in: context)
            self.receipt = nil
            result = String(localized: "Import undone.")
        } catch { fail(.writeFailed) }
    }

    private func fail(_ failure: GarminFITBridge.Failure) {
        isError = true
        preview = nil
        result = message(for: failure)
    }
}
