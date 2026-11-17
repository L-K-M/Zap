/// The SF Symbols that stand in for a window in the overlay's window section:
/// the glyph in each list row, and the placeholder in a preview tile whose
/// capture hasn't arrived (or never will, for a minimized window).
///
/// One place for both, because `Image(systemName:)` draws *nothing* for a name
/// the system doesn't know. A misspelled or nonexistent symbol fails silently:
/// minimized windows once drew no glyph at all, which also shifted their row's
/// title out of line with its siblings. `SFSymbolNameTests` pins every name
/// here to one the running system resolves.
enum WindowGlyph {

    /// An ordinary window.
    static let standard = "macwindow"

    /// A minimized window: a window going down into the Dock. Available since
    /// SF Symbols 3 (macOS 12), so it covers Zap's macOS 13 floor.
    static let minimized = "dock.arrow.down.rectangle"

    /// Every symbol this type can return, for the resolution test.
    static let allSymbolNames = [standard, minimized]

    /// The glyph for a window in the given state.
    static func symbolName(isMinimized: Bool) -> String {
        isMinimized ? minimized : standard
    }
}
