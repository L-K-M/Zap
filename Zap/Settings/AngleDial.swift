import SwiftUI

/// A circular dial for picking a `0...360`° angle by dragging or clicking around
/// it. 0° points straight down (a top→bottom gradient) and increases clockwise,
/// matching `Preferences.gradientAngle`. The knob points in the gradient's flow
/// direction, so the dial reads as "the gradient runs this way."
struct AngleDial: View {
    @Binding var angleDegrees: Double
    var diameter: CGFloat = 46

    var body: some View {
        let radians = angleDegrees * .pi / 180
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
        .accessibilityLabel("Gradient direction")
        .accessibilityValue("\(Int(angleDegrees.rounded())) degrees")
    }
}
