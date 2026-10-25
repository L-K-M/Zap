import CoreGraphics

/// Pure height budgeting for the panel, shared by `OverlayView` (which lays the
/// panel out and clips/scrolls the window section) and
/// `OverlayWindowController` (which must know whether a vertical scroll gesture
/// belongs to the window section or to the icon row).
///
/// The panel grows *downward* from a fixed top edge, so the height budget for
/// the window section is `maxPanelHeight` minus everything above and below it.
/// Everything that can appear must be reserved: under-reserving is what makes
/// the frame clamp in `layout(keepTop:)` shift the panel up mid-session, moving
/// the icon row the fixed top edge exists to keep still.
///
/// Heights are *reserves*, not measurements (same stance as
/// `HelpFooterMetrics`): they round up rather than tracking the exact wrap, so
/// the estimate never under-reserves. Kept analytic so the controller's
/// synchronous sizing pass needs no SwiftUI measurement round-trip.
enum PanelBudget {

    /// Vertical gap the panel's `VStack` puts between sections
    /// (`OverlayView.body`).
    static let sectionSpacing: CGFloat = 10

    /// Height of the one-line app-name label in the header.
    static let nameLineHeight: CGFloat = 20

    /// Height of the type-to-search badge (a one-line 12 pt capsule, 3 pt
    /// vertical padding each side), rounded up to a whole point.
    static let searchBadgeHeight: CGFloat = 23

    /// Height of the panel's always-visible header: outer padding, the optional
    /// name line, and the icon row (a square cell).
    static func headerHeight(contentPadding: CGFloat, cellWidth: CGFloat,
                             showsAppName: Bool) -> CGFloat {
        let nameBlock: CGFloat = showsAppName ? (nameLineHeight + sectionSpacing) : 0
        return contentPadding * 2 + cellWidth + nameBlock
    }

    /// Space between the icon row and the window section: the two `VStack` gaps
    /// (icon row to divider, divider to section) plus the divider line, rounded
    /// up a touch so the estimate never under-reserves.
    static var dividerReserve: CGFloat { sectionSpacing * 2 + 10 }

    /// Room the search badge takes below the icon row while a query is typed:
    /// the badge plus its gap.
    static var searchBadgeReserve: CGFloat { sectionSpacing + searchBadgeHeight }

    /// The window section's height budget: `maxPanelHeight` less the header,
    /// the divider gap, and whichever optional sections are showing, floored at
    /// `minimum` (one grid cell / list row) so the section is never unusable.
    static func windowSectionBudget(maxPanelHeight: CGFloat,
                                    headerHeight: CGFloat,
                                    dividerReserve: CGFloat,
                                    searchBadgeReserve: CGFloat,
                                    showsSearchBadge: Bool,
                                    helpFooterReserve: CGFloat,
                                    showsHelp: Bool,
                                    minimum: CGFloat) -> CGFloat {
        var reserved = headerHeight + dividerReserve
        if showsSearchBadge { reserved += searchBadgeReserve }
        if showsHelp { reserved += helpFooterReserve }
        return max(minimum, maxPanelHeight - reserved)
    }

    /// Whether the window section outgrows its budget and therefore becomes a
    /// `ScrollView` (the rule `OverlayView.windowSection` branches on): only
    /// then do vertical scroll gestures belong to it rather than to the icon
    /// row (see `OverlayWindowController.handleScroll`).
    static func scrolls(naturalHeight: CGFloat, budget: CGFloat) -> Bool {
        naturalHeight > budget
    }
}
