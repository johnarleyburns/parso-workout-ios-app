import SwiftUI
import CadenceCore
import CadenceFeatures

/// Today-home "Ready when you are" card shown when nothing is planned.

/// Cool secondary pill for cardio actions.
struct WatchCardioPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 6)
            .background(Capsule().fill(LinearGradient(colors: [WatchTone.cardio.opacity(0.55), WatchTone.cardioDeep],
                                                      startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(WatchTone.cardio.opacity(0.8), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Rest-day alternate workout chooser: exactly Strength and Cardio.

/// Two tiles in one row: plain Buttons with their own destinations, because a List row
/// with two NavigationLinks activates as one (tapping Lift opened Cardio).
