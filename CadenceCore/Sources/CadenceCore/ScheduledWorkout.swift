import Foundation
import SwiftData

/// A user-authored, one-off workout date. This is deliberately separate from
/// `PersistedPlan`: scheduling is execution state owned by this app, not a
/// DB++ weekly-program concept.
@Model
public final class ScheduledWorkout {
    public var id: UUID = UUID()
    /// Normalized start of day in the creator's calendar, retained for sorting
    /// and range queries.
    public var scheduledDate: Date = Date()
    /// Date-only semantic value (yyyy-MM-dd) so timezone changes do not silently
    /// move a user's scheduled workout to another displayed day.
    public var scheduledDayKey: String = ""
    public var timeZoneIdentifier: String = ""
    public var title: String = "Workout"
    /// Versioned app-side snapshot of the exact reviewed Workout Plan.
    public var payloadData: Data = Data()
    public var payloadVersion: Int = 1
    public var statusRaw: String = ScheduledWorkoutStatus.scheduled.rawValue
    public var startedSessionID: UUID?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date?
    public var originDevice: String = ""

    public init(id: UUID = UUID(), scheduledDate: Date = Date(),
                scheduledDayKey: String = "", timeZoneIdentifier: String = "",
                title: String = "Workout", payloadData: Data = Data(),
                payloadVersion: Int = 1,
                status: ScheduledWorkoutStatus = .scheduled,
                startedSessionID: UUID? = nil, createdAt: Date = Date(),
                updatedAt: Date = Date(), deletedAt: Date? = nil,
                originDevice: String = "") {
        self.id = id
        self.scheduledDate = scheduledDate
        self.scheduledDayKey = scheduledDayKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.title = title
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
        self.statusRaw = status.rawValue
        self.startedSessionID = startedSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDevice = originDevice
    }

    public var status: ScheduledWorkoutStatus {
        get { ScheduledWorkoutStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    public var isVisible: Bool {
        deletedAt == nil && status != .cancelled && status != .completed
    }
}

public enum ScheduledWorkoutStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case started
    case completed
    case cancelled
}

public enum ScheduledWorkoutDate {
    public static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func normalize(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = dayKeyFormatter
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }
}
