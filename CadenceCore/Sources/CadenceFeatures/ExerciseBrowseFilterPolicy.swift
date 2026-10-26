import Foundation

/// Decides which exercise-browse filters survive a change of the muscle-group filter.
public enum ExerciseBrowseFilterPolicy {
    public enum Mode: Sendable { case byMuscleGroup, byEquipment }

    /// Equipment narrows the list when browsing by muscle group, so it resets with the
    /// group. When browsing by equipment, equipment is the primary filter and the
    /// group only narrows it, so the chosen equipment must be preserved.
    public static func resetsEquipmentOnGroupChange(mode: Mode) -> Bool {
        mode == .byMuscleGroup
    }
}
