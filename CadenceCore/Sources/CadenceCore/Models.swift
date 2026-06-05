import Foundation
import SwiftData

// MARK: - Models
//
// CloudKit compatibility rules (REQUIREMENTS §7, FR-9):
//  • every stored property is optional OR has a default value
//  • every relationship is optional
//  • no @Attribute(.unique) — CloudKit does not support unique constraints
//  • inverse is declared on exactly one side of each relationship
//
// Rich set/rep/weight detail lives here in SwiftData. HealthKit (added later)
// only ever gets a summary HKWorkout.

@Model
public final class Exercise {
    public var name: String = ""
    public var category: String?
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \SetEntry.exercise)
    public var sets: [SetEntry]? = []

    public init(name: String = "", category: String? = nil, createdAt: Date = Date()) {
        self.name = name
        self.category = category
        self.createdAt = createdAt
    }
}

@Model
public final class WorkoutSession {
    public var title: String = ""
    public var date: Date = Date()
    public var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session)
    public var sets: [SetEntry]? = []

    public init(title: String = "", date: Date = Date(), notes: String? = nil) {
        self.title = title
        self.date = date
        self.notes = notes
    }

    /// Sets in logged order.
    public var orderedSets: [SetEntry] {
        (sets ?? []).sorted { $0.order < $1.order }
    }
}

@Model
public final class SetEntry {
    public var weight: Double = 0          // user's unit; kg by default for now
    public var reps: Int = 0
    public var order: Int = 0
    public var isWarmup: Bool = false
    public var completedAt: Date = Date()

    // To-one relationships (inverses declared on the parents above).
    public var session: WorkoutSession?
    public var exercise: Exercise?

    public init(weight: Double = 0,
                reps: Int = 0,
                order: Int = 0,
                isWarmup: Bool = false,
                completedAt: Date = Date(),
                session: WorkoutSession? = nil,
                exercise: Exercise? = nil) {
        self.weight = weight
        self.reps = reps
        self.order = order
        self.isWarmup = isWarmup
        self.completedAt = completedAt
        self.session = session
        self.exercise = exercise
    }
}
