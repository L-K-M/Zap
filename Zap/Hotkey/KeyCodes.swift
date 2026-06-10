import Carbon.HIToolbox

/// Virtual key codes used by the switcher (US layout, position-based).
enum KeyCode {
    static let tab: Int64 = 0x30      // 48
    static let grave: Int64 = 0x32    // 50  (backtick / ` )
    static let escape: Int64 = 0x35   // 53
    static let q: Int64 = 0x0C        // 12
    static let w: Int64 = 0x0D        // 13
    static let h: Int64 = 0x04        // 4
    static let arrowLeft: Int64 = 0x7B  // 123
    static let arrowRight: Int64 = 0x7C // 124
    static let arrowDown: Int64 = 0x7D  // 125
    static let arrowUp: Int64 = 0x7E    // 126

    /// Carbon key code values (UInt32) for `RegisterEventHotKey`.
    enum Carbon {
        static let tab = UInt32(kVK_Tab)
    }
}
