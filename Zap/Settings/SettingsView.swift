import SwiftUI

/// Root settings window content with tabs for each settings area.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        TabView {
            GeneralView(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }

            ExclusionsView(preferences: preferences)
                .tabItem { Label("Exclusions", systemImage: "minus.circle") }

            AppearanceView(preferences: preferences)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 460)
    }
}
