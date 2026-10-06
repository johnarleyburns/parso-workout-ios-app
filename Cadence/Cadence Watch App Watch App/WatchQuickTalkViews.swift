import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 V1–V7 — Quick Talk states, shown over the Set Card / Rest while talking.
struct WatchQuickTalkOverlay: View {
    let talk: WatchQuickTalkController
    let unit: MeasurementUnitPreference
    @State private var ticked: Set<Int> = []

    var body: some View {
        switch talk.phase {
        case .idle:
            EmptyView()
        case .needsPermission:
            panel {
                Image(systemName: "mic.fill").font(.title2).foregroundStyle(WatchTone.accent)
                Text("Log sets by speaking").font(.headline).multilineTextAlignment(.center)
                Text("Hold Log set and say “100 kilos for 5”. Listens only while you hold. Your iPhone turns it into text, then the recording is deleted.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Allow Microphone") { talk.requestPermission() }
                    .buttonStyle(WatchPillStyle(kind: .primary, small: true))
                    .accessibilityIdentifier("watchTalk.allowMic")
                Button("Not now") { talk.dismiss() }.font(.caption2).buttonStyle(.plain)
            }
        case .listening(let startedAt):
            panel {
                chip(String(localized: "Listening"), color: WatchTone.heart)
                waveform
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(verbatim: "\(Int(context.date.timeIntervalSince(startedAt)))s / \(Int(WatchQuickTalkPlanner.maximumRecording))s")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text("Release to log").font(.headline)
                Text("Slide away to cancel").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("watchTalk.listening")
        case .transcribing(let source):
            panel {
                chip(source == .iPhone ? String(localized: "Transcribing on iPhone…")
                                       : String(localized: "Reading dictation…"),
                     color: WatchTone.attention)
                ProgressView()
                Button("Cancel") { talk.dismiss() }.buttonStyle(WatchPillStyle(kind: .secondary, small: true))
            }
            .accessibilityIdentifier("watchTalk.transcribing")
        case .saved(let summary, let undoUntil):
            panel {
                Image(systemName: "checkmark").font(.title2).foregroundStyle(WatchTone.accent)
                Text(summary).font(.headline).multilineTextAlignment(.center)
                Text("Logged by voice").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button("Undo") { talk.undo() }
                        .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                        .accessibilityIdentifier("watchTalk.undo")
                    Button("Done") { talk.dismiss() }
                        .buttonStyle(WatchPillStyle(kind: .light, small: true))
                        .handGestureShortcut(.primaryAction)
                }
            }
            .task(id: summary) {
                let wait = max(0, undoUntil.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(wait))
                if case .saved = talk.phase { talk.dismiss() }
            }
            .accessibilityIdentifier("watchTalk.saved")
        case .review(let heard, let items):
            ScrollView {
                VStack(spacing: 6) {
                    Text("Heard “\(heard)”").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ForEach(items) { item in
                        Button { toggle(item.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(.footnote.weight(.semibold))
                                    if let note = item.note {
                                        Text(note).font(.caption2).foregroundStyle(WatchTone.gold)
                                    }
                                }
                                Spacer()
                                Image(systemName: ticked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(WatchTone.accent)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(WatchTone.surface))
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(ticked.contains(item.id) ? Text("Selected") : Text("Not selected"))
                    }
                    Button {
                        talk.confirm(items.filter { ticked.contains($0.id) })
                    } label: {
                        if items.count > 1 { Text("Do These") } else { Text("Log") }
                    }
                    .buttonStyle(WatchPillStyle(kind: .primary, small: true))
                    .disabled(ticked.isEmpty)
                    .handGestureShortcut(.primaryAction)
                    .accessibilityIdentifier("watchTalk.confirm")
                    Button("Cancel") { talk.dismiss() }.font(.caption2).buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
            .background(Color.black)
            .onAppear { ticked = Set(items.map(\.id)) }
            .accessibilityIdentifier("watchTalk.review")
        case .notUnderstood(let heard, let clarification):
            panel {
                Text("Didn't catch that").font(.headline)
                Text("Heard “\(heard)”").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let clarification { Text(clarification).font(.caption2).multilineTextAlignment(.center) }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(WatchQuickTalkPlanner.examples(unit: unit), id: \.self) { Text($0).font(.caption2) }
                }
                Button("Try Again") { talk.dismiss(); talk.startListening() }
                    .buttonStyle(WatchPillStyle(kind: .light, small: true))
                Button("Close") { talk.dismiss() }.font(.caption2).buttonStyle(.plain)
            }
            .accessibilityIdentifier("watchTalk.notUnderstood")
        case .failed(let code):
            panel {
                Image(systemName: code == "iPhoneNotNearby" ? "iphone.slash" : "exclamationmark.triangle")
                    .font(.title3).foregroundStyle(WatchTone.attention)
                Text(failureTitle(code)).font(.headline).multilineTextAlignment(.center)
                Text(failureMessage(code)).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(code).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                if code == "phoneReplyTimedOut" || code.hasPrefix("wc-") {
                    Button("Try Again") { talk.dismiss(); talk.startListening() }
                        .buttonStyle(WatchPillStyle(kind: .light, small: true))
                }
                Button("OK") { talk.dismiss() }.buttonStyle(WatchPillStyle(kind: .secondary, small: true))
            }
            .accessibilityIdentifier("watchTalk.failed")
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 6, content: content)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.94))
            .accessibilityElement(children: .contain)
    }

    private func chip(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                Capsule().fill(WatchTone.accent)
                    .frame(width: 4, height: 6 + CGFloat(talk.level) * CGFloat([18, 26, 32, 22, 30, 16, 24][index]))
            }
        }
        .frame(height: 36)
        .animation(.easeOut(duration: 0.1), value: talk.level)
        .accessibilityHidden(true)
    }

    private func toggle(_ id: Int) {
        if ticked.contains(id) { ticked.remove(id) } else { ticked.insert(id) }
    }

    private func failureTitle(_ code: String) -> LocalizedStringKey {
        switch code {
        case "iPhoneNotNearby": "iPhone not nearby"
        case "micDenied": "Microphone is off"
        case "speechAssetsMissing": "Set up Quick Talk on iPhone"
        case "phoneReplyTimedOut": "iPhone did not respond"
        default: "Couldn't log by voice"
        }
    }

    private func failureMessage(_ code: String) -> LocalizedStringKey {
        switch code {
        case "iPhoneNotNearby": "Voice is turned into text on your iPhone. Use Dictate in ⋯ instead."
        case "micDenied": "Allow the microphone for Cladiron in the Watch app on iPhone."
        case "speechAssetsMissing": "Open Cladiron on iPhone and use Quick Talk once to download the speech model."
        case "phoneReplyTimedOut": "Keep Cladiron open on iPhone and try again. You can also use Dictate in ⋯."
        default: "Nothing was logged. Try again, or log with the buttons."
        }
    }
}
