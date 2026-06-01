import SwiftUI
import AppKit

/// Lets the user pick which apps appear in the switcher.
struct ExclusionsView: View {
    @ObservedObject var preferences: Preferences

    @State private var apps: [AppInfo] = []
    @State private var search = ""

    private var filteredApps: [AppInfo] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
                Button("Refresh") { reload() }
            }
            .padding(10)

            Divider()

            List(filteredApps) { app in
                Toggle(isOn: showBinding(for: app)) {
                    HStack {
                        Image(nsImage: app.icon ?? NSImage())
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                    }
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.inset)

            Divider()
            Text("Unchecked apps are hidden from the switcher (they keep running).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))

        // Include excluded apps that aren't currently running so the user can
        // still see and re-enable them. Use a best-effort display name from the
        // app bundle on disk, falling back to the bundle identifier.
        let runningIDs = Set(running.map(\.bundleIdentifier))
        let offline = preferences.excludedBundleIDs
            .filter { !runningIDs.contains($0) }
            .map { bundleID -> AppInfo in
                AppInfo(bundleIdentifier: bundleID,
                        name: Self.displayName(forBundleID: bundleID) ?? bundleID,
                        processIdentifier: -1,
                        icon: Self.icon(forBundleID: bundleID))
            }

        apps = (running + offline)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolves a human-readable name for an installed (but not running) app.
    private static func displayName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    /// Resolves the icon for an installed (but not running) app.
    private static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// "Show in switcher" = NOT excluded.
    private func showBinding(for app: AppInfo) -> Binding<Bool> {
        Binding(
            get: { !preferences.isExcluded(app.bundleIdentifier) },
            set: { preferences.setExcluded(!$0, bundleID: app.bundleIdentifier) }
        )
    }
}
