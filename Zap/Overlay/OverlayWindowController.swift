import AppKit
import SwiftUI

/// Owns the borderless overlay window and keeps it positioned and sized to the
/// SwiftUI content. Shows across all Spaces and over fullscreen apps.
final class OverlayWindowController {

    let model = OverlayModel()
    private let window: NSWindow
    private let hostingView: NSHostingView<OverlayView>

    private(set) var isVisible = false

    init(preferences: Preferences) {
        hostingView = NSHostingView(rootView: OverlayView(model: model, preferences: preferences))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = hostingView
    }

    // MARK: Presentation

    func show(apps: [AppInfo], selectedIndex: Int, on screen: NSScreen) {
        model.apps = apps
        model.selectedIndex = selectedIndex

        resizeToFit(on: screen)
        window.orderFrontRegardless()
        isVisible = true
    }

    func updateSelection(_ index: Int) {
        model.selectedIndex = index
    }

    func hide() {
        guard isVisible else { return }
        window.orderOut(nil)
        isVisible = false
        model.apps = []
        model.selectedIndex = 0
    }

    // MARK: Layout

    private func resizeToFit(on screen: NSScreen) {
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let size = NSSize(
            width: max(fitting.width, 80),
            height: max(fitting.height, 80)
        )

        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
