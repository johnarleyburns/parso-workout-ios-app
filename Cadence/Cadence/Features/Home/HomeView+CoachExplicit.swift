import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

extension HomeView {
    var strengthWarnings: [CoachWarning] {
        CoachWarningModalityFilter.filter(coachSnapshot.decision.warnings, for: .strength)
    }
    var cardioWarnings: [CoachWarning] {
        CoachWarningModalityFilter.filter(coachSnapshot.decision.warnings, for: .cardio)
    }

    /// Runs the full coach build only if nothing fresh for the current
    /// signature already exists this session — called from an explicit
    /// request, never automatically. Reuses `refreshCoachSnapshot()` so the
    /// ready flag and cached-dashboard publish side effects still happen.
    func ensureCoachSnapshotForExplicitRequest() async {
        let signature = coachSignature
        guard coachSnapshotSignatureUsed != signature else { return }
        await refreshCoachSnapshot()
        coachSnapshotSignatureUsed = signature
    }
}
