import ApplicationServices
import AppKit

/// A lightweight snapshot of one of an application's windows, paired with the
/// live Accessibility element used to raise it.
struct WindowInfo: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isMinimized: Bool
    let element: AXUIElement

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}

/// Enumerates and raises application windows via the Accessibility (AX) API.
///
/// Requires Accessibility permission — the same grant the ⌘+Tab event tap needs —
/// so callers should gate use behind `AccessibilityAuthorizer.isTrusted`.
enum WindowEnumerator {

    // MARK: Enumeration

    /// The standard, user-facing windows of the process `pid`, in AX order.
    static func windows(forPID pid: pid_t) -> [WindowInfo] {
        let app = AXUIElementCreateApplication(pid)

        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let axWindows = value as? [AXUIElement]
        else {
            return []
        }

        return axWindows.compactMap { element in
            // Keep only standard document/app windows; drop palettes, sheets, etc.
            // Require an explicit standard subrole — if the attribute is missing
            // or unreadable, treat the window as non-standard and skip it rather
            // than risk listing transient/utility windows.
            guard stringAttribute(element, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String) else {
                return nil
            }

            let title = stringAttribute(element, kAXTitleAttribute) ?? ""
            let minimized = boolAttribute(element, kAXMinimizedAttribute) ?? false
            return WindowInfo(title: title, isMinimized: minimized, element: element)
        }
    }

    // MARK: Raising

    /// Brings `window` to the front: un-minimizes it if needed, makes it the
    /// app's main window, raises it, and activates the owning application.
    static func raise(_ window: WindowInfo, pid: pid_t) {
        if window.isMinimized {
            let unminimize = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            if unminimize != .success {
                NSLog("Zap: failed to un-minimize window (AX error \(unminimize.rawValue))")
            }
        }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let raise = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        if raise != .success {
            NSLog("Zap: failed to raise window (AX error \(raise.rawValue))")
        }
        if NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps]) != true {
            NSLog("Zap: failed to activate app pid \(pid) while raising window")
        }
    }

    // MARK: Closing

    /// Closes `window` by pressing its close button. Returns `false` when the
    /// window exposes no close button (so the caller can leave it in the list).
    @discardableResult
    static func close(_ window: WindowInfo) -> Bool {
        var button: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window.element, kAXCloseButtonAttribute as CFString, &button) == .success,
            let button,
            CFGetTypeID(button) == AXUIElementGetTypeID()
        else {
            return false
        }
        let closeButton = button as! AXUIElement // safe: type checked above
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    // MARK: Attribute helpers

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == CFBooleanGetTypeID()
        else {
            return nil
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}
