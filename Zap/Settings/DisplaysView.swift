import SwiftUI

/// Multi-display preferences: mirroring the panel onto every screen, and scoping the
/// app list per display. Surfaced as its own tab (see `SettingsView`) only when more
/// than one display is connected, since neither setting does anything on a single
/// screen.
struct DisplaysView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Mirroring") {
                Toggle("Show the switcher on all displays", isOn: $preferences.showOnAllScreens)
                Text("When off, the switcher appears only on the display with the pointer. When on, the same panel is mirrored onto every display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisplayScopeSection(preferences: preferences)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
