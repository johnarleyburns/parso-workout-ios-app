import WatchKit

enum WatchHaptics {
    static func tap() {
        WKInterfaceDevice.current().play(.click)
    }

    static func success() {
        WKInterfaceDevice.current().play(.success)
    }

    static func failure() {
        WKInterfaceDevice.current().play(.failure)
    }

    static func delete() {
        WKInterfaceDevice.current().play(.failure)
    }
}
