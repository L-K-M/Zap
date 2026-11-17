import Foundation

/// Zap's always-on status polls: input health, event-tap diagnostics and
/// Secure Input. Each runs every couple of seconds for the app's whole
/// lifetime, so each one is a wake-up an idle Mac pays for. A tolerance lets
/// macOS batch them with other timers instead of waking just for Zap.
enum BackgroundPoll {
    /// How late a poll may fire. A quarter of the 2 s polls: nothing they
    /// report is noticed within half a second either way.
    static let tolerance: TimeInterval = 0.5

    /// Schedules a repeating poll on the main run loop. Common modes keep it
    /// firing while a menu is open, which is when the status menu reads it.
    static func schedule(every interval: TimeInterval,
                         _ block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true, block: block)
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
