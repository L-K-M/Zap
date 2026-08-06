import AppKit
import PictKit
import SwiftUI

/// Where the switcher's icons come from, and what each app is currently drawn with.
///
/// **This tab used to be the editor.** Choosing a file, searching providers,
/// downloading icon themes and applying one wholesale all lived here, and all of it
/// now lives in Pict. What is left is the read side: the setting that decides which
/// rung of the ladder Zap draws from, what each app resolves to today, and the two
/// verbs that need no image handling at all.
///
/// The reason for the split is not tidiness. Ingestion meant decoding untrusted
/// images, standing up a `WKWebView` over fetched markup and spawning `tar` — in a
/// process that holds an Accessibility event tap and can never be sandboxed. Pict
/// needs no permissions at all, so that work belongs there.
struct IconsView: View {

    @ObservedObject var preferences: Preferences
    let icons: ZapIcons

    @State private var apps: [AppInfo] = []
    /// Keyed by the store's serialised key, which is what rows are identified by.
    @State private var statuses: [String: IconArtworkStatus] = [:]
    @State private var search = ""
    /// Where Pict is, when it's installed. `nil` turns the per-row link into a
    /// pointer at where to get it.
    @State private var pictURL: URL?

    private var store: IconStore { icons.store }

    private var filteredApps: [AppInfo] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

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
                .fixedSize(horizontal: false, vertical: true)

            if !IconSourceMode.isSquircleJailed {
                Text("This version of macOS doesn't mask app icons, so there's nothing to un-jail — the original artwork and the system icon are the same picture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        let key = app.storeKey

        return HStack(spacing: 8) {
            // A placeholder rather than a blank tile: the resolver may not have
            // reached this app yet, and an empty square reads as a broken row.
            if let icon = icons.resolver.icon(for: app.iconTarget) ?? app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(key.flatMap { statuses[$0]?.label } ?? "Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                if pictURL != nil {
                    Button("Customise in Pict…") { customise(app) }
                } else {
                    Button("Get Pict to Customise Icons…") { openPictHomepage() }
                }
                Divider()
                Button("Use Original Artwork") { useOriginalArtwork(app) }
                    .disabled(!hasOverride(app))
                Button("Use System Icon") { useSystemIcon(app) }
                    .disabled(isPinned(app))
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Reset All Icons", role: .destructive, action: resetAll)
                Spacer()
                if pictURL != nil {
                    Button("Open Pict") { openPict(selecting: nil) }
                } else {
                    Button("Get Pict…") { openPictHomepage() }
                }
            }

            // Reset All Icons stays here, and it is the one write worth keeping: it
            // needs no image handling, and it is exactly what someone without Pict
            // installed is most likely to want.
            Text(pictURL != nil
                 ? "Icons are shared with Jetty and Top Drawer — a change in any of them shows up here. Pict is where you pick one."
                 : "Zap shows each app's original artwork automatically. To choose your own icons — from a file, a search, or an icon theme — install Pict; icons you set there appear here, in Jetty and in Top Drawer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Lists running apps, plus any app that already has an icon set for it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    // MARK: Actions

    private func hasOverride(_ app: AppInfo) -> Bool {
        guard let key = app.storeKey, let status = statuses[key] else { return false }
        return status.hasCustomIcon || status.isPinnedToSystemIcon
    }

    private func isPinned(_ app: AppInfo) -> Bool {
        guard let key = app.storeKey else { return false }
        return statuses[key]?.isPinnedToSystemIcon == true
    }

    private func useOriginalArtwork(_ app: AppInfo) {
        store.clear(for: app.iconTarget)
        refresh(app)
    }

    /// Pinning writes an entry that names no image, so it needs none of the
    /// ingestion that moved to Pict — which is why this verb can stay.
    private func useSystemIcon(_ app: AppInfo) {
        _ = store.pinToSystemIcon(for: app.iconTarget, writtenBy: "Zap")
        refresh(app)
    }

    private func resetAll() {
        store.removeAll()
        icons.resolver.invalidate()
        reloadStatuses()
    }

    private func refresh(_ app: AppInfo) {
        icons.resolver.invalidate(app.iconTarget)
        reloadStatuses()
    }

    private func customise(_ app: AppInfo) {
        openPict(selecting: app.iconTarget)
    }

    /// Hands the app over to Pict. One-way: nothing waits for a reply, because the
    /// store change is the notification — `ZapIcons` watches for it.
    private func openPict(selecting target: IconTarget?) {
        PictURL.open(selecting: target)
    }

    private func openPictHomepage() {
        guard let url = PictURL.homepage else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Loading

    private func reload() {
        pictURL = PictURL.installedAppURL()

        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))

        // Apps with a stored override that aren't running right now would otherwise
        // be unreachable — the user could never undo them.
        let offline = Self.offlineRows(storeKeys: Array(store.entries.keys), running: running)

        apps = (running + offline)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        reloadStatuses()
    }

    /// Statuses decode bundle artwork, so they're gathered off the main thread.
    private func reloadStatuses() {
        IconArtworkStatus.load(for: apps.map(\.iconTarget), store: store) { resolved in
            statuses = resolved
        }
    }

    /// Which stored entries still need a row of their own.
    ///
    /// Matched against **every** key a running app could be stored under, not just
    /// the one it would be written to now. An icon set before overrides were keyed
    /// by path is still filed under the bundle identifier, and comparing only the
    /// path meant that entry looked like a different, absent app — so a second row
    /// appeared for something already in the list.
    static func offlineRows(storeKeys: [IconEntryKey], running: [AppInfo]) -> [AppInfo] {
        let covered = Set(running.flatMap { app in
            IconEntryKey.lookupLadder(for: app.iconTarget).map(\.serialized)
        })
        return storeKeys
            .filter { !covered.contains($0.serialized) }
            .compactMap(offlineApp(forKey:))
    }

    /// Builds a row for a stored entry whose app isn't running.
    ///
    /// A path key names the app well enough on its own — the bundle is right there,
    /// so Finder can supply the icon and the file name supplies the label. Asking
    /// `NSWorkspace` about it by identifier would find the browser a wrapper
    /// borrowed its identifier from, and label three different apps "Google Chrome".
    ///
    /// Entries for files and links — which Jetty and Top Drawer can write and Zap
    /// cannot — get no row. Zap has nothing to say about them and nowhere to show
    /// them; Pict lists them.
    private static func offlineApp(forKey key: IconEntryKey) -> AppInfo? {
        switch key.kind {
        case .app:
            let url = URL(fileURLWithPath: key.value)
            let stem = url.deletingPathExtension().lastPathComponent
            return AppInfo(bundleIdentifier: key.value,
                           name: stem.isEmpty ? key.value : stem,
                           processIdentifier: -1,
                           icon: NSWorkspace.shared.icon(forFile: key.value),
                           bundleURL: url)
        case .bundleID:
            let located = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key.value)
            return AppInfo(bundleIdentifier: key.value,
                           name: located.map { $0.deletingPathExtension().lastPathComponent }
                               ?? key.value,
                           processIdentifier: -1,
                           icon: located.map { NSWorkspace.shared.icon(forFile: $0.path) })
        case .file, .url:
            return nil
        }
    }
}
