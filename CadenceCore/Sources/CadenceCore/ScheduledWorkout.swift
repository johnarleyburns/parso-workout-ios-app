import Foundation
import SwiftData

/// Legacy saved-workout storage retained for existing stores and archives.
/// New workouts use PlanningDraft; no date-based scheduling API remains.
@Model
public final class ScheduledWorkout {
    public var id: UUID = UUID()
    /// Normalized local date and time in the creator's calendar, retained for
    /// sorting and range queries. Older records may contain local midnight;
    /// those remain valid date-only schedules.
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

