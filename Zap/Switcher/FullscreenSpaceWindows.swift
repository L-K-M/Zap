import CoreGraphics
import Foundation

private typealias CGSConnectionID = UInt32

/// Private SkyLight SPIs that expose Spaces — their type and which windows live on
/// them. The public window list (`CGWindowListCopyWindowInfo`) carries no Space
/// information at all, so this is the only way to know a window sits on a
/// *full-screen* Space rather than an ordinary desktop. That distinction is what
/// lets screen-scoping include Split View pairs: each tiled window covers only half
/// the display, so it fails the "fills the screen" geometric test, yet macOS files
/// its Space under the full-screen type all the same.
///
/// Same trade-off as `_AXUIElementGetWindow` (see `WindowEnumerator`): fine for
/// Developer ID + notarization, would block App Store, and treated as best-effort —
/// callers must tolerate `nil` and fall back to geometry.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
private func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int,
                                              _ spaces: CFArray, _ options: Int,
                                              _ setTags: UnsafeMutablePointer<Int>,
                                              _ clearTags: UnsafeMutablePointer<Int>) -> CFArray

/// Resolves which windows live on full-screen Spaces, via SkyLight.
enum FullscreenSpaceWindows {

    /// The Space `type` value `CGSCopyManagedDisplaySpaces` reports for a
    /// full-screen Space — used both by a single full-screen app and by a Split
    /// View pair tiled side by side.
    static let fullscreenSpaceType = 4

    /// `CGSCopyWindowsWithOptionsAndTags` option bits (invisible windows, both
    /// sets) so windows on Spaces other than the current one are reported too —
    /// a full-screen Space the user isn't looking at is exactly the case of interest.
    private static let includeInvisibleOptions = 0b111

    /// The IDs of every window on any full-screen Space, across all displays.
    /// `nil` when the SPIs fail, so the caller can fall back to the geometric
    /// "fills the screen" heuristic; an empty set is a genuine "no full-screen
    /// windows right now."
    ///
    /// Display attribution is deliberately *not* read from the Space data: when
    /// Mission Control's "Displays have separate Spaces" is off, SkyLight reports
    /// a single "Main" display, so the caller attributes windows to displays by
    /// their bounds instead (same rule as the rest of screen-scoping).
    static func fullscreenWindowIDs() -> Set<CGWindowID>? {
        let connection = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return nil
        }
        let spaceIDs = fullscreenSpaceIDs(fromDisplaySpaces: displays)
        guard !spaceIDs.isEmpty else { return [] }
        var setTags = 0
        var clearTags = 0
        guard let windowIDs = CGSCopyWindowsWithOptionsAndTags(
            connection, 0, spaceIDs as CFArray, includeInvisibleOptions,
            &setTags, &clearTags) as? [CGWindowID]
        else { return nil }
        return Set(windowIDs)
    }

    /// The IDs of the full-screen-type Spaces in `displays`, the parsed form of
    /// `CGSCopyManagedDisplaySpaces`. Pure for testing.
    static func fullscreenSpaceIDs(fromDisplaySpaces displays: [[String: Any]]) -> [UInt64] {
        displays.flatMap { display in
            (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space in
                guard (space["type"] as? NSNumber)?.intValue == fullscreenSpaceType else { return nil }
                return (space["id64"] as? NSNumber)?.uint64Value
            }
        }
    }
}
