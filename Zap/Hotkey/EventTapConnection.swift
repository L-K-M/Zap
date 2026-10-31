import CoreGraphics

/// Owns a tap and its run-loop attachment. Separate from shortcut handling so
/// lifecycle failures can be exercised without installing global keyboard hooks.
protocol EventTapConnection: AnyObject {
    var isValid: Bool { get }
    var isEnabled: Bool { get }
    var registeredEvents: CGEventMask? { get }
    func setEnabled(_ enabled: Bool)
    func invalidate()
}
