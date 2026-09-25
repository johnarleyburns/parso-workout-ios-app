import SwiftUI
import ImageIO
import CadenceCore

/// Photos, first steps, and facets for the Add Exercise preview's "Show
/// Detail" page. Split out of `WatchAddExerciseView` to keep that file within
/// the 400-line budget; the content is unchanged.
struct WatchExerciseDetailContent: View {
    let exercise: Exercise

    var body: some View {
        let imageURLs = ExerciseLibrary.imageURLs(forImageName: exercise.imageName)
        if !imageURLs.isEmpty {
            ForEach(imageURLs, id: \.self) { url in
                exerciseImage(url)
            }
        }

        if !exercise.instructions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(exercise.instructions.prefix(4).enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .font(.caption2)
                }
            }
        } else {
            Text(exercise.displayFacetTags.prefix(3).joined(separator: " "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func exerciseImage(_ url: URL) -> some View {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.18))
                .frame(height: 96)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
