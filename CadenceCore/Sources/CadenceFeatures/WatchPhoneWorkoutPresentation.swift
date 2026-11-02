import Foundation

public enum WatchPhoneWorkoutPresentation {
    public static func shouldShow(isActive: Bool, phoneRequestID: String?) -> Bool {
        isActive && phoneRequestID != nil
    }
}
