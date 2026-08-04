import Foundation
import XCTest
@testable import Zap

/// The ceiling on concurrent SVG renders (`SVGRenderGate`).
///
/// Worth its own tests because the failure mode is a hang: get the hand-off wrong
/// and a waiter is never resumed, which in the app looks like an icon that renders
/// forever. Everything here would time out rather than fail if that happened, which
/// is the signal.
final class SVGRenderGateTests: XCTestCase {

    func testASlotIsTakenImmediatelyWhenOneIsFree() async {
        let gate = SVGRenderGate(limit: 2)
        await gate.acquire()
        await gate.acquire()
        let active = await gate.activeCount
        XCTAssertEqual(active, 2)
    }

    func testReleasingFreesTheSlot() async {
        let gate = SVGRenderGate(limit: 1)
        await gate.acquire()
        await gate.release()
        XCTAssertEqual(await gate.activeCount, 0)

        // And the freed slot is usable rather than merely counted.
        await gate.acquire()
        XCTAssertEqual(await gate.activeCount, 1)
    }

    func testReleasingMoreThanWasTakenDoesNotGoNegative() async {
        let gate = SVGRenderGate(limit: 1)
        await gate.release()
        XCTAssertEqual(await gate.activeCount, 0)
    }

    func testALimitBelowOneIsStillOne() async {
        let gate = SVGRenderGate(limit: 0)
        XCTAssertEqual(gate.limit, 1)
    }

    /// The point of the thing: many callers, never more than `limit` inside at once,
    /// and every one of them gets through.
    func testConcurrentCallersNeverExceedTheLimitAndAllComplete() async {
        let gate = SVGRenderGate(limit: 2)
        let counter = ConcurrencyCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await gate.acquire()
                    await counter.enter()
                    // Long enough that overlapping callers really are overlapping.
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    await counter.leave()
                    await gate.release()
                }
            }
        }

        XCTAssertEqual(await counter.completed, 20)
        XCTAssertLessThanOrEqual(await counter.peak, 2)
        // Every slot handed back, so the gate is reusable afterwards.
        XCTAssertEqual(await gate.activeCount, 0)
    }

    /// A waiter must be resumed by whoever leaves, not left for the next arrival to
    /// step over. With `limit` 1 this is the whole hand-off in one line.
    func testAWaiterIsResumedWhenTheHolderLeaves() async {
        let gate = SVGRenderGate(limit: 1)
        await gate.acquire()

        let waiter = Task {
            await gate.acquire()
            return true
        }
        // Give the waiter a chance to actually suspend inside the gate.
        try? await Task.sleep(nanoseconds: 5_000_000)
        await gate.release()

        let resumed = await waiter.value
        XCTAssertTrue(resumed)
        await gate.release()
        XCTAssertEqual(await gate.activeCount, 0)
    }
}

/// Tracks how many callers are inside the gate at once.
private actor ConcurrencyCounter {
    private(set) var peak = 0
    private(set) var completed = 0
    private var current = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
        completed += 1
    }
}
