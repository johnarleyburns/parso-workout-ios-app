import CadenceFeatures
import Foundation

/// Shared phone/Watch RGB values. Strength uses warm reds and lime/forest greens;
/// cardio uses rose, amber and mint/emerald, preserving each progress band.
public enum WeeklyActivityPalette {
    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    public static func color(_ role: WeeklySetTintRole, cardio: Bool) -> RGB {
        switch (role, cardio) {
        case (.red, false): RGB(red: 0.95, green: 0.20, blue: 0.12)
        case (.red, true): RGB(red: 0.95, green: 0.32, blue: 0.52)
        case (.yellow, false): RGB(red: 1.00, green: 0.88, blue: 0.12)
        case (.yellow, true): RGB(red: 0.96, green: 0.65, blue: 0.08)
        case (.lightGreen, false): RGB(red: 0.67, green: 0.88, blue: 0.30)
        case (.lightGreen, true): RGB(red: 0.38, green: 0.88, blue: 0.68)
        case (.green, false): RGB(red: 0.18, green: 0.58, blue: 0.16)
        case (.green, true): RGB(red: 0.04, green: 0.65, blue: 0.43)
        }
    }
}
