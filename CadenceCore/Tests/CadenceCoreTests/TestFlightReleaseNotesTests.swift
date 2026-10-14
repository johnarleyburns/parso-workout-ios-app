import XCTest
@testable import CadenceCore

final class TestFlightReleaseNotesTests: XCTestCase {
    private func notes(_ changes: [TestFlightReleaseNotes.Change], sha: String = "8ace226a1c43deadbeef")
        -> TestFlightReleaseNotes {
        .init(marketingVersion: "1.1.674", buildNumber: 674, commitSHA: sha,
              repository: "johnarleyburns/parso-workout-ios-app", changes: changes)
    }

    func testMultipleIssuesListedWithSHAAndInstructions() {
        let text = notes([
            .init(issueNumber: 58, title: "Keep Progress header unchanged", testInstruction: "Open Progress → History; header stays Progress."),
            .init(issueNumber: 51, title: "Update cardio minutes", testInstruction: "Check 150/300 minute goals.")
        ]).render()
        XCTAssertTrue(text.contains("Source: 8ace226a1c43\n"))
        XCTAssertTrue(text.contains("Cadence 1.1.674 (674)"))
        XCTAssertTrue(text.contains("- #51 — Update cardio minutes\n- #58 — Keep Progress"))
        XCTAssertTrue(text.contains("- #58: Open Progress"))
    }

    func testCIOnlyChangesAreNotGivenInventedSteps() {
        let text = notes([.init(issueNumber: 69, title: "Workflow tweak", kind: .infrastructure)]).render()
        XCTAssertTrue(text.contains("Infrastructure only (#69)"))
        XCTAssertFalse(text.contains("smoke-test"))
    }

    func testNoIssuesStatedExplicitly() {
        let text = notes([]).render()
        XCTAssertTrue(text.contains("No new GitHub issues"))
        XCTAssertFalse(text.contains("What to test"))
    }

    func testDuplicateIssuesCollapse() {
        let text = notes([.init(issueNumber: 5, title: "A"), .init(issueNumber: 5, title: "A again")]).render()
        XCTAssertEqual(text.components(separatedBy: "#5 —").count, 2)
    }

    func testLongTitlesAndLimitKeepSHAAndIssueNumbers() {
        let many = (1...300).map {
            TestFlightReleaseNotes.Change(issueNumber: $0, title: String(repeating: "x", count: 500),
                                          testInstruction: String(repeating: "y", count: 500))
        }
        let text = notes(many).render()
        XCTAssertLessThanOrEqual(text.count, TestFlightReleaseNotes.characterLimit)
        XCTAssertTrue(text.contains("Source: 8ace226a1c43"))
        XCTAssertTrue(text.contains("#1 —"))
        XCTAssertTrue(text.contains("more (see GitHub)"))
    }

    func testArchivedCommitNotLatestMainUsed() {
        let archived = notes([], sha: "AAAAAAAAAAAAAAAA")
        XCTAssertEqual(archived.shortSHA, "aaaaaaaaaaaa")
        XCTAssertEqual(archived.shortSHA.count, 12)
    }

    func testPublicationIdempotentAndScoped() {
        let n = notes([.init(issueNumber: 1, title: "T")])
        func target(build: Int = 674, version: String = "1.1.674", existing: String? = nil)
            -> TestFlightNotesPublication.Target {
            .init(appID: "app", platform: "IOS", version: version, build: build, existingNotes: existing)
        }
        func decide(_ t: TestFlightNotesPublication.Target, newest: Int = 674) -> TestFlightNotesPublication {
            .decide(target: t, expectedAppID: "app", expectedPlatform: "IOS", notes: n, newestKnownBuild: newest)
        }
        XCTAssertEqual(decide(target()), .publish)
        XCTAssertEqual(decide(target(existing: n.render())), .skipAlreadyCurrent) // retry
        // Older build still processing while a newer commit lands: only its own build is eligible.
        XCTAssertEqual(decide(target(build: 675), newest: 675), .skipWrongBuild)
        XCTAssertEqual(decide(target(), newest: 680), .publish)
        XCTAssertEqual(decide(target(version: "1.1.999")), .skipWrongBuild)
    }
}
