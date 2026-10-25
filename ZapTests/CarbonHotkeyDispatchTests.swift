import Carbon.HIToolbox
import XCTest
@testable import Zap

/// Tests `CarbonHotkey.handleHotkeyEvent(_:)` with real synthetic Carbon events.
/// Several handlers can share the application event target, so a handler must
/// refuse events that are not its own instead of consuming them. No global
/// hotkeys are registered; dispatch is exercised directly on the seam.
final class CarbonHotkeyDispatchTests: XCTestCase {

    /// Four-char signature `'ZAPH'` — the literal wire value, kept independent of
    /// the implementation's own constant.
    private static let signature: OSType = 0x5A41_5048

    /// Builds a synthetic `kEventHotKeyPressed` event carrying an
    /// `EventHotKeyID` parameter, or one with the parameter omitted.
    private func makeHotkeyEvent(signature: OSType = CarbonHotkeyDispatchTests.signature,
                                 id: UInt32,
                                 includeParameter: Bool = true) -> EventRef? {
        var event: EventRef?
        guard CreateEvent(nil,
                          OSType(kEventClassKeyboard),
                          UInt32(kEventHotKeyPressed),
                          0,
                          0,
                          &event) == noErr,
              let event else { return nil }

        guard includeParameter else { return event }
        var pressedID = EventHotKeyID(signature: signature, id: id)
        guard SetEventParameter(event,
                                EventParamName(kEventParamDirectObject),
                                EventParamType(typeEventHotKeyID),
                                MemoryLayout<EventHotKeyID>.size,
                                &pressedID) == noErr else {
            ReleaseEvent(event)
            return nil
        }
        return event
    }

    /// A hotkey event addressed to `forward` must pass through `reverse` unhandled,
    /// then fire exactly `forward`'s callback.
    func testForwardEventRefusedByReverseThenFiresForward() {
        let forward = CarbonHotkey(identifier: 1)
        let reverse = CarbonHotkey(identifier: 2)
        var forwardCount = 0
        var reverseCount = 0
        let forwardFired = expectation(description: "forward hotkey callback")
        forward.onPressed = { forwardCount += 1; forwardFired.fulfill() }
        reverse.onPressed = { reverseCount += 1 }

        let event = makeHotkeyEvent(id: 1)!
        defer { ReleaseEvent(event) }

        XCTAssertEqual(reverse.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        XCTAssertEqual(forward.handleHotkeyEvent(event), noErr)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(forwardCount, 1)
        XCTAssertEqual(reverseCount, 0)
    }

    /// Symmetrically, a hotkey event addressed to `reverse` must pass through
    /// `forward` unhandled, then fire exactly `reverse`'s callback.
    func testReverseEventRefusedByForwardThenFiresReverse() {
        let forward = CarbonHotkey(identifier: 1)
        let reverse = CarbonHotkey(identifier: 2)
        var forwardCount = 0
        var reverseCount = 0
        let reverseFired = expectation(description: "reverse hotkey callback")
        forward.onPressed = { forwardCount += 1 }
        reverse.onPressed = { reverseCount += 1; reverseFired.fulfill() }

        let event = makeHotkeyEvent(id: 2)!
        defer { ReleaseEvent(event) }

        XCTAssertEqual(forward.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        XCTAssertEqual(reverse.handleHotkeyEvent(event), noErr)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(reverseCount, 1)
        XCTAssertEqual(forwardCount, 0)
    }

    func testUnrelatedSignatureIsNotHandled() {
        let hotkey = CarbonHotkey(identifier: 1)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        hotkey.onPressed = { silence.fulfill() }

        let event = makeHotkeyEvent(signature: 0x5445_5354, id: 1)! // 'TEST'
        defer { ReleaseEvent(event) }

        XCTAssertEqual(hotkey.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        waitForExpectations(timeout: 0.3)
    }

    func testUnknownIdentifierIsNotHandled() {
        let forward = CarbonHotkey(identifier: 1)
        let reverse = CarbonHotkey(identifier: 2)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        forward.onPressed = { silence.fulfill() }
        reverse.onPressed = { silence.fulfill() }

        let event = makeHotkeyEvent(id: 99)!
        defer { ReleaseEvent(event) }

        XCTAssertEqual(forward.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        XCTAssertEqual(reverse.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        waitForExpectations(timeout: 0.3)
    }

    func testMissingHotkeyParameterIsNotHandled() {
        let hotkey = CarbonHotkey(identifier: 1)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        hotkey.onPressed = { silence.fulfill() }

        let event = makeHotkeyEvent(id: 1, includeParameter: false)!
        defer { ReleaseEvent(event) }

        XCTAssertEqual(hotkey.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        waitForExpectations(timeout: 0.3)
    }

    /// A real Carbon event whose direct object carries the wrong parameter type
    /// must be refused by `GetEventParameter` — the status check runs before any
    /// ID comparison, so malformed input can never fire a callback.
    func testWrongParameterTypeIsNotHandled() {
        let hotkey = CarbonHotkey(identifier: 1)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        hotkey.onPressed = { silence.fulfill() }

        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil,
                                   OSType(kEventClassKeyboard),
                                   UInt32(kEventHotKeyPressed),
                                   0,
                                   0,
                                   &event), noErr)
        var notAHotKeyID: UInt32 = 1
        XCTAssertEqual(SetEventParameter(event!,
                                         EventParamName(kEventParamDirectObject),
                                         EventParamType(typeSInt32),
                                         MemoryLayout<UInt32>.size,
                                         &notAHotKeyID), noErr)
        defer { ReleaseEvent(event!) }

        XCTAssertEqual(hotkey.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        waitForExpectations(timeout: 0.3)
    }

    func testNilEventIsNotHandled() {
        let hotkey = CarbonHotkey(identifier: 1)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        hotkey.onPressed = { silence.fulfill() }

        XCTAssertEqual(hotkey.handleHotkeyEvent(nil), OSStatus(eventNotHandledErr))
        waitForExpectations(timeout: 0.3)
    }
}
