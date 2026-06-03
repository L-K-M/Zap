import CoreGraphics

/// Translates raw scroll-wheel / trackpad deltas into whole-icon scroll steps for
/// the overflowing app-switcher row.
///
/// Pure apart from the caller-owned `accumulator`, so the stepping math (remainder
/// carry, normalising trackpad pixels vs mouse-wheel lines) can be unit-tested
/// without synthesising `NSEvent`s.
enum ScrollWheelStepper {
    /// Folds `raw` into `accumulator` and returns how many whole icons to advance.
    ///
    /// `pointsPerIcon` normalises the delta: trackpads report pixels (use a larger
    /// value), mouse wheels report lines (use `1`). Sign convention: a *negative*
    /// delta — a downward / leftward gesture under default pointer settings —
    /// advances toward *later* icons (a positive step). Flip the comparisons here if
    /// it feels inverted.
    static func steps(raw: CGFloat, pointsPerIcon: CGFloat, accumulator: inout CGFloat) -> Int {
        guard raw != 0, pointsPerIcon > 0 else { return 0 }
        accumulator += raw / pointsPerIcon
        var step = 0
        while accumulator >= 1 { step -= 1; accumulator -= 1 }
        while accumulator <= -1 { step += 1; accumulator += 1 }
        return step
    }
}
