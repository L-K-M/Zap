import XCTest
@testable import Zap

/// Tests the pure identity check behind `AppListProvider.runningApplication(for:)`,
/// which resolves a snapshot back to the live process by pid alone and must refuse
/// any candidate that is not the very same process.
final class RunningApplicationResolutionTests: XCTestCase {

    private func app(pid: pid_t = 42,
                     bundleID: String = "com.example.app",
                     bundleURL: URL? = URL(fileURLWithPath: "/Applications/Example.app")) -> AppInfo {
        AppInfo(bundleIdentifier: bundleID, name: bundleID,
                processIdentifier: pid, bundleURL: bundleURL)
    }

    private func matches(_ info: AppInfo, pid: pid_t,
                         bundleID: String? = "com.example.app",
                         bundleURL: URL? = URL(fileURLWithPath: "/Applications/Example.app"),
                         isTerminated: Bool = false) -> Bool {
        AppListProvider.matchesSnapshot(info,
                                        processIdentifier: pid,
                                        bundleIdentifier: bundleID,
                                        bundleURL: bundleURL,
                                        isTerminated: isTerminated)
    }

    func testExactMatchIsAccepted() {
        XCTAssertTrue(matches(app(), pid: 42))
    }

    func testMismatchedBundleIdentifierIsRejected() {
        XCTAssertFalse(matches(app(), pid: 42, bundleID: "com.example.other"))
    }

    func testMissingBundleIdentifierIsRejected() {
        XCTAssertFalse(matches(app(), pid: 42, bundleID: nil))
    }

    func testSameIdentityButDifferentPIDIsRejected() {
        XCTAssertFalse(matches(app(), pid: 43))
    }

    func testSamePIDAndBundleIdentifierButDifferentPathIsRejected() {
        let otherPath = URL(fileURLWithPath: "/Applications/Other/Example.app")
        XCTAssertFalse(matches(app(), pid: 42, bundleURL: otherPath))
    }

    func testMissingLiveURLIsRejectedWhenSnapshotHasOne() {
        XCTAssertFalse(matches(app(), pid: 42, bundleURL: nil))
    }

    func testStandardizedEquivalentPathIsAccepted() {
        let equivalent = URL(fileURLWithPath: "/Applications/../Applications/Example.app")
        XCTAssertTrue(matches(app(), pid: 42, bundleURL: equivalent))
    }

    func testTerminatedCandidateIsRejected() {
        XCTAssertFalse(matches(app(), pid: 42, isTerminated: true))
    }

    func testSnapshotWithoutURLAcceptsMatchingPIDAndBundleIdentifier() {
        let info = app(bundleURL: nil)
        XCTAssertTrue(matches(info, pid: 42, bundleURL: nil))
        XCTAssertTrue(matches(info, pid: 42, bundleURL: URL(fileURLWithPath: "/anywhere/Example.app")))
    }

    func testNonPositivePIDIsRejected() {
        XCTAssertFalse(matches(app(), pid: 0))
        XCTAssertFalse(matches(app(), pid: -1))
    }
}
