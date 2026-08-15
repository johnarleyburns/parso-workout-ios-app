import Foundation

public enum SessionRouteMode: Sendable, Equatable { case active, review }
public enum SessionSetSaveKind: Sendable, Equatable { case pending, finalPlanned, unplanned }

public enum SessionExerciseExpansionModel {
    public static func initial(exerciseIDs: [UUID], unfinishedIDs: Set<UUID>, mode: SessionRouteMode) -> UUID? {
        guard mode == .active else { return nil }
        return exerciseIDs.first(where: unfinishedIDs.contains)
    }
    public static func headerTapped(current: UUID?, tapped: UUID) -> UUID? { current == tapped ? nil : tapped }
    public static func setOpened(_ exerciseID: UUID) -> UUID { exerciseID }
    public static func afterSave(current: UUID?, savedExerciseID: UUID, nextUnfinishedID: UUID?, kind: SessionSetSaveKind) -> UUID? {
        switch kind { case .pending, .unplanned: savedExerciseID; case .finalPlanned: nextUnfinishedID }
    }
    public static func focused(requestedID: UUID?, existingIDs: Set<UUID>) -> UUID? {
        guard let requestedID, existingIDs.contains(requestedID) else { return nil }; return requestedID
    }
}
