import SwiftUI
import AppKit
import Combine

/// Root settings window content with tabs for each settings area.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var inputMode: InputModeReporter
    @ObservedObject var updateChecker: UpdateChecker

    /// Whether more than one display is connected. The Displays tab — mirroring and
    /// per-display scoping — only applies with multiple displays, so it's shown only
    /// then. Tracked live so the tab appears/disappears as displays are connected.
    @State private var multipleDisplays = NSScreen.screens.count >= 2

    var body: some View {
        TabView {
            GeneralView(preferences: preferences, updateChecker: updateChecker)
                .tabItem { Label("General", systemImage: "gearshape") }

            ExclusionsView(preferences: preferences)
                .tabItem { Label("Exclusions", systemImage: "minus.circle") }

            if multipleDisplays {
                DisplaysView(preferences: preferences)
                    .tabItem { Label("Displays", systemImage: "rectangle.on.rectangle") }
            }

            AppearanceView(preferences: preferences)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            PermissionsView(inputMode: inputMode)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            AboutView(preferences: preferences)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 520, minHeight: 460)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)) { _ in
            multipleDisplays = NSScreen.screens.count >= 2
        }
    }
}
