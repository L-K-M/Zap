import CoreGraphics
import XCTest
@testable import Zap

final class EventTapDiagnosticsTests: XCTestCase {

    private func health(enabled: Bool = true, intendedEnabled: Bool = true,
                        trusted: Bool = true, secureInput: Bool = false) -> EventTapDiagnostics.Health {
        .init(valid: true, enabled: enabled, intendedEnabled: intendedEnabled,
              accessibilityTrusted: trusted, secureInput: secureInput)
    }

    func testUnchangedHealthIsSummarizedOncePerMinute() {
        var messages: [String] = []
        let diagnostics = EventTapDiagnostics(record: { messages.append($0) })

        for second in stride(from: 0, through: 58, by: 2) {
            diagnostics.checkHealth(health(), now: Double(second))
        }
        XCTAssertEqual(messages.count, 1)

        diagnostics.checkHealth(health(), now: 60)
        XCTAssertEqual(messages.count, 2)
    }

    func testSilentDisableIsReportedWithoutAnInputCallback() {
        var messages: [String] = []
        let diagnostics = EventTapDiagnostics(record: { messages.append($0) })
        diagnostics.checkHealth(health(), now: 0)

        diagnostics.checkHealth(health(enabled: false), now: 2)

        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[1].contains("enabled=false intendedEnabled=true"))
    }

    func testIntentionalDisableAndSystemConditionsAreDistinguishable() {
        var messages: [String] = []
        let diagnostics = EventTapDiagnostics(record: { messages.append($0) })
        diagnostics.checkHealth(health(), now: 0)
        diagnostics.checkHealth(health(enabled: false, intendedEnabled: false), now: 2)
        diagnostics.checkHealth(health(trusted: false), now: 4)
        diagnostics.checkHealth(health(secureInput: true), now: 6)

        XCTAssertEqual(messages.count, 4)
        XCTAssertTrue(messages[1].contains("enabled=false intendedEnabled=false"))
        XCTAssertTrue(messages[2].contains("accessibilityTrusted=false"))
        XCTAssertTrue(messages[3].contains("secureInput=true"))
    }

    func testHeartbeatGapIsReportedBeforeNextSummary() {
        var messages: [String] = []
        let diagnostics = EventTapDiagnostics(record: { messages.append($0) })
        diagnostics.checkHealth(health(), now: 10)
        diagnostics.checkHealth(health(), now: 12)
        diagnostics.checkHealth(health(), now: 18)

        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[1].contains("heartbeatGapMs=6000"))
    }

    func testTabReceiptPrecedesCompletionAndCountsRejectedTabs() {
        var messages: [String] = []
        let diagnostics = EventTapDiagnostics(record: { messages.append($0) })
        let accepted = diagnostics.tabReceived(flags: .maskCommand, matchedTrigger: true)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("Tab #1 received:"))
        XCTAssertTrue(messages[0].contains("matchedTrigger=true"))

        let flags: CGEventFlags = [.maskCommand, .maskAlternate]
        let rejected = diagnostics.tabReceived(flags: flags, matchedTrigger: false)
        XCTAssertEqual(rejected, accepted + 1)
        XCTAssertTrue(messages[1].contains("flags=\(flags.rawValue) matchedTrigger=false"))

        diagnostics.tabCompleted(sequence: accepted, elapsed: 0.15)
        XCTAssertTrue(messages[2].contains("Tab #1 slow callback: elapsedMs=150"))

        diagnostics.checkHealth(health(), now: 0)
        XCTAssertTrue(messages[3].contains("tabs=2 matchedTabs=1"))
    }

    func testFastTabCompletionDoesNotAddLogTraffic() {
        var messages: [String] = []
        let diagnostics = EventTapDiagnostics(record: { messages.append($0) })
        let sequence = diagnostics.tabReceived(flags: .maskCommand, matchedTrigger: true)
        diagnostics.tabCompleted(sequence: sequence, elapsed: 0.01)
        XCTAssertEqual(messages.count, 1)
    }
}
