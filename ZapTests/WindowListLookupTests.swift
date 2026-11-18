import XCTest
@testable import Zap

/// The off-main window-list lookup (see `WindowListLookup`): enumeration must
/// not run on the main thread, a superseded result must be dropped, and one
/// selection must not trigger repeated queries.
final class WindowListLookupTests: XCTestCase {

    private func window(_ id: CGWindowID, _ title: String = "Window") -> WindowInfo {
        WindowInfo(title: title, isMinimized: false, element: nil, cgWindowID: id)
    }

    /// Spins the main run loop until `condition` holds, so main-queue completions
    /// get a chance to run.
    private func waitUntil(_ description: String, timeout: TimeInterval = 2,
                           _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Timed out waiting for \(description)")
    }

    func testEnumerationRunsOffMainAndResultArrivesOnMain() {
        let fake = FakeEnumerator()
        fake.result = [window(1), window(2)]
        let lookup = WindowListLookup(enumerate: fake.enumerate)
        let applied = expectation(description: "applied")

        lookup.start(pid: 42, includeFullScreenWindows: false, reason: .immediateReveal) { result in
            XCTAssertTrue(Thread.isMainThread, "results are applied on the main thread")
            XCTAssertEqual(result.pid, 42)
            XCTAssertEqual(result.windows.count, 2)
            XCTAssertTrue(result.focusFirst)
            applied.fulfill()
        }

        wait(for: [applied], timeout: 2)
        XCTAssertEqual(fake.calls, 1)
        XCTAssertEqual(fake.ranOffMain, [true], "AX enumeration must stay off the main thread")
    }

    func testDwellResultLeavesTheAppRowFocused() {
        let fake = FakeEnumerator()
        fake.result = [window(1), window(2)]
        let lookup = WindowListLookup(enumerate: fake.enumerate)
        let applied = expectation(description: "applied")

        lookup.start(pid: 42, includeFullScreenWindows: false, reason: .dwell) { result in
            XCTAssertFalse(result.focusFirst, "the dwell reveals the list without taking focus")
            applied.fulfill()
        }

        wait(for: [applied], timeout: 2)
        XCTAssertEqual(fake.ranOffMain, [true], "the dwell lookup must stay off the main thread")
    }

    func testSupersededLookupDoesNotDeliverItsResult() {
        let fake = FakeEnumerator()
        fake.result = [window(1), window(2)]
        let called = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        fake.onCall = { called.signal() }
        fake.release = release
        let lookup = WindowListLookup(enumerate: fake.enumerate)
        let delivered = expectation(description: "delivered")
        delivered.isInverted = true

        lookup.start(pid: 42, includeFullScreenWindows: false, reason: .dwell) { _ in
            delivered.fulfill()
        }
        XCTAssertEqual(called.wait(timeout: .now() + 2), .success)

        // The selection moved on while the AX query was blocked.
        lookup.invalidate()
        release.signal()
        wait(for: [delivered], timeout: 0.5)
    }

    func testDownAdoptsPendingLookupWithoutStartingAnother() {
        let fake = FakeEnumerator()
        fake.result = [window(1), window(2)]
        let called = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        fake.onCall = { called.signal() }
        fake.release = release
        let lookup = WindowListLookup(enumerate: fake.enumerate)
        let applied = expectation(description: "applied")

        XCTAssertTrue(lookup.start(pid: 42, includeFullScreenWindows: false, reason: .dwell) { result in
            XCTAssertTrue(result.focusFirst, "↓ adopted the dwell's in-flight lookup")
            applied.fulfill()
        })
        XCTAssertEqual(called.wait(timeout: .now() + 2), .success)

        XCTAssertEqual(lookup.downAction(windowsShown: false, dwellPending: false, enabled: true),
                       .adoptPending)
        lookup.adoptPendingForImmediateReveal()
        XCTAssertEqual(lookup.downAction(windowsShown: false, dwellPending: false, enabled: true),
                       .adoptPending)
        XCTAssertFalse(lookup.start(pid: 42, includeFullScreenWindows: false, reason: .immediateReveal) { _ in
            XCTFail("↓ must not start a second lookup while one is in flight")
        })

        release.signal()
        wait(for: [applied], timeout: 2)
        XCTAssertEqual(fake.calls, 1)
    }

    func testLookupThatFoundTooFewWindowsIsNotRepeated() {
        let fake = FakeEnumerator()
        fake.result = [window(1)]
        let returned = DispatchSemaphore(value: 0)
        fake.onReturn = { returned.signal() }
        let lookup = WindowListLookup(enumerate: fake.enumerate)
        let delivered = expectation(description: "delivered")
        delivered.isInverted = true

        XCTAssertTrue(lookup.start(pid: 42, includeFullScreenWindows: false, reason: .dwell) { _ in
            delivered.fulfill()
        })
        XCTAssertEqual(returned.wait(timeout: .now() + 2), .success)
        waitUntil("the lookup to finish") { !lookup.isPending }

        XCTAssertEqual(lookup.downAction(windowsShown: false, dwellPending: false, enabled: true),
                       .none)
        XCTAssertFalse(lookup.start(pid: 42, includeFullScreenWindows: false, reason: .immediateReveal) { _ in
            XCTFail("a lookup that found too few windows must not be repeated")
        })
        wait(for: [delivered], timeout: 0.2)
        XCTAssertEqual(fake.calls, 1)
    }

    func testInvalidateAllowsAFreshLookup() {
        let fake = FakeEnumerator()
        fake.result = [window(1), window(2)]
        let lookup = WindowListLookup(enumerate: fake.enumerate)
        let first = expectation(description: "first")
        let second = expectation(description: "second")

        lookup.start(pid: 42, includeFullScreenWindows: false, reason: .dwell) { _ in first.fulfill() }
        wait(for: [first], timeout: 2)

        lookup.invalidate()
        XCTAssertTrue(lookup.start(pid: 43, includeFullScreenWindows: false, reason: .dwell) { result in
            XCTAssertEqual(result.pid, 43)
            second.fulfill()
        })
        wait(for: [second], timeout: 2)
        XCTAssertEqual(fake.calls, 2)
    }

    /// Records the backend's calls so tests can assert threading and de-duplication.
    private final class FakeEnumerator {
        private let lock = NSLock()
        private var callCount = 0
        private var offMainChecks: [Bool] = []
        var result: [WindowInfo] = []
        var onCall: (() -> Void)?
        var onReturn: (() -> Void)?
        var release: DispatchSemaphore?

        func enumerate(pid: pid_t, includeFullScreenWindows: Bool,
                       isCancelled: @escaping () -> Bool) -> [WindowInfo] {
            lock.lock()
            callCount += 1
            lock.unlock()
            offMainChecks.append(!Thread.isMainThread)
            onCall?()
            release?.wait()
            onReturn?()
            return result
        }

        var calls: Int {
            lock.lock(); defer { lock.unlock() }
            return callCount
        }

        var ranOffMain: [Bool] {
            lock.lock(); defer { lock.unlock() }
            return offMainChecks
        }
    }
}
