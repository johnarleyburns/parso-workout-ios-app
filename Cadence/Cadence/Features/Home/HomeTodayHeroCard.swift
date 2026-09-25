import SwiftUI
import CadenceCore

struct HomeTodayHeroCard: View {
    let title: String
    let tag: String
    let estimatedMinutes: Int?
    let exercises: [(name: String, detail: String)]
    let reason: String?
    let citationIDs: [String]
    let onStart: () -> Void
    let onEdit: () -> Void
    let onChooseAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tag, systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CadenceTheme.accent)
                Spacer()
                if let estimatedMinutes {
                    Text("\(estimatedMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(title)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            if !exercises.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(exercises.prefix(5).enumerated()), id: \.offset) { _, exercise in
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(exercise.name)
                                Spacer(minLength: 8)
                                Text(exercise.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                Text(exercise.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
                    }
                }
            }

            if let reason {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(citationIDs, id: \.self) { citationID in
                        if let citation = CitationRegistry.citation(forId: citationID) {
                            CitationLink(citation: citation,
                                         context: "Why this workout", compact: true)
                        }
                    }
                }
            }

            Button(action: onStart) {
                Label("Start Workout", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CadenceTheme.accent)
            .controlSize(.large)
            .accessibilityIdentifier("home.hero.start")

            HStack(spacing: 18) {
                Button("Edit plan", action: onEdit)
                Button("Choose another", action: onChooseAnother)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .foregroundStyle(CadenceTheme.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(.hero)
        .accessibilityIdentifier("home.hero")
    }
}
