import SwiftUI
import CadenceCore
import CadenceFeatures

extension OnboardingView {
    var privacyPage: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .scaledSystemFont(34, relativeTo: .largeTitle)
                .foregroundStyle(.tint)
                .frame(width: 72, height: 72)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            Text("Private by design")
                .font(.title.bold())
                .padding(.top, 22)
            Text("No account, no tracking, and no advertising. Your training log stays on your devices and your private iCloud database.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 24)
            storyRow("person.crop.circle.badge.xmark", "No account required")
            storyRow("location.slash", "No tracking outside workouts you start")
            storyRow("icloud.and.arrow.up", "Private iCloud sync when available")
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    var coachingPage: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "book.closed.fill")
                .scaledSystemFont(34, relativeTo: .largeTitle)
                .foregroundStyle(.orange)
                .frame(width: 72, height: 72)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            Text("Coaching you can check")
                .font(.title.bold())
                .padding(.top, 22)
            Text("Every suggestion explains what it is solving and links to the science behind the rule.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 24)
            CitationLink(citation: CitationRegistry.volumeDoseResponse,
                         context: "Read the science behind coaching", compact: true)
                .padding(.top, 16)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func storyRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
        .padding(.top, 18)
    }
}
