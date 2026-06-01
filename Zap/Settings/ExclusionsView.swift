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
        apps = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// "Show in switcher" = NOT excluded.
    private func showBinding(for app: AppInfo) -> Binding<Bool> {
        Binding(
            get: { !preferences.isExcluded(app.bundleIdentifier) },
            set: { preferences.setExcluded(!$0, bundleID: app.bundleIdentifier) }
        )
    }
}
