import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

extension ExercisePickerView {
    enum FindScope: String, CaseIterable, Identifiable {
        case all = "All", recents = "Recents", popular = "Popular"
        case equipment = "Equipment", muscleGroup = "Muscle Group"
        var id: Self { self }
        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .recents: String(localized: "Recents")
            case .popular: String(localized: "Popular")
            case .equipment: String(localized: "Equipment")
            case .muscleGroup: String(localized: "Muscle Group")
            }
        }
    }


    /// Find exposes one scope at a time; changing it also clears the old facet.
    func selectFindScope(_ scope: FindScope) {
        findScope = scope
        browseAll = false
        selectedGroup = nil
        selectedEquipment = nil
        switch scope {
        case .all: selectedTab = .browse
        case .recents: selectedTab = .recents
        case .popular: selectedTab = .popular
        case .equipment:
            selectedTab = .browse
            browseMode = .byEquipment
            selectedEquipment = availableEquipment.first
        case .muscleGroup:
            selectedTab = .browse
            browseMode = .byMuscleGroup
            selectedGroup = availableGroups.first
        }
        refreshSearchResults()
    }

}
