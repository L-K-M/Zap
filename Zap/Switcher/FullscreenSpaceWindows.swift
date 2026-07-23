import CoreGraphics
import Foundation

private typealias CGSConnectionID = UInt32

/// Private SkyLight SPIs that expose Spaces — their type and which windows live on
/// them. The public window list (`CGWindowListCopyWindowInfo`) carries no Space
/// information at all, so this is the only way to know a window sits on a
/// *full-screen* Space rather than an ordinary desktop. Screen scoping needs that
/// distinction only when the user opts out of apps on inactive full-screen Spaces;
/// it also handles Split View, whose two tiled windows share that Space type.
///
/// Same trade-off as `_AXUIElementGetWindow` (see `WindowEnumerator`): fine for
/// Developer ID + notarization, would block App Store, and treated as best-effort —
/// callers must tolerate `nil` and conservatively keep unclassified windows.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
private func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int,
                                              _ spaces: CFArray, _ options: Int,
                                              _ setTags: UnsafeMutablePointer<Int>,
                                              _ clearTags: UnsafeMutablePointer<Int>) -> CFArray?

/// Resolves which windows live on full-screen Spaces, via SkyLight.
enum FullscreenSpaceWindows {

    struct SpaceGroups: Equatable {
        /// Full-screen Spaces that are not the current Space of their display.
        let inactiveFullscreen: Set<UInt64>
        /// Every Space whose windows must remain eligible: regular desktops, each
        /// display's current full-screen Space, and system Spaces.
        let retained: Set<UInt64>
    }

    /// The Space `type` value `CGSCopyManagedDisplaySpaces` reports for a
    /// full-screen Space — used both by a single full-screen app and by a Split
    /// View pair tiled side by side.
    static let fullscreenSpaceType = 4

    /// `CGSCopyWindowsWithOptionsAndTags` option bits so windows on Spaces other
    /// than the current one are reported too — a full-screen Space the user isn't
    /// looking at is exactly the case of interest. Bit names per the community
    /// reverse-engineering (AltTab): bit 0 = `invisible1`, bit 1 =
    /// `screenSaverLevel1000`, bit 2 = `invisible2`.
    private static let includeInvisibleOptions = 0b111

    /// The IDs of windows that live exclusively on inactive full-screen Spaces.
    /// Windows also present in any retained Space are subtracted; this keeps sticky
    /// "All Desktops" windows and windows moving between Spaces from being mistaken
    /// for inactive full-screen apps. `nil` means the topology or either window query
    /// was incomplete, so the caller must avoid removing unclassified windows.
    ///
    /// Display attribution is deliberately *not* read from the Space data: when
    /// Mission Control's "Displays have separate Spaces" is off, SkyLight reports
    /// a single "Main" display, so the caller attributes windows to displays by
    /// their bounds instead (same rule as the rest of screen-scoping).
    static func inactiveFullscreenWindowIDs() -> Set<CGWindowID>? {
        let connection = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return nil
        }
        guard let groups = spaceGroups(fromDisplaySpaces: displays) else { return nil }
        guard !groups.inactiveFullscreen.isEmpty else { return [] }
        guard !groups.retained.isEmpty,
              let inactiveWindowIDs = windowIDs(in: groups.inactiveFullscreen, connection: connection),
              let retainedWindowIDs = windowIDs(in: groups.retained, connection: connection)
        else { return nil }
        return exclusiveWindowIDs(in: inactiveWindowIDs, excluding: retainedWindowIDs)
    }

    /// Separates inactive full-screen Spaces from every Space whose windows remain
    /// eligible. Strict parsing is deliberate: this data drives exclusion, so a
    /// malformed topology must fail open instead of hiding an app. Pure for testing.
    static func spaceGroups(fromDisplaySpaces displays: [[String: Any]]) -> SpaceGroups? {
        guard !displays.isEmpty else { return nil }
        var inactiveFullscreen = Set<UInt64>()
        var retained = Set<UInt64>()
        for display in displays {
            guard
                let spaces = display["Spaces"] as? [[String: Any]],
                let currentSpace = display["Current Space"] as? [String: Any],
                let currentSpaceID = exactUInt64(currentSpace["id64"])
            else { return nil }
            var foundCurrentSpace = false
            for space in spaces {
                guard
                    let id = exactUInt64(space["id64"]),
                    let type = exactInt(space["type"])
                else { return nil }
                if id == currentSpaceID { foundCurrentSpace = true }
                if type == fullscreenSpaceType, id != currentSpaceID {
                    inactiveFullscreen.insert(id)
                } else {
                    retained.insert(id)
                }
            }
            guard foundCurrentSpace else { return nil }
        }
        return SpaceGroups(inactiveFullscreen: inactiveFullscreen, retained: retained)
    }

    /// Subtracting retained-Space membership is what prevents sticky windows from
    /// being classified as inactive full-screen windows. Pure for testing.
    static func exclusiveWindowIDs(in inactiveWindowIDs: Set<CGWindowID>,
                                   excluding retainedWindowIDs: Set<CGWindowID>) -> Set<CGWindowID> {
        inactiveWindowIDs.subtracting(retainedWindowIDs)
    }

    private static func windowIDs(in spaceIDs: Set<UInt64>,
                                  connection: CGSConnectionID) -> Set<CGWindowID>? {
        var setTags = 0
        var clearTags = 0
        guard let rawIDs = CGSCopyWindowsWithOptionsAndTags(
            connection, 0, Array(spaceIDs) as CFArray, includeInvisibleOptions,
            &setTags, &clearTags) as? [Any]
        else { return nil }
        return windowIDs(from: rawIDs)
    }

    /// Strict decoding prevents malformed private-SPI values from wrapping onto a
    /// real window ID and excluding the wrong app. Pure for testing.
    static func windowIDs(from rawIDs: [Any]) -> Set<CGWindowID>? {
        var result = Set<CGWindowID>()
        for rawID in rawIDs {
            guard let value = exactUInt64(rawID), value <= UInt64(CGWindowID.max) else {
                return nil
            }
            result.insert(CGWindowID(value))
        }
        return result
    }

    private static func exactUInt64(_ raw: Any?) -> UInt64? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let value = number.uint64Value
        return number.compare(NSNumber(value: value)) == .orderedSame ? value : nil
    }

    private static func exactInt(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let value = number.intValue
        return number.compare(NSNumber(value: value)) == .orderedSame ? value : nil
    }
}
