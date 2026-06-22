import AppKit
import CoreGraphics

/// Resolves stable identifiers and names for displays.
///
/// `NSScreen` instances are ephemeral and a display's `CGDirectDisplayID` is
/// reassigned across reboots and reconnects, so neither is safe to persist a
/// per-display setting against. The display's UUID
/// (`CGDisplayCreateUUIDFromDisplayID`) *is* stable, so that's what we key on.
enum ScreenIdentity {

    /// The live (session-only) display ID for `screen`, used to talk to CoreGraphics.
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    /// A stable identifier for `screen`'s physical display, suitable as a settings
    /// key across reboots and reconnects. Prefers the display's UUID; falls back to
    /// the (session-scoped) display ID when the UUID can't be resolved, so callers
    /// always get *some* key for a connected display.
    static func persistentID(for screen: NSScreen) -> String? {
        guard let displayID = displayID(for: screen) else { return nil }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "display-\(displayID)"
    }

    /// A human-readable name for `screen` (e.g. "Built-in Retina Display").
    static func displayName(for screen: NSScreen) -> String {
        screen.localizedName
    }
}
