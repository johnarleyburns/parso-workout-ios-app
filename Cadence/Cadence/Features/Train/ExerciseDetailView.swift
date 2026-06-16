import SwiftUI
import CadenceCore

/// In-app exercise detail (strength-pivot P2). Replaces the old external EXRX.NET
/// link: the public-domain demonstration image, muscles, and step-by-step
/// instructions now ship on-device (free-exercise-db, Unlicense), so the user never
/// leaves the app and works fully offline. "Add to workout" picks the movement.
struct ExerciseDetailView: View {
    let exercise: Exercise
    var onPick: ((Exercise) -> Void)?

    private var imageURL: URL? { ExerciseLibrary.imageURL(forImageName: exercise.imageName) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        default:
                            Color(.secondarySystemBackground)
                                .frame(height: 200)
                                .overlay(ProgressView())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("\(exercise.name) demonstration")
                }

                facets

                if !primaryMuscles.isEmpty || !secondaryMuscles.isEmpty {
                    muscles
                }

                if !exercise.instructions.isEmpty {
                    instructions
                }
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onPick {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") { onPick(exercise) }
                        .accessibilityIdentifier("detail.add")
                }
            }
        }
        .accessibilityIdentifier("exercise.detail")
    }

    // MARK: Sections

    private var facets: some View {
        HStack(spacing: 8) {
            if let level = exercise.level { tag(level.capitalized) }
            if let eq = exercise.equipmentValue { tag(eq.displayName) }
            if let cat = exercise.categoryValue { tag(cat.displayName) }
        }
        .accessibilityElement(children: .combine)
    }

    private var muscles: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !primaryMuscles.isEmpty {
                Text("Targets").font(.headline)
                Text(primaryMuscles.joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
            if !secondaryMuscles.isEmpty {
                Text("Also works").font(.subheadline.weight(.semibold)).padding(.top, 2)
                Text(secondaryMuscles.joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions").font(.headline)
            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                    Text(step)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    private var primaryMuscles: [String] { exercise.primaryMuscles.map(Self.display) }
    private var secondaryMuscles: [String] { exercise.secondaryMuscles.map(Self.display) }

    /// "upper-chest" → "Upper Chest".
    static func display(_ id: String) -> String {
        id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(.tint)
    }
}
