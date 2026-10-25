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
    func testForwardEventRefusedByReverseThenFiresForward() throws {
        let forward = CarbonHotkey(identifier: 1)
        let reverse = CarbonHotkey(identifier: 2)
        var forwardCount = 0
        var reverseCount = 0
        let forwardFired = expectation(description: "forward hotkey callback")
        forward.onPressed = { forwardCount += 1; forwardFired.fulfill() }
        reverse.onPressed = { reverseCount += 1 }

        let event = try XCTUnwrap(makeHotkeyEvent(id: 1),
                                  "failed to create synthetic Carbon event")
        defer { ReleaseEvent(event) }

        XCTAssertEqual(reverse.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        XCTAssertEqual(forward.handleHotkeyEvent(event), noErr)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(forwardCount, 1)
        XCTAssertEqual(reverseCount, 0)
    }

    /// Symmetrically, a hotkey event addressed to `reverse` must pass through
    /// `forward` unhandled, then fire exactly `reverse`'s callback.
    func testReverseEventRefusedByForwardThenFiresReverse() throws {
        let forward = CarbonHotkey(identifier: 1)
        let reverse = CarbonHotkey(identifier: 2)
        var forwardCount = 0
        var reverseCount = 0
        let reverseFired = expectation(description: "reverse hotkey callback")
        forward.onPressed = { forwardCount += 1 }
        reverse.onPressed = { reverseCount += 1; reverseFired.fulfill() }

        let event = try XCTUnwrap(makeHotkeyEvent(id: 2),
                                  "failed to create synthetic Carbon event")
        defer { ReleaseEvent(event) }

        XCTAssertEqual(forward.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        XCTAssertEqual(reverse.handleHotkeyEvent(event), noErr)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(reverseCount, 1)
        XCTAssertEqual(forwardCount, 0)
    }

    func testUnrelatedSignatureIsNotHandled() throws {
        let hotkey = CarbonHotkey(identifier: 1)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        hotkey.onPressed = { silence.fulfill() }

        let event = try XCTUnwrap(makeHotkeyEvent(signature: 0x5445_5354, id: 1), // 'TEST'
                                  "failed to create synthetic Carbon event")
        defer { ReleaseEvent(event) }

        XCTAssertEqual(hotkey.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        waitForExpectations(timeout: 0.3)
    }

    func testUnknownIdentifierIsNotHandled() throws {
        let forward = CarbonHotkey(identifier: 1)
        let reverse = CarbonHotkey(identifier: 2)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        forward.onPressed = { silence.fulfill() }
        reverse.onPressed = { silence.fulfill() }

        let event = try XCTUnwrap(makeHotkeyEvent(id: 99),
                                  "failed to create synthetic Carbon event")
        defer { ReleaseEvent(event) }

        XCTAssertEqual(forward.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        XCTAssertEqual(reverse.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        waitForExpectations(timeout: 0.3)
    }

    func testMissingHotkeyParameterIsNotHandled() throws {
        let hotkey = CarbonHotkey(identifier: 1)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        hotkey.onPressed = { silence.fulfill() }

        let event = try XCTUnwrap(makeHotkeyEvent(id: 1, includeParameter: false),
                                  "failed to create synthetic Carbon event")
        defer { ReleaseEvent(event) }

        XCTAssertEqual(hotkey.handleHotkeyEvent(event), OSStatus(eventNotHandledErr))
        waitForExpectations(timeout: 0.3)
    }

    /// A real Carbon event whose direct object carries the wrong parameter type
    /// must be refused by `GetEventParameter` — the status check runs before any
    /// ID comparison, so malformed input can never fire a callback.
    func testWrongParameterTypeIsNotHandled() throws {
        let hotkey = CarbonHotkey(identifier: 1)
        let silence = expectation(description: "no hotkey callback")
        silence.isInverted = true
        hotkey.onPressed = { silence.fulfill() }

        var created: EventRef?
        XCTAssertEqual(CreateEvent(nil,
                                   OSType(kEventClassKeyboard),
                                   UInt32(kEventHotKeyPressed),
                                   0,
                                   0,
                                   &created), noErr)
        let event = try XCTUnwrap(created, "failed to create synthetic Carbon event")
        defer { ReleaseEvent(event) }
        var notAHotKeyID: UInt32 = 1
        XCTAssertEqual(SetEventParameter(event,
                                         EventParamName(kEventParamDirectObject),
                                         EventParamType(typeSInt32),
                                         MemoryLayout<UInt32>.size,
                                         &notAHotKeyID), noErr)

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

    /// Exercise Carbon's installed handler chain rather than only the helper.
    func testRegisteredHandlersDoNotSwallowSiblingHotkeyEvents() throws {
        let forward = CarbonHotkey(identifier: 101)
        let reverse = CarbonHotkey(identifier: 102)
        defer {
            forward.unregister()
            reverse.unregister()
        }

        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        guard forward.register(keyCode: UInt32(kVK_F19), modifiers: modifiers) else {
            XCTFail("forward hotkey registration failed")
            return
        }
        guard reverse.register(keyCode: UInt32(kVK_F20), modifiers: modifiers) else {
            XCTFail("reverse hotkey registration failed")
            return
        }

        var forwardCount = 0
        var reverseCount = 0
        let forwardFired = expectation(description: "forward hotkey callback")
        let reverseFired = expectation(description: "reverse hotkey callback")
        forward.onPressed = { forwardCount += 1; forwardFired.fulfill() }
        reverse.onPressed = { reverseCount += 1; reverseFired.fulfill() }

        let identifiers: [UInt32] = [101, 102]
        for id in identifiers {
            let event = try XCTUnwrap(makeHotkeyEvent(id: id),
                                      "failed to create synthetic Carbon event")
            defer { ReleaseEvent(event) }
            XCTAssertEqual(SendEventToEventTarget(event, GetApplicationEventTarget()), noErr)
        }

        waitForExpectations(timeout: 2)
        XCTAssertEqual(forwardCount, 1)
        XCTAssertEqual(reverseCount, 1)
    }
}
