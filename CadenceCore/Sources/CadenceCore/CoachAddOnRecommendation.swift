import Foundation

public enum CoachAddOnStatus: String, Sendable, Equatable, Codable {
    case encouraged
    case neutral
    case warn
}

public struct CoachAddOnOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let session: CoachSession
    public let status: CoachAddOnStatus
    public let message: String
    public let citationIds: [String]

    public init(id: String, session: CoachSession, status: CoachAddOnStatus,
                message: String, citationIds: [String] = []) {
        self.id = id
        self.session = session
        self.status = status
        self.message = message
        self.citationIds = citationIds
    }
}

public struct CoachAddOnRecommendation: Sendable, Equatable {
    public let primaryOption: CoachAddOnOption?
    public let secondaryOptions: [CoachAddOnOption]
    public let generatedAt: Date

    public static let empty = CoachAddOnRecommendation(
        primaryOption: nil, secondaryOptions: [], generatedAt: Date()
    )

    public init(primaryOption: CoachAddOnOption?, secondaryOptions: [CoachAddOnOption],
                generatedAt: Date) {
        self.primaryOption = primaryOption
        self.secondaryOptions = secondaryOptions
        self.generatedAt = generatedAt
    }
}
