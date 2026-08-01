import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Lets the user choose where the switcher's icons come from, and override any
/// single app's (`UNJAILED.md §8.4`).
struct IconsView: View {
    @ObservedObject var preferences: Preferences
    let iconResolver: IconResolver

    @State private var apps: [AppInfo] = []
    @State private var statuses: [String: IconResolver.Status] = [:]
    @State private var search = ""
    @State private var problem: String?
    /// Bundle identifier of the row a drag is currently over.
    @State private var dropTarget: String?
    /// Bundle identifiers with a remote fetch in flight.
    @State private var fetching: Set<String> = []

    private var filteredApps: [AppInfo] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var store: IconStore { iconResolver.store }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            List(filteredApps) { app in
                row(for: app)
            }
            .listStyle(.inset)

            Divider()
            footer
        }
        .onAppear(perform: reload)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Icon source", selection: $preferences.iconSourceMode) {
                ForEach(IconSourceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            // The honest limitation, stated rather than buried: Zap draws its own
            // icon row, so this is a presentation choice inside Zap and nothing else.
            Label("Applies to Zap's switcher only. The Dock and Finder keep showing the system's icons.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !IconSourceMode.isSquircleJailed {
                Text("This version of macOS doesn't mask app icons, so there's nothing to un-jail — the original artwork and the system icon are the same picture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
                Button("Refresh", action: reload)
            }
        }
        .padding(10)
    }

    // MARK: Rows

    private func row(for app: AppInfo) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: icon(for: app) ?? NSImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(rowStatus(for: app))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Choose File…") { chooseFile(for: app) }
                Button("Use Original Artwork") { useOriginalArtwork(for: app) }
                    .disabled(!hasOverride(app))
                Button("Use System Icon") { useSystemIcon(for: app) }
                    .disabled(statuses[app.bundleIdentifier]?.isPinnedToSystemIcon == true)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // §5.3: the browser is the search box. A drag from one carries a URL rather
        // than a file, and that is the more important ingestion path of the two.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            adopt(url, for: app)
            return true
        } isTargeted: { targeted in
            if targeted {
                dropTarget = app.bundleIdentifier
            } else if dropTarget == app.bundleIdentifier {
                dropTarget = nil
            }
        }
        .listRowBackground(dropTarget == app.bundleIdentifier
                           ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    /// What the row's caption says, including transient states the status fetch
    /// doesn't know about.
    private func rowStatus(for app: AppInfo) -> String {
        if fetching.contains(app.bundleIdentifier) { return "Downloading…" }
        return statuses[app.bundleIdentifier]?.label ?? "Checking…"
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Reset All Icons", role: .destructive, action: resetAll)
                Spacer()
            }

            Text("Drag an image onto a row from Finder, or straight from a browser — searching the web for an icon is free there, and Google Images can filter to transparent backgrounds only (Tools → Color → Transparent). Nothing about your apps is ever sent anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Lists running apps, plus any app you've already given an icon. Custom icons need the third option above; adding one switches to it for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    // MARK: Actions

    /// Shows the icon Zap would actually draw, falling back to the system icon
    /// while the resolver is still warming.
    private func icon(for app: AppInfo) -> NSImage? {
        iconResolver.icon(forBundleID: app.bundleIdentifier) ?? app.icon
    }

    private func hasOverride(_ app: AppInfo) -> Bool {
        guard let status = statuses[app.bundleIdentifier] else { return false }
        return status.hasCustomIcon || status.isPinnedToSystemIcon
    }

    private func chooseFile(for app: AppInfo) {
        let panel = NSOpenPanel()
        // `.image` covers everything ImageIO decodes; PDF is accepted separately
        // because Core Graphics renders it natively (`UNJAILED.md §6.1`). The real
        // gate is `IconImageValidator`, which reads the decoded data rather than
        // trusting the extension.
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        apply(store.setCustomIcon(from: url, forBundleID: app.bundleIdentifier), for: app)
    }

    /// Takes on a dragged or pasted URL: a file is imported directly, an http(s)
    /// link is fetched first.
    private func adopt(_ url: URL, for app: AppInfo) {
        guard !url.isFileURL else {
            apply(store.setCustomIcon(from: url, forBundleID: app.bundleIdentifier), for: app)
            return
        }
        guard RemoteIconFetcher.isFetchable(url) else {
            problem = "That link isn't something Zap can fetch an image from."
            return
        }

        let bundleID = app.bundleIdentifier
        fetching.insert(bundleID)
        Task {
            let fetched = await RemoteIconFetcher.fetch(url)
            await MainActor.run {
                fetching.remove(bundleID)
                switch fetched {
                case .failure(let error):
                    problem = error.message
                case .success(let data):
                    switch IconImageValidator.decode(data: data) {
                    case .failure(let rejection):
                        problem = rejection.message
                    case .success(let image):
                        // Provenance is captured at save time, not display time
                        // (§5.4) — the link the user dragged from is the credit.
                        apply(store.setCustomIcon(image, forBundleID: bundleID,
                                                  origin: .search,
                                                  creditURL: url.absoluteString,
                                                  provider: "web"),
                              for: app)
                    }
                }
            }
        }
    }

    /// Shared outcome handling for every ingestion path.
    private func apply(_ result: Result<IconManifest.Entry, IconImageValidator.Rejection>,
                       for app: AppInfo) {
        switch result {
        case .failure(let rejection):
            problem = rejection.message
        case .success:
            problem = nil
            // A custom icon that the current mode would ignore is a trap; adopt
            // the mode that honours it.
            if !preferences.iconSourceMode.usesCustomIcons {
                preferences.iconSourceMode = .originalPlusCustom
            }
            refresh(app.bundleIdentifier)
        }
    }

    private func useOriginalArtwork(for app: AppInfo) {
        store.clearOverride(forBundleID: app.bundleIdentifier)
        problem = nil
        refresh(app.bundleIdentifier)
    }

    private func useSystemIcon(for app: AppInfo) {
        store.pinToSystemIcon(forBundleID: app.bundleIdentifier)
        problem = nil
        refresh(app.bundleIdentifier)
    }

    private func resetAll() {
        store.removeAll()
        problem = nil
        iconResolver.invalidate()
        reloadStatuses()
    }

    /// Re-resolves one app and re-reads its status.
    private func refresh(_ bundleID: String) {
        iconResolver.invalidate(bundleID: bundleID)
        reloadStatuses()
    }

    // MARK: Loading

    private func reload() {
        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))

        // Apps with a stored override that aren't running right now would
        // otherwise be unreachable — the user could never undo them.
        let runningIDs = Set(running.map(\.bundleIdentifier))
        let offline = store.manifest.entries.keys
            .filter { !runningIDs.contains($0) }
            .map { bundleID in
                AppInfo(bundleIdentifier: bundleID,
                        name: Self.displayName(forBundleID: bundleID) ?? bundleID,
                        processIdentifier: -1,
                        icon: Self.icon(forBundleID: bundleID))
            }

        apps = (running + offline)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        reloadStatuses()
    }

    /// Statuses decode bundle artwork, so they're gathered off the main thread.
    private func reloadStatuses() {
        iconResolver.statuses(forBundleIDs: apps.map(\.bundleIdentifier)) { resolved in
            statuses = resolved
        }
    }

    /// Resolves a human-readable name for an installed (but not running) app.
    private static func displayName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        let nsName = name as NSString
        return nsName.pathExtension == "app" ? nsName.deletingPathExtension : name
    }

    /// Resolves the icon for an installed (but not running) app.
    private static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
