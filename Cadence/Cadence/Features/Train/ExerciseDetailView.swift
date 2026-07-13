import SwiftUI
import CadenceCore

struct ExerciseDetailView: View {
    let exercise: Exercise
    var actionTitle: String = "Add"
    var onPick: ((Exercise) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showEditSheet = false

    private var imageURLs: [URL] { ExerciseLibrary.imageURLs(forImageName: exercise.imageName) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !imageURLs.isEmpty {
                    imageRow
                }

                if exercise.isCustom {
                    customEditBanner
                }

                facets

                if !primaryMuscles.isEmpty || !secondaryMuscles.isEmpty {
                    muscles
                }

                if !exercise.instructions.isEmpty {
                    instructions
                }

                attribution
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        exercise.isFavorite.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: exercise.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(exercise.isFavorite ? .pink : .secondary)
                    }
                    .accessibilityLabel(exercise.isFavorite ? "Remove from favorites" : "Add to favorites")
                    if let onPick {
                        Button(actionTitle) { onPick(exercise); dismiss() }
                            .accessibilityIdentifier("detail.add")
                    }
                }
            }
        }
        .accessibilityIdentifier("exercise.detail")
        .sheet(isPresented: $showEditSheet) {
            CustomExerciseEditView(exercise: exercise)
        }
    }

    // MARK: Sections

    private var customEditBanner: some View {
        HStack {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Exercise")
                    .font(.subheadline.weight(.semibold))
                Text("Tag muscles, equipment, and region so it counts in your stats.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit") { showEditSheet = true }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Image/Content Sections

    private var imageRow: some View {
        HStack(spacing: 8) {
            ForEach(imageURLs, id: \.self) { url in
                exerciseImage(url: url)
            }
        }
        .accessibilityLabel("\(exercise.name) demonstration")
    }

    @ViewBuilder
    private func exerciseImage(url: URL) -> some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        Color(.secondarySystemBackground)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "photo.slash")
                        .font(.title3).foregroundStyle(.secondary)
                    Text("Image not available")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var facets: some View {
        FlowLayout(spacing: 8) {
            ForEach(exercise.displayFacetTags, id: \.self) { tag($0) }
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

    private var attribution: some View {
        HStack(spacing: 4) {
            Text("Exercise data:")
                .font(.caption2).foregroundStyle(.tertiary)
            Link("free-exercise-db", destination: ExerciseLibrary.exerciseRepoURL)
                .font(.caption2)
            Text("(public domain)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: Helpers

    private var primaryMuscles: [String] { exercise.primaryMuscles.map(Self.display) }
    private var secondaryMuscles: [String] { exercise.secondaryMuscles.map(Self.display) }

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
