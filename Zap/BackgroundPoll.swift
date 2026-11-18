import Foundation

/// Zap's always-on status polls: input health, event-tap diagnostics and
/// Secure Input. Each runs every couple of seconds for the app's whole
/// lifetime, so each one is a wake-up an idle Mac pays for. A tolerance lets
/// macOS batch them with other timers instead of waking just for Zap.
enum BackgroundPoll {
    /// How late a 2 s poll may fire: nothing these polls report is noticed
    /// within half a second either way. Shorter polls get a quarter of their
    /// interval instead, so a fast poll isn't batched down to 2 Hz.
    static let tolerance: TimeInterval = 0.5

    /// Schedules a repeating poll on the main run loop. Common modes keep it
    /// firing while a menu is open, which is when the status menu reads it.
    static func schedule(every interval: TimeInterval,
                         _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        timer.tolerance = min(tolerance, interval / 4)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
