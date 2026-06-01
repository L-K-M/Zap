import SwiftUI

/// Root settings window content with tabs for each settings area.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var inputMode: InputModeReporter

    var body: some View {
        TabView {
            GeneralView(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }

            ExclusionsView(preferences: preferences)
                .tabItem { Label("Exclusions", systemImage: "minus.circle") }

            AppearanceView(preferences: preferences)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            PermissionsView(inputMode: inputMode)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(minWidth: 520, minHeight: 460)
    }
}
