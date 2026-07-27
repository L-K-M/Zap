import Carbon.HIToolbox

/// Virtual key codes used by the switcher.
///
/// Position-based, which is correct for these keys: Tab, Escape, Delete, the
/// arrows and the backtick sit in the same place on every layout (and `grave` is
/// the physical key macOS itself uses for "cycle backwards"). Keys that stand for
/// a *letter* — the Q/H/W action keys — are deliberately absent: they're matched
/// on the character they type instead, via `EventTapMonitor.shortcutKey(for:)`,
/// so they land on the right key on AZERTY, Dvorak and QWERTZ.
enum KeyCode {
    static let tab: Int64 = 0x30      // 48
    static let grave: Int64 = 0x32    // 50  (backtick / ` )
    static let escape: Int64 = 0x35   // 53
    static let delete: Int64 = 0x33   // 51  (Delete / Backspace)
    static let arrowLeft: Int64 = 0x7B  // 123
    static let arrowRight: Int64 = 0x7C // 124
    static let arrowDown: Int64 = 0x7D  // 125
    static let arrowUp: Int64 = 0x7E    // 126

    /// Carbon key code values (UInt32) for `RegisterEventHotKey`.
    enum Carbon {
        static let tab = UInt32(kVK_Tab)
    }
}
