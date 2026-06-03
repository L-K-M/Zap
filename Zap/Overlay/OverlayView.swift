import SwiftUI
import AppKit

/// The switcher panel: a blurred rounded rectangle containing a row of app icons
/// with the selected app highlighted and (optionally) named.
struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var preferences: Preferences

    private var iconSpacing: CGFloat { 12 }
    private var outerPadding: CGFloat { preferences.contentPadding }

    var body: some View {
        VStack(spacing: 10) {
            if preferences.showAppName {
                Text(model.selectedApp?.name ?? " ")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hexString: preferences.labelColorHex))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: panelContentWidth)
            }

            HStack(spacing: iconSpacing) {
                ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                    iconCell(app, isSelected: index == model.selectedIndex,
                             isQuitting: model.quittingPIDs.contains(app.processIdentifier),
                             isDropTarget: index == model.dropTargetIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { model.onPick?(index) }
                        .onHover { hovering in
                            if hovering { model.onHoverApp?(index) }
                        }
                        // Let the user drop files onto an app to open them with it.
                        .dropDestination(for: URL.self) { urls, _ in
                            model.onDropFiles?(index, urls)
                            return true
                        } isTargeted: { targeted in
                            if targeted {
                                model.dropTargetIndex = index
                            } else if model.dropTargetIndex == index {
                                model.dropTargetIndex = nil
                            }
                        }
                }
            }
            .modifier(HorizontallyScrollable(active: iconRowGeometry.overflows,
                                              viewport: panelContentWidth,
                                              offset: model.scrollOffset,
                                              fade: iconRowFade))

            if !model.windows.isEmpty {
                Divider()
                    .frame(maxWidth: panelContentWidth)
                windowList
            }
        }
        .padding(outerPadding)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: preferences.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: preferences.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The icon row width, capped so the panel never exceeds the screen.
    private var panelContentWidth: CGFloat {
        min(maxRowWidth, model.maxContentWidth)
    }

    /// Footprint of one icon: the image plus its 8pt padding on each side.
    private var cellWidth: CGFloat { preferences.iconSize + 16 }

    private var maxRowWidth: CGFloat {
        let count = max(model.apps.count, 1)
        return CGFloat(count) * cellWidth + CGFloat(count - 1) * iconSpacing
    }

    /// Layout of the scrolling icon row, shared with the controller (which drives
    /// `scrollOffset`) via `IconRowGeometry`.
    private var iconRowGeometry: IconRowGeometry {
        IconRowGeometry(count: model.apps.count, cellWidth: cellWidth,
                        spacing: iconSpacing, viewport: panelContentWidth)
    }

    /// Edge-fade amounts for the (possibly scrolled) icon row, fading only the
    /// side(s) with content hidden past the edge. Tracks the real scroll position
    /// (`scrollOffset`), not the highlight, so it stays put while hovering.
    private var iconRowFade: EdgeFade {
        iconRowGeometry.fade(offset: model.scrollOffset, fadeWidth: preferences.iconSize)
    }

    private var panelBackground: some View {
        ZStack {
            VisualEffectBlur()
            backgroundFill
                .opacity(preferences.backgroundOpacity)
            if preferences.decorationStyle != .none {
                PanelDecoration(style: preferences.decorationStyle,
                                position: preferences.decorationPosition,
                                cornerRadius: preferences.cornerRadius,
                                thickness: preferences.decorationSize)
                    .opacity(preferences.decorationOpacity)
            }
        }
    }

    /// The tint behind the blur: either a solid color or a gradient.
    ///
    /// The gradient line is pinned to a fixed reference rect (`headerWidth` ×
    /// `headerHeight`, the always-present name + icon row) centered at the panel's
    /// top-center, then converted to `UnitPoint`s against the *current* panel size.
    /// Because the panel grows downward from a fixed top edge and widens from its
    /// center (see `OverlayWindowController`), pinning the line this way keeps the
    /// gradient's appearance over the icon row identical no matter how the panel
    /// resizes while open — any growth area simply extends the edge colors (which
    /// `LinearGradient` clamps to). This holds for every gradient angle.
    @ViewBuilder
    private var backgroundFill: some View {
        if preferences.useGradientBackground {
            GeometryReader { geo in
                let points = gradientPoints(in: geo.size)
                LinearGradient(
                    colors: [Color(hexString: preferences.backgroundColorHex),
                             Color(hexString: preferences.gradientColorHex)],
                    startPoint: points.start,
                    endPoint: points.end
                )
            }
        } else {
            Color(hexString: preferences.backgroundColorHex)
        }
    }

    /// Gradient line endpoints (as `UnitPoint`s in the current panel `size`) for
    /// `preferences.gradientAngle`, pinned so the line spans the top-center
    /// reference rect along the chosen direction regardless of panel size.
    private func gradientPoints(in size: CGSize) -> (start: UnitPoint, end: UnitPoint) {
        guard size.width > 0, size.height > 0 else { return (.top, .bottom) }
        let radians = preferences.gradientAngle * .pi / 180
        // Screen y grows downward, so (sin, cos) puts 0° at top→bottom.
        let dx = sin(radians)
        let dy = cos(radians)
        let centerX = size.width / 2
        let centerY = headerHeight / 2
        // Extent of the reference rect projected onto the gradient direction, so
        // the line spans corner-to-corner of the header for any angle.
        let halfExtent = headerWidth / 2 * abs(dx) + headerHeight / 2 * abs(dy)
        let start = CGPoint(x: centerX - dx * halfExtent, y: centerY - dy * halfExtent)
        let end = CGPoint(x: centerX + dx * halfExtent, y: centerY + dy * halfExtent)
        return (UnitPoint(x: start.x / size.width, y: start.y / size.height),
                UnitPoint(x: end.x / size.width, y: end.y / size.height))
    }

    /// Width of the panel's always-visible header (icon row + outer padding),
    /// the horizontal span the gradient line is pinned to.
    private var headerWidth: CGFloat {
        panelContentWidth + outerPadding * 2
    }

    /// Height of the panel's always-visible header (outer padding + optional app
    /// name + icon row), the vertical span the gradient line is pinned to.
    private var headerHeight: CGFloat {
        let iconCell = preferences.iconSize + 16  // icon image + its 8pt padding
        let nameBlock: CGFloat = preferences.showAppName ? (nameLineHeight + vStackSpacing) : 0
        return outerPadding * 2 + iconCell + nameBlock
    }

    private var nameLineHeight: CGFloat { 20 }
    private var vStackSpacing: CGFloat { 10 }

    private func iconCell(_ app: AppInfo, isSelected: Bool, isQuitting: Bool, isDropTarget: Bool) -> some View {
        Image(nsImage: app.icon ?? NSImage())
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: preferences.iconSize, height: preferences.iconSize)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: preferences.highlightCornerRadius, style: .continuous)
                    .fill(isSelected
                          ? Color(hexString: preferences.highlightColorHex).opacity(preferences.highlightOpacity)
                          : Color.clear)
            )
            // Accent ring while a file drag hovers this icon, marking the drop target.
            .overlay(
                RoundedRectangle(cornerRadius: preferences.highlightCornerRadius, style: .continuous)
                    .strokeBorder(Color(hexString: preferences.highlightColorHex),
                                  lineWidth: isDropTarget ? 3 : 0)
            )
            .animation(.easeOut(duration: 0.12), value: isDropTarget)
            // Dim apps that are quitting until their fate is confirmed.
            .opacity(isQuitting ? 0.3 : 1)
            .animation(.easeOut(duration: 0.15), value: isQuitting)
    }

    // MARK: Window list

    private var windowList: some View {
        VStack(spacing: 4) {
            ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                windowRow(window, isSelected: index == model.windowSelectedIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onPickWindow?(index) }
                    .onHover { hovering in
                        if hovering { model.onHoverWindow?(index) }
                    }
            }
        }
    }

    private func windowRow(_ window: WindowInfo, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            windowLeading(window)
            Text(window.title.isEmpty ? "Untitled" : window.title)
                .font(.system(size: 13))
                .foregroundStyle(Color(hexString: preferences.labelColorHex))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: preferences.showWindowPreviews ? 420 : 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected
                      ? Color(hexString: preferences.highlightColorHex).opacity(preferences.highlightOpacity)
                      : Color.clear)
        )
    }

    /// The leading element of a window row: a captured preview when previews are
    /// enabled and available, otherwise the window/minimized glyph. When previews
    /// are on, the placeholder occupies the same footprint so rows don't reflow as
    /// thumbnails stream in.
    @ViewBuilder
    private func windowLeading(_ window: WindowInfo) -> some View {
        if preferences.showWindowPreviews,
           let id = window.cgWindowID,
           let image = model.windowThumbnails[id] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(width: WindowPreviewMetrics.rowWidth, height: WindowPreviewMetrics.rowHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        } else {
            Image(systemName: window.isMinimized ? "macwindow.badge.minus" : "macwindow")
                .foregroundStyle(Color(hexString: preferences.labelColorHex).opacity(0.8))
                .frame(width: preferences.showWindowPreviews ? WindowPreviewMetrics.rowWidth : nil,
                       height: preferences.showWindowPreviews ? WindowPreviewMetrics.rowHeight : nil)
        }
    }
}

/// Shared sizing for window previews: `maxDimension` bounds the captured image
/// (see `WindowThumbnailProvider`), while the row dimensions fix the on-screen
/// thumbnail footprint.
enum WindowPreviewMetrics {
    static let maxDimension: CGFloat = 160
    static let rowWidth: CGFloat = 120
    static let rowHeight: CGFloat = 72
}

/// Clips a crowded icon row to `viewport` and scrolls it by a raw pixel `offset`,
/// so a row wider than the panel can be scrolled (continuously, by the wheel) and
/// auto-scrolled (animated, by the keyboard) without an inner `ScrollView` — which
/// on macOS 13 can't be driven to a pixel offset. When the row fits (`active` is
/// false) it's shown untouched.
///
/// The icons fade to transparent at an edge that has content scrolled past it (per
/// `fade`), so the cutoff reads as a deliberate soft edge rather than a hard clip;
/// the fade shows only where there's hidden content, so a first/last icon resting
/// flush against an edge stays crisp.
private struct HorizontallyScrollable: ViewModifier {
    let active: Bool
    let viewport: CGFloat
    let offset: CGFloat
    let fade: EdgeFade

    func body(content: Content) -> some View {
        if active && viewport.isFinite {
            content
                .fixedSize(horizontal: true, vertical: false)   // lay out at full width
                .offset(x: -offset)                             // scroll
                .frame(width: viewport, alignment: .leading)    // window onto the row
                .clipped()
                .mask { fadeMask }
        } else {
            content
        }
    }

    /// A horizontal mask: opaque through the middle, ramping to clear at an edge in
    /// proportion to how much content is hidden on that side.
    private var fadeMask: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .black.opacity(1 - fade.leading), location: 0),
                .init(color: .black, location: fade.inset),
                .init(color: .black, location: 1 - fade.inset),
                .init(color: .black.opacity(1 - fade.trailing), location: 1),
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
