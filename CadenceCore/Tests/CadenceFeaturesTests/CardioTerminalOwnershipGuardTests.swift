import XCTest
import Foundation

/// Architecture guard (issue #488): automatic cardio/interval pause/end is owned by durable
/// coordinators (`PhoneCardioInactivityCoordinator` via `AppModel`, and the Watch manager's
/// persisted record + armed deadline task), never only by SwiftUI `Timer.publish`,
/// `TimelineView`, or `onAppear`. UI timers may refresh display and *call* reconcile, but the
/// terminal decision and its side effects must not live in view files.
final class CardioTerminalOwnershipGuardTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    private func read(_ rel: String) throws -> String {
        try String(contentsOf: repo.appendingPathComponent(rel), encoding: .utf8)
    }
    private func swiftFiles(in rel: String, matching: (String) -> Bool) throws -> [String] {
        let dir = repo.appendingPathComponent(rel)
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") && matching($0) }.map { "\(rel)/\($0)" }
    }

    /// Symbols that decide or perform automatic terminal behavior.
    private let terminalSymbols = [
        "CardioInactivityPolicy", "PhoneCardioInactivityCoordinator", "WatchCardioInactivityTracker",
        "finalizePhoneCardio", "pauseForInactivity", "autoFinishCardioForInactivity",
        "pauseCardioForInactivity", "recordAutoPause", "recordAutoEnd"
    ]

    func testViewsDoNotOwnAutomaticTerminalBehavior() throws {
        var views = try swiftFiles(in: "Cadence/Cadence/Features/Cardio") { _ in true }
        views += try swiftFiles(in: "Cadence/Cadence Watch App Watch App") {
            ($0.hasPrefix("WatchCardio") || $0.hasPrefix("WatchInterval")) && !$0.contains("Manager")
        }
        XCTAssertFalse(views.isEmpty)
        for file in views {
            let text = try read(file)
            for sym in terminalSymbols {
                XCTAssertFalse(text.contains(sym),
                               "[guard:view-owns-terminal] \(file) references \(sym); terminal behavior belongs to a durable coordinator")
            }
        }
    }

    func testPhoneCoordinatorIsDrivenFromAppLevelHooksNotOnlyLiveViews() throws {
        let root = try read("Cadence/Cadence/App/RootTabView.swift")
        XCTAssertGreaterThanOrEqual(root.components(separatedBy: "reconcilePhoneCardio").count - 1, 2,
                                    "[guard:phone] root scene/heartbeat hooks must reconcile phone cardio")
        let model = try read("Cadence/Cadence/App/AppModel+PhoneCardio.swift")
        XCTAssertTrue(model.contains("extension AppModel: PhoneCardioLifecycleActions"))
        XCTAssertTrue(model.contains("phoneCardio.reconcile(now:"))
    }

    func testWatchManagerOwnsDurableDeadlineTaskAndHealthKitHooks() throws {
        let owner = try read("Cadence/Cadence Watch App Watch App/WatchWorkoutManager+CardioInactivity.swift")
        XCTAssertTrue(owner.contains("Task.sleep"), "[guard:watch] manager must arm its own deadline task")
        XCTAssertTrue(owner.contains("func autoFinishCardioForInactivity"))
        XCTAssertTrue(owner.contains("func restoreCardioInactivity"), "[guard:watch] relaunch recovery")
        let manager = try read("Cadence/Cadence Watch App Watch App/WatchWorkoutManager.swift")
        XCTAssertTrue(manager.contains("reconcileCardioInactivity"), "[guard:watch] HK callbacks reconcile")
        let app = try read("Cadence/Cadence Watch App Watch App/Cadence_Watch_AppApp.swift")
        XCTAssertTrue(app.contains("reconcileCardioInactivity"), "[guard:watch] app lifecycle reconciles")
    }
}
