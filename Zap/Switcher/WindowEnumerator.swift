import ApplicationServices
import AppKit
import CoreGraphics

/// Private Accessibility SPI that yields the `CGWindowID` backing an AX window
/// element. There is no public way to bridge an `AXUIElement` to the window ID
/// that screen-capture APIs require, so we rely on this long-standing symbol.
///
/// Notes:
/// - Fine for Developer ID + notarization (notarization checks signing/malware,
///   not API surface), but would block an App Store submission.
/// - Treated as best-effort: callers must tolerate a `nil` window ID, so a future
///   OS change that removes the symbol degrades to "no preview", not a crash.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A lightweight snapshot of one of an application's windows, paired with the
/// live Accessibility element used to raise it.
struct WindowInfo: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isMinimized: Bool
    /// The live AX element used to raise and close the window. `nil` for a window
    /// found only via the Quartz window list — e.g. a full-screen window on another
    /// Space, which `AXWindows` omits — which can be listed but only brought forward
    /// by activating its app.
    let element: AXUIElement?
    /// The Quartz window ID, used to capture a preview. `nil` when the SPI is
    /// unavailable, so previews are best-effort and never required.
    let cgWindowID: CGWindowID?

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}

/// Enumerates and raises application windows via the Accessibility (AX) API.
///
/// Requires Accessibility permission — the same grant the ⌘+Tab event tap needs —
/// so callers should gate use behind `AccessibilityAuthorizer.isTrusted`.
enum WindowEnumerator {

    private static let finderBundleID = "com.apple.finder"

    // MARK: Enumeration

    /// The standard, user-facing windows of the process `pid`, in AX order. When
    /// `includeFullScreenWindows` is on, also lists full-screen windows on other
    /// Spaces that the Accessibility API omits.
    static func windows(forPID pid: pid_t, includeFullScreenWindows: Bool = false) -> [WindowInfo] {
        let app = AXUIElementCreateApplication(pid)
        let isFinder = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == finderBundleID

        var axWindows = windowInfos(from: elementsAttribute(app, kAXWindowsAttribute), allowFinderFallback: isFinder)
        if isFinder, axWindows.count < 2 {
            // Finder is a special case: depending on macOS/Finder state, browser
            // windows can be omitted from AXWindows or lack the standard subrole.
            // AXChildren often still exposes the same live window elements, so merge
            // it only as a Finder fallback and keep the normal stricter path for apps.
            let fallback = windowInfos(from: elementsAttribute(app, kAXChildrenAttribute), allowFinderFallback: true)
            axWindows = unique(axWindows + fallback)
        }

        guard includeFullScreenWindows else { return axWindows }

        // `AXWindows` only reports windows on the active Space, so full-screen windows
        // (each on their own Space) and windows on other desktops go missing. Backfill
        // them from the Quartz window list, which spans every Space, keyed by
        // CGWindowID so a window AX already returned is never duplicated.
        let known = Set(axWindows.compactMap(\.cgWindowID))
        let offSpace = offSpaceWindows(pid: pid).filter { window in
            window.cgWindowID.map { !known.contains($0) } ?? false
        }
        return unique(axWindows + offSpace)
    }

    private static func windowInfos(from elements: [AXUIElement], allowFinderFallback: Bool) -> [WindowInfo] {
        elements.compactMap { element in
            guard stringAttribute(element, kAXRoleAttribute) == (kAXWindowRole as String) else { return nil }
            let cgWindowID = windowID(of: element)
            guard isUserFacingWindow(element, allowFinderFallback: allowFinderFallback) else { return nil }
            let title = stringAttribute(element, kAXTitleAttribute) ?? ""
            let minimized = boolAttribute(element, kAXMinimizedAttribute) ?? false
            return WindowInfo(title: title, isMinimized: minimized, element: element,
                              cgWindowID: cgWindowID)
        }
    }

    private static func isUserFacingWindow(_ element: AXUIElement, allowFinderFallback: Bool) -> Bool {
        let subrole = stringAttribute(element, kAXSubroleAttribute)
        if subrole == (kAXStandardWindowSubrole as String) { return true }

        guard allowFinderFallback else { return false }
        if let subrole, isTransientSubrole(subrole) { return false }
        return hasWindowChrome(element)
    }

    private static func isTransientSubrole(_ subrole: String) -> Bool {
        subrole == (kAXDialogSubrole as String)
            || subrole == (kAXSystemDialogSubrole as String)
            || subrole == (kAXFloatingWindowSubrole as String)
    }

    private static func hasWindowChrome(_ element: AXUIElement) -> Bool {
        hasElementAttribute(element, kAXCloseButtonAttribute)
            || hasElementAttribute(element, kAXMinimizeButtonAttribute)
            || hasElementAttribute(element, kAXZoomButtonAttribute)
    }

    private static func hasElementAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value
        else {
            return false
        }
        return CFGetTypeID(value) == AXUIElementGetTypeID()
    }

    private static func elementsAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let elements = value as? [AXUIElement]
        else {
            return []
        }
        return elements
    }

    private static func unique(_ windows: [WindowInfo]) -> [WindowInfo] {
        var seenWindowIDs = Set<CGWindowID>()
        var seenElements = Set<CFHashCode>()
        return windows.filter { window in
            if let id = window.cgWindowID {
                return seenWindowIDs.insert(id).inserted
            }
            if let element = window.element {
                return seenElements.insert(CFHash(element)).inserted
            }
            return true
        }
    }

    /// Resolves the `CGWindowID` for an AX window element via the private SPI,
    /// returning `nil` on failure so previews stay strictly optional.
    private static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id = CGWindowID(0)
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    // MARK: Off-Space windows (Quartz fallback)

    /// `pid`'s document windows that aren't on the active Space — chiefly full-screen
    /// windows, each on its own desktop, which `AXWindows` doesn't report. Sourced
    /// from the Quartz window list (which spans all Spaces). These carry no AX element.
    private static func offSpaceWindows(pid: pid_t) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { offSpaceWindowInfo(from: $0, pid: pid) }
    }

    /// Builds a `WindowInfo` from one Quartz window-list entry when it's an off-Space
    /// document window of `pid`, or `nil` otherwise (wrong process, on the current
    /// Space, a non-window layer, or too small to be a real window). Pure for testing.
    static func offSpaceWindowInfo(from info: [String: Any], pid: pid_t) -> WindowInfo? {
        guard
            (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
            (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,           // normal window layer
            (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue != true,  // not on the current Space
            isDocumentSized(info),
            let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        else { return nil }
        // `kCGWindowName` is only populated with Screen Recording permission, so the
        // title may be empty for these — the row still appears (and gets a preview if
        // that permission is granted).
        let title = info[kCGWindowName as String] as? String ?? ""
        return WindowInfo(title: title, isMinimized: false, element: nil, cgWindowID: number)
    }

    /// Whether a Quartz window entry is a visible, real-sized window rather than a
    /// transparent or tiny helper surface.
    private static func isDocumentSized(_ info: [String: Any]) -> Bool {
        if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 { return false }
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return false }
        let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
        let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
        return width >= 120 && height >= 120
    }

    // MARK: Raising

    /// Brings `window` to the front: un-minimizes it if needed, makes it the
    /// app's main window, raises it, and activates the owning application.
    static func raise(_ window: WindowInfo, pid: pid_t) {
        let runningApp = NSRunningApplication(processIdentifier: pid)

        // A hidden app (⌘H) keeps all its windows hidden; unhide before raising
        // or the AX raise has nothing visible to bring forward.
        if runningApp?.isHidden == true {
            runningApp?.unhide()
        }
        if let element = window.element {
            if window.isMinimized {
                let unminimize = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                if unminimize != .success {
                    NSLog("Zap: failed to un-minimize window (AX error \(unminimize.rawValue))")
                }
            }
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            let raise = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            if raise != .success {
                NSLog("Zap: failed to raise window (AX error \(raise.rawValue))")
            }
        }
        // Activating the app brings the target forward. For a window found only on
        // another Space (no AX element) it's the only lever available — switching to
        // its desktop is then best-effort and up to the system.
        if let runningApp, !activate(runningApp) {
            NSLog("Zap: failed to activate app pid \(pid) while raising window")
        }
    }

    // MARK: Activation

    /// Activates `app`, correctly handing activation over from Zap.
    ///
    /// macOS 14 introduced *cooperative activation*: once Zap has been the active
    /// app (which happens the moment the Settings window opens via `NSApp.activate`),
    /// it becomes part of the activation context. Hand off explicitly using Apple's
    /// documented sequence: the currently-active app yields to the target, then the
    /// target requests activation. A short verification retry covers silent no-ops
    /// where the activation request was accepted but not honored on that run-loop
    /// turn (seen after interacting with Settings/color controls).
    @discardableResult
    static func activate(_ app: NSRunningApplication, allWindows: Bool = false) -> Bool {
        let activated = requestActivation(of: app, allWindows: allWindows)
        if activated {
            verifyActivation(of: app, allWindows: allWindows, remainingRetries: 2)
        }
        return activated
    }

    @discardableResult
    private static func requestActivation(of app: NSRunningApplication, allWindows: Bool) -> Bool {
        if #available(macOS 14.0, *) {
            var options: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]
            if allWindows { options.insert(.activateAllWindows) }
            NSApp.yieldActivation(to: app)
            return app.activate(options: options)
        } else {
            var options: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]
            if allWindows { options.insert(.activateAllWindows) }
            return app.activate(options: options)
        }
    }

    private static func verifyActivation(of app: NSRunningApplication, allWindows: Bool, remainingRetries: Int) {
        guard remainingRetries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard !app.isTerminated else { return }
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard frontmostPID != app.processIdentifier else { return }
            requestActivation(of: app, allWindows: allWindows)
            verifyActivation(of: app, allWindows: allWindows, remainingRetries: remainingRetries - 1)
        }
    }

    // MARK: Closing

    /// Closes `window` by pressing its close button. Returns `false` when the
    /// window exposes no close button (so the caller can leave it in the list).
    @discardableResult
    static func close(_ window: WindowInfo) -> Bool {
        // No AX element (off-Space Quartz-only window) → nothing to press; leave it.
        guard let element = window.element else { return false }
        var button: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
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
