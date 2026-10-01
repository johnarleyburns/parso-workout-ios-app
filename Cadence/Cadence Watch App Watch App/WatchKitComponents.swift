import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

// Watch redesign (plans/watch-redesign/2026-09-30/DESIGN.md §3): the Cladiron watch kit — the same
// component vocabulary as the Platterhead/Voxglass Watch Listening Kit, tuned for training.

enum WatchTone {
    /// Cladiron AccentColor (dark) `#3DDC83`.
    static let accent = Color(red: 0x3D / 255, green: 0xDC / 255, blue: 0x83 / 255)
    static let accentInk = Color(red: 0x04 / 255, green: 0x14 / 255, blue: 0x0B / 255)
    static let accentSoft = Color(red: 0x0F / 255, green: 0x2E / 255, blue: 0x1D / 255)
    /// `CadenceTheme.achievement` — PRs only.
    static let gold = Color(red: 0.95, green: 0.66, blue: 0.23)
    static let heart = Color(red: 0xFF / 255, green: 0x4F / 255, blue: 0x5E / 255)
    static let attention = Color.orange
    static let surface = Color(red: 0x1C / 255, green: 0x1F / 255, blue: 0x24 / 255)
    static let surfaceRaised = Color(red: 0x2A / 255, green: 0x2E / 255, blue: 0x35 / 255)
}

/// §3 `MetricField`: one big number with its unit; outlined while it owns the Crown.
struct WatchMetricField: View {
    let value: String
    let unit: String
    let isFocused: Bool
    let accessibilityName: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFocused ? WatchTone.accentSoft : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? WatchTone.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(Text("\(value) \(unit)"))
        .accessibilityHint(isFocused ? Text("Turn the Digital Crown to adjust") : Text("Double-tap to adjust with the Digital Crown"))
    }
}

/// §3 `ActionPill`: a 46 pt (primary) or 34 pt (small) capsule button.
struct WatchPillStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, light }
    var kind: Kind = .primary
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((small ? Font.footnote : Font.headline).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: small ? 34 : 46)
            .padding(.horizontal, 6)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: WatchTone.accentInk
        case .secondary: .primary
        case .destructive: .red
        case .light: .black
        }
    }

    private var background: Color {
        switch kind {
        case .primary: WatchTone.accent
        case .secondary: WatchTone.surfaceRaised
        case .destructive: Color.red.opacity(0.18)
        case .light: .white
        }
    }
}

/// §3 `CitationChip`: "ⓘ The science ›" → the citation card. Never a raw id (HARD RULE).
struct WatchCoachLineView: View {
    let line: WatchCoachLine
    @State private var showingCitation = false

    var body: some View {
        VStack(spacing: 2) {
            Text(line.text)
                .font(.caption2)
                .foregroundStyle(WatchTone.accent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !citations.isEmpty {
                Button { showingCitation = true } label: {
                    Label("The science", systemImage: "info.circle").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(WatchTone.accent)
                .accessibilityIdentifier("watch.coach.science")
            }
        }
        .sheet(isPresented: $showingCitation) {
            NavigationStack { WatchCitationCard(claim: line.text, citations: citations) }
        }
    }

    private var citations: [Citation] { line.citationIDs.compactMap(CitationRegistry.citation(forId:)) }
}

/// §5 C3: the claim, then each source's authors, year and title; full reading hands off to iPhone.
struct WatchCitationCard: View {
    let claim: String
    let citations: [Citation]

    var body: some View {
        List {
            Text(claim).font(.footnote).listRowBackground(Color.clear)
            ForEach(citations) { citation in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "\(citation.authors) · \(citation.year)").font(.caption2.weight(.semibold))
                    Text(citation.title).font(.caption2).foregroundStyle(.secondary)
                    Text(citation.source).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .userActivity("guru.parso.cladiron.citation") { activity in
                    activity.isEligibleForHandoff = true
                    activity.webpageURL = URL(string: citation.url)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Open on iPhone from the App Switcher to read the paper.")
                .font(.caption2).foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        .navigationTitle("The science")
    }
}

/// §3 `ReceiptRow`: a destination and its real state.
struct WatchReceiptRow: View {
    let title: LocalizedStringKey
    let state: WatchSaveReceipt.State

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.semibold))
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(WatchTone.accent)
        case .inProgress: ProgressView()
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(WatchTone.attention)
        }
    }

    private var detail: String? {
        switch state {
        case .done: nil
        case .inProgress(let text), .waiting(let text), .failed(let text): text
        }
    }
}

/// Progress dots for the Set Card (done / current / upcoming).
struct WatchSetDots: View {
    let dots: [WatchSetDot]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                Circle()
                    .fill(color(dot))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Set \((dots.firstIndex(of: .current) ?? 0) + 1) of \(dots.count)"))
    }

    private func color(_ dot: WatchSetDot) -> Color {
        switch dot {
        case .done: WatchTone.accent
        case .current: .white
        case .upcoming: Color.white.opacity(0.25)
        }
    }
}
