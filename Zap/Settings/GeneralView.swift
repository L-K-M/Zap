import SwiftUI

/// General preferences: launch at login, the show delay, and the fallback hotkey.
struct GeneralView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Launch Zap at login", isOn: $preferences.launchAtLogin)
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
    }
}
