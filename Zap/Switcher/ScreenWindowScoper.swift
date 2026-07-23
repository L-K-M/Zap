import AppKit
import CoreGraphics

/// Determines which applications own a window on a given display, so the switcher
/// can scope its list to "what's living on this screen."
///
/// Built on the Quartz window list (`CGWindowListCopyWindowInfo`), which reports
/// windows across all apps and Spaces in a single call and — unlike window *titles*
/// — exposes geometry and owner PID without Screen Recording permission. Looking
/// across Spaces keeps a display's app list stable when its visible Space changes.
enum ScreenWindowScoper {

    /// A window reduced to the fields screen-scoping needs: its owner process and
    /// its CoreGraphics bounds (top-left origin, y-down, relative to the primary
    /// display's top-left), plus its Quartz window ID so SkyLight's full-screen
    /// Space membership can be checked. Extracted so the geometry can be
    /// unit-tested without a live window server.
    struct ScopedWindow: Equatable {
        let pid: pid_t
        let cgBounds: CGRect
        /// `kCGWindowNumber`, when the window-list entry carried one. Identifies
        /// the window to SkyLight's per-Space queries; `nil` in hand-built test
        /// fixtures.
        let windowID: CGWindowID?

        init(pid: pid_t, cgBounds: CGRect, windowID: CGWindowID? = nil) {
            self.pid = pid
            self.cgBounds = cgBounds
            self.windowID = windowID
        }
    }

    /// Smallest window (points) that counts toward a screen — filters out tiny
    /// transient/helper surfaces while keeping real utility windows.
    private static let minWindowSide: CGFloat = 80

    /// Absence of `.optionOnScreenOnly` is the important part: `.optionAll` has a
    /// zero raw value, while `.excludeDesktopElements` removes wallpaper windows.
    /// Internal so a regression test can lock the all-Spaces query contract.
    static let windowListOptions: CGWindowListOption = [.optionAll, .excludeDesktopElements]

    // MARK: Public

    /// The set of process IDs owning a normal window whose largest area falls on
    /// `target`. A window straddling two displays counts for the one holding most of
    /// it, so each window is attributed to exactly one screen. Returns an empty set
    /// if `target` can't be located among the connected displays.
    ///
    /// Regular desktop windows count across every Space assigned to `target`, so
    /// entering full-screen or Split View does not hide the apps on the display's
    /// regular desktops. A full-screen app on the currently visible Space always
    /// counts; `includeFullScreenFromOtherSpaces` controls whether full-screen apps
    /// on inactive Spaces count too.
    static func pidsOwningWindows(onDisplay target: NSScreen,
                                  includingFullScreenFromOtherSpaces includeFullScreenFromOtherSpaces: Bool = false,
                                  allScreens: [NSScreen] = NSScreen.screens) -> Set<pid_t> {
        guard
            let targetID = ScreenIdentity.displayID(for: target),
            let primaryHeight = primaryHeight(of: allScreens),
            let targetIndex = allScreens.firstIndex(where: { ScreenIdentity.displayID(for: $0) == targetID })
        else { return [] }
        let screenFrames = allScreens.map(\.frame)

        // `.optionAll` is intentional: inactive regular desktops disappear from an
        // on-screen-only snapshot whenever this display enters full-screen. Hidden
        // and minimized windows remain assigned to their display and therefore count.
        guard let infoList = CGWindowListCopyWindowInfo(windowListOptions, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let windows = infoList.compactMap { scopedWindow(from: $0) }
        let inactiveFullscreenWindowIDs: Set<CGWindowID>? = includeFullScreenFromOtherSpaces || windows.isEmpty
            ? nil
            : FullscreenSpaceWindows.inactiveFullscreenWindowIDs()
        return pids(for: windows, targetScreenIndex: targetIndex,
                    screenFrames: screenFrames, primaryHeight: primaryHeight,
                    includingFullScreenFromOtherSpaces: includeFullScreenFromOtherSpaces,
                    inactiveFullscreenWindowIDs: inactiveFullscreenWindowIDs)
    }

    // MARK: Pure helpers (unit-tested)

    /// Builds a `ScopedWindow` from one Quartz window-list entry, or `nil` when the
    /// entry isn't a real, normal-layer, document-sized window (wrong layer, a tiny
    /// or transparent helper surface, or missing bounds). Pure for testing.
    static func scopedWindow(from info: [String: Any]) -> ScopedWindow? {
        guard
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,   // normal window layer
            let bounds = info[kCGWindowBounds as String] as? [String: Any],
            let cgBounds = rect(fromBoundsDictionary: bounds),
            isLargeEnough(cgBounds)
        else { return nil }
        if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 {
            return nil
        }
        let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        return ScopedWindow(pid: pid, cgBounds: cgBounds, windowID: windowID)
    }

    /// The PIDs of `windows` whose dominant display is `targetScreenIndex`. When
    /// inactive full-screen Spaces are disabled, a window is removed only when
    /// SkyLight definitively places its ID exclusively on an inactive full-screen
    /// Space. Missing data fails open so regular desktop apps never disappear because
    /// a private query failed. Pure.
    static func pids(for windows: [ScopedWindow], targetScreenIndex: Int,
                     screenFrames: [CGRect], primaryHeight: CGFloat,
                     includingFullScreenFromOtherSpaces: Bool = true,
                     inactiveFullscreenWindowIDs: Set<CGWindowID>? = nil) -> Set<pid_t> {
        var pids = Set<pid_t>()
        for window in windows {
            let appKit = appKitRect(fromCG: window.cgBounds, primaryHeight: primaryHeight)
            guard dominantScreenIndex(windowFrame: appKit, screenFrames: screenFrames) == targetScreenIndex
            else { continue }
            if !includingFullScreenFromOtherSpaces,
               let windowID = window.windowID,
               inactiveFullscreenWindowIDs?.contains(windowID) == true {
                continue
            }
            pids.insert(window.pid)
        }
        return pids
    }

    /// Converts a CoreGraphics window rect (top-left origin, y-down, measured from the
    /// primary display's top-left) into AppKit global coordinates (bottom-left origin,
    /// y-up), where `primaryHeight` is the primary display's height. Both systems share
    /// the same origin point and X axis, so only Y is flipped.
    static func appKitRect(fromCG cg: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cg.origin.x,
               y: primaryHeight - cg.origin.y - cg.height,
               width: cg.width, height: cg.height)
    }

    /// The index of the screen in `screenFrames` holding the largest area of
    /// `windowFrame` (all in AppKit coordinates), or `nil` if it overlaps none. A
    /// window split across displays is attributed to whichever holds more of it.
    static func dominantScreenIndex(windowFrame: CGRect, screenFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in screenFrames.enumerated() {
            let intersection = windowFrame.intersection(frame)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            guard area > 0 else { continue }
            if let current = best {
                if area > current.area { best = (index, area) }
            } else {
                best = (index, area)
            }
        }
        return best?.index
    }

    /// The height of the primary display (the one whose AppKit frame origin is the
    /// global origin), used as the Y-flip constant. Pure.
    static func primaryHeight(of screens: [NSScreen]) -> CGFloat? {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        return primary.map { $0.frame.height }
    }

    // MARK: Private

    private static func isLargeEnough(_ rect: CGRect) -> Bool {
        rect.width >= minWindowSide && rect.height >= minWindowSide
    }

    /// Reads a CoreGraphics `kCGWindowBounds` dictionary into a `CGRect`.
    private static func rect(fromBoundsDictionary bounds: [String: Any]) -> CGRect? {
        guard
            let x = (bounds["X"] as? NSNumber)?.doubleValue,
            let y = (bounds["Y"] as? NSNumber)?.doubleValue,
            let width = (bounds["Width"] as? NSNumber)?.doubleValue,
            let height = (bounds["Height"] as? NSNumber)?.doubleValue
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
