import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Shared warm-up / cool-down face. The phase name lives in the navigation title
/// so the time and heart rate start higher; one bottom toolbar owns pause, the
/// center phase action, and +1.
struct WatchPhaseTimerView: View {
    let title: String
    let tint: Color
    let remaining: Int
    let isPaused: Bool
    let bpm: Double?
    let centerSystemImage: String
    let centerAccessibilityLabel: Text
    let identifierPrefix: String
    let centerAccessibilityIdentifier: String
    let onPause: () -> Void
    let onCenter: () -> Void
    let onAddOneMinute: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            tint.ignoresSafeArea(.all)

            VStack(spacing: 8) {
                Text(formatTime(remaining))
                    .font(.system(size: 52, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                WatchLiveHeartRateBadge(bpm: bpm, zoneCode: zoneCode)
                Spacer()
            }
            .padding(.top, 2)
        }
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 8) {
                    Button(action: onPause) {
                        Image(systemName: WatchWarmUpControlPresentation.pauseSystemImage(isPaused: isPaused))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(isPaused ? Text("Resume") : Text("Pause"))
                    .accessibilityIdentifier("\(identifierPrefix).pause")

                    Spacer(minLength: 0)

                    Button(action: onCenter) {
                        Image(systemName: centerSystemImage)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(centerAccessibilityLabel)
                    .accessibilityIdentifier(centerAccessibilityIdentifier)

                    Spacer(minLength: 0)

                    Button(action: onAddOneMinute) {
                        Text(verbatim: WatchWarmUpControlPresentation.addOneMinuteLabel)
                            .font(.headline.weight(.bold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(Text("Add one minute"))
                    .accessibilityIdentifier("\(identifierPrefix).add")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var maxHR: Double {
        settings.cardioMaximumHROverride ?? CardioMath.defaultMaxHR(age: settings.userAge)
    }

    private var zoneCode: String? {
        WatchHeartRateZoneText.code(bpm: bpm, maxHR: maxHR)
    }

    private func formatTime(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
