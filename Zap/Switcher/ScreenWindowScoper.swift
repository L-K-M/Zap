import AppKit
import CoreGraphics

/// Determines which applications own a window on a given display, so the switcher
/// can scope its list to "what's living on this screen."
///
/// Built on the Quartz window list (`CGWindowListCopyWindowInfo`), which reports
/// every on-screen window across all apps in a single call and — unlike window
/// *titles* — exposes geometry and owner PID without Screen Recording permission.
/// `.optionOnScreenOnly` means only windows on the *current* Space count, so
/// minimized/hidden apps and windows on other Spaces are naturally excluded.
enum ScreenWindowScoper {

    /// A window reduced to the fields screen-scoping needs: its owner process and
    /// its CoreGraphics bounds (top-left origin, y-down, relative to the primary
    /// display's top-left). Extracted so the geometry can be unit-tested without a
    /// live window server.
    struct ScopedWindow: Equatable {
        let pid: pid_t
        let cgBounds: CGRect
    }

    /// Smallest window (points) that counts toward a screen — filters out tiny
    /// transient/helper surfaces while keeping real utility windows.
    private static let minWindowSide: CGFloat = 80

    /// Minimum fraction of a display a window must cover to count as full-screen on
    /// it. A native full-screen window fills the display exactly; the margin only
    /// absorbs rounding and the menu-bar-area overhang.
    private static let fullScreenCoverageRatio: CGFloat = 0.9

    // MARK: Public

    /// The set of process IDs owning a normal window whose largest area falls on
    /// `target`. A window straddling two displays counts for the one holding most of
    /// it, so each window is attributed to exactly one screen. Returns an empty set
    /// if `target` can't be located among the connected displays.
    ///
    /// When `includeFullScreen` is on, apps that are *full-screen* on `target` are
    /// also included. macOS gives each native full-screen window its own Space, which
    /// the on-screen pass can't see, so a second all-Spaces pass backfills windows
    /// that fill the display — without sweeping in ordinary windows merely parked on
    /// another Space of it.
    static func pidsOwningWindows(onScreen target: NSScreen,
                                  includingFullScreen includeFullScreen: Bool = false,
                                  allScreens: [NSScreen] = NSScreen.screens) -> Set<pid_t> {
        guard
            let targetID = ScreenIdentity.displayID(for: target),
            let primaryHeight = primaryHeight(of: allScreens),
            let targetIndex = allScreens.firstIndex(where: { ScreenIdentity.displayID(for: $0) == targetID })
        else { return [] }
        let screenFrames = allScreens.map(\.frame)

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let windows = infoList.compactMap { scopedWindow(from: $0) }
        var result = pids(for: windows, targetScreenIndex: targetIndex,
                          screenFrames: screenFrames, primaryHeight: primaryHeight)

        // Full-screen apps live on their own Space, so the on-screen pass above never
        // sees them. Take a second pass across *all* Spaces and keep only windows that
        // fill the target display — the geometric signature of a full-screen window —
        // so ordinary windows parked on another Space of this display don't leak in.
        if includeFullScreen,
           let allList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] {
            let offSpace = allList.compactMap { offSpaceScopedWindow(from: $0) }
            result.formUnion(fullScreenPids(for: offSpace, targetScreenIndex: targetIndex,
                                            screenFrames: screenFrames, primaryHeight: primaryHeight))
        }
        return result
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
        return ScopedWindow(pid: pid, cgBounds: cgBounds)
    }

    /// The PIDs of `windows` whose dominant display is `targetScreenIndex`. Pure.
    static func pids(for windows: [ScopedWindow], targetScreenIndex: Int,
                     screenFrames: [CGRect], primaryHeight: CGFloat) -> Set<pid_t> {
        var pids = Set<pid_t>()
        for window in windows {
            let appKit = appKitRect(fromCG: window.cgBounds, primaryHeight: primaryHeight)
            if dominantScreenIndex(windowFrame: appKit, screenFrames: screenFrames) == targetScreenIndex {
                pids.insert(window.pid)
            }
        }
        return pids
    }

    /// Like `scopedWindow(from:)`, but only for windows that *aren't* on the current
    /// Space (`kCGWindowIsOnscreen` false or absent) — the off-Space windows, chiefly
    /// full-screen ones, that the on-screen pass omits. Skipping on-screen entries
    /// avoids double-counting windows the on-screen pass already handled. Pure.
    static func offSpaceScopedWindow(from info: [String: Any]) -> ScopedWindow? {
        guard (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue != true else { return nil }
        return scopedWindow(from: info)
    }

    /// The PIDs of off-Space `windows` that *fill* the target display — the signature
    /// of a native full-screen window, whose own Space hid it from the on-screen pass.
    /// Requiring near-total coverage keeps ordinary windows that merely live on another
    /// Space of this display out of the scoped list. Pure.
    static func fullScreenPids(for windows: [ScopedWindow], targetScreenIndex: Int,
                               screenFrames: [CGRect], primaryHeight: CGFloat) -> Set<pid_t> {
        guard screenFrames.indices.contains(targetScreenIndex) else { return [] }
        let targetFrame = screenFrames[targetScreenIndex]
        var pids = Set<pid_t>()
        for window in windows {
            let appKit = appKitRect(fromCG: window.cgBounds, primaryHeight: primaryHeight)
            guard dominantScreenIndex(windowFrame: appKit, screenFrames: screenFrames) == targetScreenIndex,
                  fillsScreen(windowFrame: appKit, screenFrame: targetFrame)
            else { continue }
            pids.insert(window.pid)
        }
        return pids
    }

    /// Whether `windowFrame` covers nearly all of `screenFrame` (by intersection
    /// area) — the test that tells a full-screen window apart from a smaller one that
    /// happens to sit on another Space. A window overhanging the display (full-screen
    /// windows can cover the menu-bar area) still qualifies. Pure.
    static func fillsScreen(windowFrame: CGRect, screenFrame: CGRect) -> Bool {
        let screenArea = screenFrame.width * screenFrame.height
        guard screenArea > 0 else { return false }
        let intersection = windowFrame.intersection(screenFrame)
        guard !intersection.isNull else { return false }
        return intersection.width * intersection.height >= screenArea * fullScreenCoverageRatio
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
