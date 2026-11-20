import Foundation

/// The post-merge `iOS Build & TestFlight` core-tests job sets
/// `CADENCE_RELEASE_CI=1`. PR validation runs the full suite without it.
///
/// This flag exists only to quarantine tests that still block on synchronous
/// I/O or thread primitives under the release runner's heavy concurrent load.
/// Each quarantine must carry a tracking note and be replaced with an async or
/// mocked seam; it is not a permanent exclusion.
enum ReleaseCITestSupport {
    static var isReleaseCI: Bool {
        ProcessInfo.processInfo.environment["CADENCE_RELEASE_CI"] == "1"
    }
}
