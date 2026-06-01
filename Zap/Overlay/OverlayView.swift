import SwiftUI
import AppKit

/// The switcher panel: a blurred rounded rectangle containing a row of app icons
/// with the selected app highlighted and (optionally) named.
struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var preferences: Preferences

    private var outerPadding: CGFloat { 20 }
    private var iconSpacing: CGFloat { 12 }

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
                    iconCell(app, isSelected: index == model.selectedIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { model.onPick?(index) }
                        .onHover { hovering in
                            if hovering { model.onHoverApp?(index) }
                        }
                }
            }
            .modifier(HorizontallyScrollable(active: maxRowWidth > model.maxContentWidth,
                                              width: panelContentWidth))

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

    private var maxRowWidth: CGFloat {
        let count = max(model.apps.count, 1)
        let cell = preferences.iconSize + 16
        return CGFloat(count) * cell + CGFloat(count - 1) * iconSpacing
    }

    private var panelBackground: some View {
        ZStack {
            VisualEffectBlur()
            Color(hexString: preferences.backgroundColorHex)
                .opacity(preferences.backgroundOpacity)
        }
    }

    private func iconCell(_ app: AppInfo, isSelected: Bool) -> some View {
        Image(nsImage: app.icon ?? NSImage())
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: preferences.iconSize, height: preferences.iconSize)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? Color(hexString: preferences.highlightColorHex).opacity(preferences.highlightOpacity)
                          : Color.clear)
            )
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
        .padding(.vertical, 6)
        .frame(maxWidth: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected
                      ? Color(hexString: preferences.highlightColorHex).opacity(preferences.highlightOpacity)
                      : Color.clear)
        )
    }
}

/// Wraps content in a horizontal `ScrollView` constrained to `width` when
/// `active`, so a crowded icon row scrolls instead of overflowing the screen.
private struct HorizontallyScrollable: ViewModifier {
    let active: Bool
    let width: CGFloat

    func body(content: Content) -> some View {
        if active && width.isFinite {
            ScrollView(.horizontal, showsIndicators: false) { content }
                .frame(width: width)
        } else {
            content
        }
    }
}
