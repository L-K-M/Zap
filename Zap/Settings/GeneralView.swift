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
            }

            Section("Trigger") {
                Toggle("Use ⌥-Tab fallback when ⌘-Tab is unavailable", isOn: $preferences.useAlternateHotkey)
                Text("⌘-Tab requires Accessibility permission. Without it, Zap falls back to ⌥-Tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
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
