import SwiftUI

/// General preferences: launch at login, the show delay, and the fallback hotkey.
struct GeneralView: View {
    @ObservedObject var preferences: Preferences
    @State private var screenRecordingGranted = ScreenRecordingAuthorizer.isGranted

    var body: some View {
        Form {
            Section {
                Toggle("Launch Zap at login", isOn: $preferences.launchAtLogin)
                if let error = preferences.launchAtLoginError {
                    Text("Couldn't update login item: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Timing") {
                VStack(alignment: .leading) {
                    Text("Show delay: \(Int(preferences.showDelayMs)) ms")
                    Slider(value: $preferences.showDelayMs, in: 0...250, step: 10)
                    Text("A short delay lets a quick ⌘-Tab tap switch apps without flashing the switcher.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Windows") {
                Toggle("Show an app's windows when the selection rests on it", isOn: $preferences.showWindowList)
                VStack(alignment: .leading) {
                    Text("Reveal after: \(Int(preferences.windowDwellMs)) ms")
                    Slider(value: $preferences.windowDwellMs, in: 100...1500, step: 50)
                    Text("While switching, keep the highlight on an app this long to list its windows. Use ↑/↓ to pick one. Requires Accessibility permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!preferences.showWindowList)

                Toggle("Show a preview of each window", isOn: $preferences.showWindowPreviews)
                    .disabled(!preferences.showWindowList)
                if preferences.showWindowPreviews {
                    windowPreviewHint
                }

                Toggle("Include full-screen windows on other desktops", isOn: $preferences.includeFullScreenWindows)
                    .disabled(!preferences.showWindowList)
                Text("""
                A full-screen window lives on its own desktop (Space), which macOS won't let Zap switch to directly: \
                choosing one activates the app and lets the system decide whether to jump to that desktop — it often \
                doesn't if the app also has windows on the current one. Their titles are also blank without Screen \
                Recording permission. Off by default for that reason.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Trigger") {
                Toggle("Use ⌥-Tab fallback when ⌘-Tab is unavailable", isOn: $preferences.useAlternateHotkey)
                Text("⌘-Tab requires Accessibility permission. Without it, Zap falls back to ⌥-Tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dismissing") {
                Toggle("Close the switcher when you click outside it", isOn: $preferences.closeOnClickOutside)
                Text("A click anywhere outside the panel dismisses the switcher without switching apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Displays") {
                Toggle("Show the switcher on all displays", isOn: $preferences.showOnAllScreens)
                Text("When off, the switcher appears only on the display with the pointer. When on, the same panel is mirrored onto every display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            preferences.refreshLaunchAtLoginStatus()
            screenRecordingGranted = ScreenRecordingAuthorizer.isGranted
        }
    }

    /// Guidance shown when previews are enabled, nudging the user to grant Screen
    /// Recording (a separate permission from Accessibility) when it's missing.
    @ViewBuilder
    private var windowPreviewHint: some View {
        if screenRecordingGranted {
            Text("Window previews need Screen Recording permission, which is granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Window previews need Screen Recording permission. Until it's granted, rows show an icon instead.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    Button("Grant Screen Recording…") {
                        ScreenRecordingAuthorizer.request()
                        screenRecordingGranted = ScreenRecordingAuthorizer.isGranted
                    }
                    Button("Open System Settings") {
                        ScreenRecordingAuthorizer.openSystemSettings()
                    }
                }
                .font(.caption)
            }
        }
    }
}
