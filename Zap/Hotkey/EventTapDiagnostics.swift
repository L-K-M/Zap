import CoreGraphics
import Foundation
import os

/// Shortcut metadata for diagnosing intermittent input loss. Never receives text
/// or the identities of keys other than Tab. State is owned by the main run loop;
/// only immutable log messages leave it, so logging cannot block a tap callback.
final class EventTapDiagnostics {

    struct Health: Equatable {
        let valid: Bool
        let enabled: Bool
        let intendedEnabled: Bool
        let accessibilityTrusted: Bool
        let secureInput: Bool
        let registeredEvents: CGEventMask?
    }

    private static let logger = Logger(subsystem: "ch.lkmc.Zap", category: "HotkeyDiagnostics")
    private static let logQueue = DispatchQueue(label: "ch.lkmc.Zap.hotkey-diagnostics", qos: .utility)
    private static let summaryInterval: TimeInterval = 60
    private static let heartbeatWarningInterval: TimeInterval = 5
    private static let slowCallbackInterval: TimeInterval = 0.1

    private let record: (String) -> Void
    private var tabCount: UInt64 = 0
    private var matchedTabCount: UInt64 = 0
    private var lastHealth: Health?
    private var lastCheckAt: TimeInterval?
    private var lastSummaryAt: TimeInterval?

    init(record: ((String) -> Void)? = nil) {
        self.record = record ?? { message in
            Self.logQueue.async {
                Self.logger.notice("\(message, privacy: .public)")
            }
        }
    }

    func lifecycle(_ message: String) {
        record(message)
    }

    /// Recorded before controller work so a stalled callback still leaves a
    /// receipt. Flags explain whether the opening shortcut matched without text.
    func tabReceived(flags: CGEventFlags, matchedTrigger: Bool) -> UInt64 {
        tabCount &+= 1
        if matchedTrigger { matchedTabCount &+= 1 }
        record("Tab #\(tabCount) received: flags=\(flags.rawValue) matchedTrigger=\(matchedTrigger)")
        return tabCount
    }

    func tabCompleted(sequence: UInt64, elapsed: TimeInterval) {
        guard elapsed >= Self.slowCallbackInterval else { return }
        record("Tab #\(sequence) slow callback: elapsedMs=\(Int(elapsed * 1000))")
    }

    /// A healthy idle tap has no callbacks to diagnose. Sample independently,
    /// logging transitions immediately and one summary per minute. A heartbeat
    /// gap can also mean sleep or a busy main run loop; it is not proof of a hang.
    func checkHealth(_ health: Health, now: TimeInterval) {
        let gap = lastCheckAt.map { now - $0 } ?? 0
        lastCheckAt = now
        let summaryDue = lastSummaryAt.map { now - $0 >= Self.summaryInterval } ?? true
        guard health != lastHealth || summaryDue || gap >= Self.heartbeatWarningInterval else { return }

        lastHealth = health
        lastSummaryAt = now
        record("Tap health: valid=\(health.valid) enabled=\(health.enabled) intendedEnabled=\(health.intendedEnabled) accessibilityTrusted=\(health.accessibilityTrusted) secureInput=\(health.secureInput) registeredEvents=\(health.registeredEvents.map(String.init) ?? "unknown") tabs=\(tabCount) matchedTabs=\(matchedTabCount) heartbeatGapMs=\(Int(gap * 1000))")
    }
}
