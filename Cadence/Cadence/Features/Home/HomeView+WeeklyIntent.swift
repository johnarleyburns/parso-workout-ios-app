import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
    /// Cheap, date-bounded recompute of just the weekly rings, independent of
    /// `refreshHomeActivitySnapshot`'s full-history projection. Must never call
    /// `WorkoutRepository.allSessions` or `.allCardio`.
    func refreshWeeklyIntentSnapshot() async {
        guard let container = cadenceModelContainer else { return }
        let now = Date()
        let weekStart = WeeklyStats.weekStart(now: now)
        let passiveSamples = self.passiveSamples
        let userAge = settings.userAge
        let maximumHROverride = settings.cardioMaximumHROverride
        let snapshot = await Task.detached(priority: .userInitiated) { [container, now, weekStart, passiveSamples, userAge, maximumHROverride] in
            let backgroundContext = ModelContext(container)
            let sessions = (try? WorkoutRepository.sessions(since: weekStart, in: backgroundContext)) ?? []
            let cardio = (try? WorkoutRepository.cardio(since: weekStart, in: backgroundContext)) ?? []
            let profile = CardioIntensityProfile.forHome(
                passiveSamples: passiveSamples, userAge: userAge, maximumHROverride: maximumHROverride)
            return HomeWeeklyIntentProjection.make(
                sessions: sessions, cardio: cardio, weekStart: weekStart, now: now, cardioProfile: profile)
        }.value
        guard !Task.isCancelled else { return }
        weeklyIntent = snapshot
        publishCachedDashboard()
        await HomeWeeklyIntentCache.store.save(snapshot)
    }
}
