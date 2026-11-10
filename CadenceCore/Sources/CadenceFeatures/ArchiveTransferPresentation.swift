import Foundation
import CadenceCore

/// Which half of the archive screen is shown: export (My Workouts) or restore (Settings).
public enum ArchiveFlowMode: Equatable, Sendable {
    case exportOnly
    case restoreOnly
}

/// Pure control visibility for the archive screen; never both export and restore.
public struct ArchiveFlowPresentation: Equatable, Sendable {
    public let mode: ArchiveFlowMode
    public init(mode: ArchiveFlowMode) { self.mode = mode }
    public var showsExportControls: Bool { mode == .exportOnly }
    public var showsRestoreControls: Bool { mode == .restoreOnly }
    public var navigationTitle: String {
        switch mode {
        case .exportOnly: return String(localized: "Export", bundle: .module)
        case .restoreOnly: return String(localized: "Restore", bundle: .module)
        }
    }
}

/// Export formats and the single mapping from a full export to each format's payload.
public enum ArchiveExportFormat: String, CaseIterable, Identifiable, Sendable {
    case json = "JSON", csv = "CSV", fit = "FIT"
    public var id: String { rawValue }

    /// Narrows the complete export to what the format can carry.
    public func payload(from export: CadenceExport) -> CadenceExport {
        switch self {
        case .json: return export
        case .csv: return CadenceExport(sessions: export.sessions)
        case .fit: return CadenceExport(sessions: [], cardio: export.cardio)
        }
    }
}

public enum ArchiveExportScope: Equatable, Sendable {
    case completeArchive
    case visiblePage
}

/// An export request. It deliberately has no page limit or cursor.
public struct ArchiveExportRequest: Equatable, Sendable {
    public let scope: ArchiveExportScope
    public let format: ArchiveExportFormat
    /// Always the complete archive, regardless of how much history is loaded on screen.
    public init(format: ArchiveExportFormat = .json) {
        self.scope = .completeArchive
        self.format = format
    }
}

/// Header/backup action models (pure test seam for the views' button lists).
public enum ArchiveActionPresenter {
    public static let historyHeaderActions: [String] = ["Export"]
    public static let settingsBackupActions: [String] = ["Restore or Import"]
}

public enum ArchiveExportState: Equatable, Sendable {
    case preparing
    case failed(String)
    case empty
    case ready

    public var message: String? {
        switch self {
        case .preparing: return String(localized: "Preparing export…", bundle: .module)
        case .failed(let m): return m
        case .empty: return String(localized: "No data to export.", bundle: .module)
        case .ready: return nil
        }
    }
    public var accessibilityIdentifier: String {
        switch self {
        case .preparing: return "export.loading"
        case .failed: return "export.error"
        case .empty, .ready: return "export.summary"
        }
    }
    public var offersShare: Bool { self == .ready }
}
