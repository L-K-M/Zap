import SwiftUI
import AppKit
import Combine

/// Root settings window content with tabs for each settings area.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var inputMode: InputModeReporter
    @ObservedObject var updateChecker: UpdateChecker
    let icons: ZapIcons

    /// Whether more than one display is connected. The Displays tab — mirroring and
    /// per-display scoping — only applies with multiple displays, so it's shown only
    /// then. Tracked live so the tab appears/disappears as displays are connected.
    @State private var multipleDisplays = NSScreen.screens.count >= 2

    var body: some View {
        TabHost(preferences: preferences, inputMode: inputMode,
                updateChecker: updateChecker, icons: icons,
                multipleDisplays: multipleDisplays)
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification)) { _ in
                multipleDisplays = NSScreen.screens.count >= 2
            }
    }

    private struct TabHost: NSViewControllerRepresentable {
        let preferences: Preferences
        let inputMode: InputModeReporter
        let updateChecker: UpdateChecker
        let icons: ZapIcons
        let multipleDisplays: Bool

        func makeNSViewController(context: Context) -> SettingsTabViewController {
            SettingsTabViewController(preferences: preferences, inputMode: inputMode,
                                      updateChecker: updateChecker, icons: icons,
                                      showsDisplays: multipleDisplays)
        }

        func updateNSViewController(_ controller: SettingsTabViewController, context: Context) {
            controller.setShowsDisplays(multipleDisplays)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsViewController controller: SettingsTabViewController,
                          context: Context) -> CGSize? {
            guard proposal.width?.isInfinite != true, proposal.height?.isInfinite != true else { return nil }
            // The native selector can be wider than 520 points. Forward its
            // minimum through SwiftUI so the window cannot clip the end tabs.
            let fittingSize = controller.view.fittingSize
            let minimum = CGSize(width: max(520, fittingSize.width),
                                 height: max(460, fittingSize.height))
            return CGSize(width: max(proposal.width ?? minimum.width, minimum.width),
                          height: max(proposal.height ?? minimum.height, minimum.height))
        }
    }
}
