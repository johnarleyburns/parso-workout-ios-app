import SwiftUI
import CadenceCore
import CadenceFeatures

/// The zero-privacy-cost growth loop (revenue plan Phase 6, decision D6): a
/// branded PR card the user can render to a PNG and share. **No account, no
/// server, nothing leaves the device but an image the user explicitly chose to
/// post.**
///
/// `ImageRenderer` rasterises a plain SwiftUI card off the live view tree; the
/// PNG is written to the temp dir and handed to `ShareLink` as a URL.
struct ShareCardRenderer {

    /// The branded card that gets rasterised. Kept deliberately simple — no
    /// environment dependencies — so `ImageRenderer` produces a deterministic
    /// image at any scale.
    struct PRCard: View {
        let exerciseName: String
        let valueLabel: String
        let detailLabel: String?
        let dateLabel: String

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                    Text("NEW PR")
                        .font(.subheadline.weight(.heavy))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                Text(exerciseName)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 18)
                Text(valueLabel)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 2)
                if let detailLabel {
                    Text(detailLabel)
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
                Spacer(minLength: 24)
                HStack {
                    Text(dateLabel)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("Cladiron")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(28)
            .frame(width: 360, height: 360, alignment: .topLeading)
            .background(
                LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20),
                                        Color(red: 0.06, green: 0.30, blue: 0.42)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
    }

    /// Render a PR event to a shareable PNG URL. Returns nil if rasterisation or
    /// the temp-file write fails. Runs on the main actor (ImageRenderer requires it).
    @MainActor
    static func render(event: PREvent, unit: MeasurementUnitPreference,
                       calendar: Calendar = .current) -> URL? {
        let row = PRTimelinePresenter.row(for: event, unit: unit, calendar: calendar, now: Date())
        let card = PRCard(exerciseName: row.exerciseName,
                          valueLabel: row.valueLabel,
                          detailLabel: row.deltaLabel,
                          dateLabel: row.dateLabel)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage,
              let data = uiImage.pngData() else { return nil }

        let safeName = event.exerciseName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cladiron-PR-\(safeName.isEmpty ? "lift" : safeName).png")
        do {
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
