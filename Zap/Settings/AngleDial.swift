import SwiftUI

/// A circular dial for picking a `0...360`° angle by dragging or clicking around
/// it. 0° points straight down (a top→bottom gradient) and increases clockwise,
/// matching `Preferences.gradientAngle`. The knob points in the gradient's flow
/// direction, so the dial reads as "the gradient runs this way."
struct AngleDial: View {
    @Binding var angleDegrees: Double
    var diameter: CGFloat = 46

    /// Whether the dial holds keyboard focus (drives the focus ring).
    @FocusState private var isFocused: Bool

    /// Angle step for keyboard arrows and VoiceOver increment/decrement.
    private static let adjustmentStep: Double = 5

    /// Returns `angle + delta` wrapped into `[0, 360)`; the shared adjustment
    /// path for keyboard and accessibility input (exposed for unit testing).
    /// Non-finite input, or a finite sum overflowing to infinity, falls back
    /// to `0`.
    static func adjustedAngle(_ angle: Double, by delta: Double) -> Double {
        guard angle.isFinite, delta.isFinite else { return 0 }
        let sum = angle + delta
        guard sum.isFinite else { return 0 }
        let wrapped = sum.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Whole degrees announced to VoiceOver, normalized into `0..<360` so an
    /// arbitrary binding value cannot read out nonsense (exposed for unit
    /// testing).
    static func announcedDegrees(_ angle: Double) -> Int {
        Int(adjustedAngle(angle, by: 0).rounded()) % 360
    }

    var body: some View {
        let radians = Self.adjustedAngle(angleDegrees, by: 0) * .pi / 180
        let reach = diameter / 2 - 6
        // Screen y grows downward, so (sin, cos) puts 0° at the bottom.
        let knob = CGPoint(x: sin(radians) * reach, y: cos(radians) * reach)

        ZStack {
            Circle().fill(Color.secondary.opacity(0.12))
            Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)

            Path { path in
                path.move(to: CGPoint(x: diameter / 2, y: diameter / 2))
                path.addLine(to: CGPoint(x: diameter / 2 + knob.x, y: diameter / 2 + knob.y))
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))

            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
                .offset(x: knob.x, y: knob.y)
        }
        .frame(width: diameter, height: diameter)
        .overlay(
            // Focus ring drawn just outside the dial; hit testing stays on the
            // dial's own contentShape so the ring can't swallow drags.
            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(-3)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
        )
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.location.x - diameter / 2
                    let dy = value.location.y - diameter / 2
                    guard dx != 0 || dy != 0 else { return }
                    var degrees = atan2(dx, dy) * 180 / .pi
                    if degrees < 0 { degrees += 360 }
                    angleDegrees = degrees
                }
        )
        .focusable()
        .focused($isFocused)
        .onMoveCommand { direction in
            switch direction {
            case .up, .right:
                angleDegrees = Self.adjustedAngle(angleDegrees, by: Self.adjustmentStep)
            case .down, .left:
                angleDegrees = Self.adjustedAngle(angleDegrees, by: -Self.adjustmentStep)
            default:
                break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gradient direction")
        .accessibilityValue("\(Self.announcedDegrees(angleDegrees)) degrees")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                angleDegrees = Self.adjustedAngle(angleDegrees, by: Self.adjustmentStep)
            case .decrement:
                angleDegrees = Self.adjustedAngle(angleDegrees, by: -Self.adjustmentStep)
            default:
                break
            }
        }
    }
}
