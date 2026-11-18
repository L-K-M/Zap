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

    /// Builds one label per entry in `displays`, keeping identical `name`s
    /// distinguishable for the per-display scope pickers.
    ///
    /// Rules:
    /// - A name that occurs exactly once is returned unchanged.
    /// - A name shared by exactly two displays gets a position word derived from
    ///   the frames' centers in AppKit global coordinates (y grows upward). When
    ///   the horizontal distance between centers is at least the vertical
    ///   distance, the smaller `midX` becomes " (left)" and the other " (right)";
    ///   otherwise the larger `midY` becomes " (top)" and the other " (bottom)".
    ///   Identical centers (mirrored displays) fall back to numbering.
    /// - A name shared by three or more displays gets " (1)", " (2)", ... in
    ///   reading order: sorted by `midX` ascending, ties broken by `midY`
    ///   descending.
    ///
    /// Labels are unique within a group of identical names. A display whose
    /// own name already ends in such a suffix (say "DELL (left)") could match
    /// another group's label; names come from the display's EDID, so that is
    /// left alone rather than renumbered. Callers must pass frames in AppKit's
    /// global screen coordinate space for the position words to match the
    /// physical layout.
    static func disambiguatedNames(_ displays: [(id: String, name: String, frame: CGRect)]) -> [String] {
        var names = [String](repeating: "", count: displays.count)
        let groups = Dictionary(grouping: displays.indices, by: { displays[$0].name })

        for (_, indices) in groups {
            guard let first = indices.first else { continue }
            guard indices.count > 1 else {
                names[first] = displays[first].name
                continue
            }

            if indices.count == 2 {
                let a = displays[indices[0]]
                let b = displays[indices[1]]
                let horizontalGap = abs(a.frame.midX - b.frame.midX)
                let verticalGap = abs(a.frame.midY - b.frame.midY)

                if horizontalGap == 0 && verticalGap == 0 {
                    // Mirrored displays share a center, so position words can't
                    // tell them apart; number them instead.
                    assignNumberedNames(indices, displays: displays, into: &names)
                } else if horizontalGap >= verticalGap {
                    let left = a.frame.midX < b.frame.midX ? indices[0] : indices[1]
                    let right = left == indices[0] ? indices[1] : indices[0]
                    names[left] = "\(a.name) (left)"
                    names[right] = "\(a.name) (right)"
                } else {
                    let top = a.frame.midY > b.frame.midY ? indices[0] : indices[1]
                    let bottom = top == indices[0] ? indices[1] : indices[0]
                    names[top] = "\(a.name) (top)"
                    names[bottom] = "\(a.name) (bottom)"
                }
                continue
            }

            assignNumberedNames(indices, displays: displays, into: &names)
        }

        return names
    }

    /// Writes "name (n)" for `indices`, ordered by `midX` ascending with `midY`
    /// descending as the tie-break (reading order). The persistent display ID is the final
    /// tie-break for exactly coincident centers.
    private static func assignNumberedNames(
        _ indices: [Int],
        displays: [(id: String, name: String, frame: CGRect)],
        into names: inout [String]
    ) {
        let name = displays[indices[0]].name
        let ordered = indices.sorted {
            let a = displays[$0].frame
            let b = displays[$1].frame
            if a.midX != b.midX { return a.midX < b.midX }
            if a.midY != b.midY { return a.midY > b.midY }
            return displays[$0].id < displays[$1].id
        }
        for (position, index) in ordered.enumerated() {
            names[index] = "\(name) (\(position + 1))"
        }
    }
}
