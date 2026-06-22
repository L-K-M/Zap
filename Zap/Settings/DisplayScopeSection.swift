import SwiftUI
import AppKit
import Combine

/// One connected display, for the per-display scope picker.
private struct DisplayOption: Identifiable {
    /// Stable display UUID — the key the mode is stored under.
    let id: String
    let name: String
}

/// Per-display "scope the switcher to the apps living on this screen" controls.
///
/// Disabled while "show on all displays" is on, since mirroring one shared panel
/// onto every screen and scoping the list per display are mutually exclusive
/// (mirroring takes precedence; the stored per-display modes are kept and resume
/// when mirroring is turned back off).
struct DisplayScopeSection: View {
    @ObservedObject var preferences: Preferences
    @State private var displays: [DisplayOption] = []

    private var mirroring: Bool { preferences.showOnAllScreens }

    var body: some View {
        Section("Per-display app list") {
            if displays.isEmpty {
                Text("No displays detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displays) { display in
                    Picker(display.name, selection: modeBinding(forID: display.id)) {
                        ForEach(ScreenScopeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                .disabled(mirroring)
            }

            Text(captionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)) { _ in refresh() }
    }

    private var captionText: String {
        if mirroring {
            return "Turn off “Show the switcher on all displays” to scope the app list per display."
        }
        return """
        Scope a display so its switcher lists only apps with a window on it. \
        “incl. excluded” also surfaces apps you’ve hidden under Exclusions when their \
        window is on that display. A scoped display with nothing on it falls back to \
        the full list.
        """
    }

    /// Rebuilds the display list from the current screen configuration, dropping any
    /// display whose stable id can't be resolved.
    private func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            guard let id = ScreenIdentity.persistentID(for: screen) else { return nil }
            return DisplayOption(id: id, name: ScreenIdentity.displayName(for: screen))
        }
    }

    private func modeBinding(forID id: String) -> Binding<ScreenScopeMode> {
        Binding(
            get: { preferences.screenScopeMode(forID: id) },
            set: { preferences.setScreenScopeMode($0, forID: id) }
        )
    }
}
