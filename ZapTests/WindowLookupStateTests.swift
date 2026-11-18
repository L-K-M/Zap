import XCTest
@testable import Zap

/// Rules for the window-list lookup of the current selection (see
/// `WindowLookupState`). The point of these tests is that ↓ starts one lookup,
/// never repeats it, and can hand the focus to a lookup that is already running.
final class WindowLookupStateTests: XCTestCase {

    // MARK: ↓ while nothing is shown

    func testDownStartsALookupWhileTheDwellIsPending() {
        var state = WindowLookupState()
        XCTAssertEqual(state.downAction(windowsShown: false, dwellPending: true, enabled: true),
                       .start)
    }

    func testDownDoesNothingWhenTheListIsAlreadyShown() {
        var state = WindowLookupState()
        XCTAssertEqual(state.downAction(windowsShown: true, dwellPending: true, enabled: true),
                       .none)
    }

    func testDownDoesNothingWhenWindowLookupsAreDisabled() {
        var state = WindowLookupState()
        XCTAssertEqual(state.downAction(windowsShown: false, dwellPending: true, enabled: false),
                       .none)
    }

    func testDownDoesNothingOnceTheDwellLookedAndFoundNothing() {
        // Regression: ↓ used to re-run the synchronous AX query on every press
        // for an app with fewer than two windows.
        var state = WindowLookupState()
        state.start(focusesFirst: false)
        XCTAssertNil(state.finish(foundWindowCount: 1))
        XCTAssertEqual(state.downAction(windowsShown: false, dwellPending: false, enabled: true),
                       .none)
    }

    func testDownAdoptsALookupThatIsAlreadyRunning() {
        // The dwell's lookup is in flight; ↓ must not start a second query, but
        // its result still has to focus the first window.
        var state = WindowLookupState()
        state.start(focusesFirst: false)
        XCTAssertEqual(state.downAction(windowsShown: false, dwellPending: false, enabled: true),
                       .adoptPending)
        state.adoptPendingForImmediateReveal()
        XCTAssertEqual(state.finish(foundWindowCount: 2), true)
    }

    func testAdoptedPendingLookupWithoutEnoughWindowsStillMarksExhausted() {
        var state = WindowLookupState()
        state.start(focusesFirst: false)
        state.adoptPendingForImmediateReveal()
        XCTAssertNil(state.finish(foundWindowCount: 1))
        XCTAssertEqual(state.exhaustedGeneration, state.generation)
    }

    // MARK: Invalidation (selection or session changed)

    func testInvalidateClearsTheExhaustedMark() {
        var state = WindowLookupState()
        state.start(focusesFirst: false)
        XCTAssertNil(state.finish(foundWindowCount: 0))
        let oldGeneration = state.generation
        state.invalidate()
        XCTAssertEqual(state.generation, oldGeneration + 1)
        XCTAssertNil(state.exhaustedGeneration)
        XCTAssertEqual(state.downAction(windowsShown: false, dwellPending: true, enabled: true),
                       .start)
    }

    func testInvalidateDropsAPendingLookupSoTheNextSelectionCanStartOne() {
        var state = WindowLookupState()
        state.start(focusesFirst: false)
        state.invalidate()
        XCTAssertFalse(state.isPending)
        state.start(focusesFirst: true)
        XCTAssertTrue(state.isPending)
        XCTAssertEqual(state.finish(foundWindowCount: 2), true)
    }

    // MARK: Finishing

    func testFinishReturnsNoFocusForTheDwell() {
        var state = WindowLookupState()
        state.start(focusesFirst: false)
        XCTAssertEqual(state.finish(foundWindowCount: 3), false)
    }

    func testFinishReturnsFocusForAnImmediateReveal() {
        var state = WindowLookupState()
        state.start(focusesFirst: true)
        XCTAssertEqual(state.finish(foundWindowCount: 2), true)
    }

    func testFinishClearsPending() {
        var state = WindowLookupState()
        state.start(focusesFirst: true)
        XCTAssertTrue(state.finish(foundWindowCount: 2) ?? false)
        XCTAssertFalse(state.isPending)
    }

    func testEnoughWindowsDoesNotMarkExhausted() {
        var state = WindowLookupState()
        state.start(focusesFirst: false)
        XCTAssertNotNil(state.finish(foundWindowCount: 2))
        XCTAssertNil(state.exhaustedGeneration)
    }
}
