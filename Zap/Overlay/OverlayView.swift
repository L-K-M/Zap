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
                    .frame(maxWidth: max(panelContentWidth, windowSectionWidth))
                windowSection
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

    // MARK: Window list / grid

    /// The window area below the icon row: a preview **grid** when previews are on,
    /// otherwise a single-column **list** of titles. Either form scrolls internally
    /// once it would grow taller than `windowListBudget` (the room left on screen),
    /// so a long window list never pushes the panel's top off-screen.
    @ViewBuilder
    private var windowSection: some View {
        if windowSectionNaturalHeight > windowListBudget {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    windowSectionContent
                }
                .frame(width: windowSectionWidth, height: windowListBudget)
                // Keep the keyboard-selected window visible. Driven by an explicit
                // tick so hover (which also moves the selection) never scrolls.
                .onChange(of: model.windowScrollTick) { _ in
                    scrollSelectionIntoView(proxy)
                }
            }
        } else {
            windowSectionContent
        }
    }

    @ViewBuilder
    private var windowSectionContent: some View {
        if preferences.showWindowPreviews {
            windowGrid
        } else {
            windowList
        }
    }

    /// Scrolls the highlighted window to just within view (minimal movement, so an
    /// already-visible cell doesn't jump). Falls back to the top when focus has
    /// returned to the app row.
    private func scrollSelectionIntoView(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if let index = model.windowSelectedIndex, model.windows.indices.contains(index) {
                proxy.scrollTo(model.windows[index].id)
            } else if let first = model.windows.first {
                proxy.scrollTo(first.id, anchor: .top)
            }
        }
    }

    // MARK: Window grid (previews on)

    private var windowGrid: some View {
        let columns = max(1, windowGridGeometry.columns)
        let count = model.windows.count
        let rowStarts = Array(stride(from: 0, to: count, by: columns))
        return VStack(spacing: WindowGridMetrics.spacing) {
            ForEach(rowStarts, id: \.self) { start in
                HStack(spacing: WindowGridMetrics.spacing) {
                    ForEach(start..<min(start + columns, count), id: \.self) { index in
                        windowCell(model.windows[index], index: index,
                                   isSelected: index == model.windowSelectedIndex)
                    }
                }
            }
        }
    }

    private func windowCell(_ window: WindowInfo, index: Int, isSelected: Bool) -> some View {
        VStack(spacing: WindowGridMetrics.innerSpacing) {
            windowThumbnail(window)
            Text(window.title.isEmpty ? "Untitled" : window.title)
                .font(.system(size: 11))
                .foregroundStyle(Color(hexString: preferences.labelColorHex))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: WindowGridMetrics.thumbWidth)
        }
        .padding(WindowGridMetrics.padding)
        .frame(width: WindowGridMetrics.cellWidth, height: WindowGridMetrics.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected
                      ? Color(hexString: preferences.highlightColorHex).opacity(preferences.highlightOpacity)
                      : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.onPickWindow?(index) }
        .onHover { hovering in
            if hovering { model.onHoverWindow?(index) }
        }
        .id(window.id)
    }

    /// A captured preview when available, otherwise a placeholder tile carrying the
    /// window/minimized glyph. Both share the same footprint so cells don't reflow
    /// as thumbnails stream in.
    @ViewBuilder
    private func windowThumbnail(_ window: WindowInfo) -> some View {
        if let id = window.cgWindowID, let image = model.windowThumbnails[id] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(width: WindowGridMetrics.thumbWidth, height: WindowGridMetrics.thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: WindowGridMetrics.thumbWidth, height: WindowGridMetrics.thumbHeight)
                .overlay(
                    Image(systemName: window.isMinimized ? "macwindow.badge.minus" : "macwindow")
                        .foregroundStyle(Color(hexString: preferences.labelColorHex).opacity(0.8))
                )
        }
    }

    // MARK: Window list (previews off)

    private var windowList: some View {
        VStack(spacing: WindowRowMetrics.spacing) {
            ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                windowRow(window, index: index, isSelected: index == model.windowSelectedIndex)
            }
        }
    }

    private func windowRow(_ window: WindowInfo, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: window.isMinimized ? "macwindow.badge.minus" : "macwindow")
                .foregroundStyle(Color(hexString: preferences.labelColorHex).opacity(0.8))
            Text(window.title.isEmpty ? "Untitled" : window.title)
                .font(.system(size: 13))
                .foregroundStyle(Color(hexString: preferences.labelColorHex))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: windowListWidth, height: WindowRowMetrics.height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected
                      ? Color(hexString: preferences.highlightColorHex).opacity(preferences.highlightOpacity)
                      : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.onPickWindow?(index) }
        .onHover { hovering in
            if hovering { model.onHoverWindow?(index) }
        }
        .id(window.id)
    }

    // MARK: Window section geometry

    /// Width of the single-column window list, capped to the screen.
    private var windowListWidth: CGFloat { min(360, model.maxContentWidth) }

    /// Layout of the preview grid, shared with the controller (which uses the column
    /// count for arrow-key navigation) via `WindowGridGeometry`.
    private var windowGridGeometry: WindowGridGeometry {
        WindowGridGeometry(count: model.windows.count,
                           availableWidth: model.maxContentWidth,
                           cellWidth: WindowGridMetrics.cellWidth,
                           cellHeight: WindowGridMetrics.cellHeight,
                           spacing: WindowGridMetrics.spacing)
    }

    /// On-screen width of the window section (grid or list).
    private var windowSectionWidth: CGFloat {
        preferences.showWindowPreviews ? windowGridGeometry.width : windowListWidth
    }

    /// Natural (unclipped) height of the window section, computed analytically from
    /// fixed cell/row metrics so the controller's synchronous sizing pass and the
    /// scroll decision agree without a measurement round-trip.
    private var windowSectionNaturalHeight: CGFloat {
        if preferences.showWindowPreviews {
            return windowGridGeometry.height
        }
        let n = CGFloat(model.windows.count)
        guard n > 0 else { return 0 }
        return n * WindowRowMetrics.height + (n - 1) * WindowRowMetrics.spacing
    }

    /// The vertical room the window section may occupy before it scrolls: the
    /// panel's screen-derived height budget minus everything above it (header, the
    /// inter-section gaps, and the divider).
    private var windowListBudget: CGFloat {
        let reserved = headerHeight + dividerReserve
        let minimum = preferences.showWindowPreviews
            ? WindowGridMetrics.cellHeight
            : WindowRowMetrics.height
        return max(minimum, model.maxPanelHeight - reserved)
    }

    /// Space between the icon row and the window section: the two `VStack` gaps
    /// (icon row↔divider, divider↔section) plus the divider line, rounded up a touch
    /// so the estimate never under-reserves and lets the panel overflow.
    private var dividerReserve: CGFloat { vStackSpacing * 2 + 10 }
}

/// Shared sizing for window previews: `maxDimension` bounds the captured image
/// (see `WindowThumbnailProvider`), while the row dimensions fix the on-screen
/// thumbnail footprint.
enum WindowPreviewMetrics {
    static let maxDimension: CGFloat = 160
    static let rowWidth: CGFloat = 120
    static let rowHeight: CGFloat = 72
}

/// Fixed footprint of one window-preview grid cell (thumbnail above a one-line
/// title). Heights are exact so the grid's natural size can be computed without a
/// SwiftUI measurement pass — see `OverlayView.windowSectionNaturalHeight`.
enum WindowGridMetrics {
    static let thumbWidth = WindowPreviewMetrics.rowWidth
    static let thumbHeight = WindowPreviewMetrics.rowHeight
    static let titleHeight: CGFloat = 16
    static let innerSpacing: CGFloat = 4
    static let padding: CGFloat = 6
    /// Gap between cells, horizontally and vertically.
    static let spacing: CGFloat = 8
    static var cellWidth: CGFloat { thumbWidth + padding * 2 }
    static var cellHeight: CGFloat { thumbHeight + innerSpacing + titleHeight + padding * 2 }
}

/// Fixed sizing for one row of the previews-off window list, kept exact for the
/// same reason as `WindowGridMetrics`.
enum WindowRowMetrics {
    static let height: CGFloat = 30
    static let spacing: CGFloat = 4
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
