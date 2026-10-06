import AppKit
import CoreGraphics

/// Queries ordering metadata only; it does not capture pixels or require
/// Screen Recording permission. Unknown is distinct from an offscreen window.
enum WindowServerVisibility {
    static func isOnscreen(_ window: NSWindow) -> Bool? {
        guard let number = CGWindowID(exactly: window.windowNumber), number != 0 else { return nil }
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, number) as? [[String: Any]]
        return isOnscreen(in: info, windowNumber: window.windowNumber)
    }

    static func isOnscreen(in info: [[String: Any]]?, windowNumber: Int) -> Bool? {
        guard let info else { return nil }
        guard let window = info.first(where: { $0[kCGWindowNumber as String] as? Int == windowNumber }) else {
            return false
        }
        // CGWindow.h explicitly defines an omitted key as not ordered onscreen.
        return window[kCGWindowIsOnscreen as String] as? Bool ?? false
    }
}
