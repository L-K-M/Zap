import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Lets the user choose where the switcher's icons come from, and override any
/// single app's (`UNJAILED.md §8.4`).
struct IconsView: View {
    @ObservedObject var preferences: Preferences
    let iconResolver: IconResolver

    @State private var apps: [AppInfo] = []
    /// Keyed by `IconIdentity.storageKey` throughout, not by bundle identifier —
    /// several apps can share one identifier (see `IconIdentity`), and keying rows
    /// by it made them highlight, caption and update as a group.
    @State private var statuses: [String: IconArtworkStatus] = [:]
    @State private var search = ""
    @State private var problem: IconProblem?
    /// Key of the row a drag is currently over.
    @State private var dropTarget: String?
    /// Keys with an import in flight, and what the row should say
    /// about it. Reading an SVG stands up a web view, so a local file is no longer
    /// reliably instant either — both paths get a caption.
    @State private var inFlight: [String: String] = [:]
    /// The app whose search sheet is open, if any.
    @State private var searchingApp: AppInfo?
    /// Whether the icon-set manager is open.
    @State private var managingSets = false

    /// The installed icon themes (`UNJAILED.md §5.6`).
    @ObservedObject private var iconSets = IconSetLibrary.shared

    /// Where a search sheet can look, best first.
    ///
    /// Installed sets lead. They are the only providers that can suggest anything
    /// before being asked — their corpus is on disk — so opening the sheet on one
    /// means opening it on a grid of likely icons rather than an empty box. The
    /// remote provider is last and is always there, so the list is never empty.
    ///
    /// State rather than a computed property, and rebuilt only when the installed
    /// sets can have changed: building one reads a directory of several thousand
    /// files, and a computed property here would do that on every redraw of a sheet
    /// that is open.
    ///
    /// Starts with the keyless remote provider (`UNJAILED.md §5.2` conclusion 3)
    /// already in it so it is never empty — the sheet takes the list as given and
    /// shows its first entry, and "no sources at all" is not a state Zap can be in.
    ///
    /// That one instance is also the only one: `refreshProviders` carries it over
    /// rather than building another, so the set metadata behind it is fetched once
    /// per session rather than once per rebuild.
    @State private var searchProviders: [IconSearchProvider] = [IconifyClient()]

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
        .alert(iconProblem: $problem)
        .sheet(item: $searchingApp) { app in
            IconSearchSheet(
                app: app,
                providers: searchProviders,
                preferences: preferences,
                onAdopt: { result, image in
                    searchingApp = nil
                    adopt(result, image: image, for: app)
                },
                onCancel: { searchingApp = nil })
        }
        .sheet(isPresented: $managingSets) {
            IconSetsSheet(library: iconSets, onDone: {
                managingSets = false
                // A set may have been installed or removed; the next search sheet
                // should offer what is actually there.
                refreshProviders()
            })
        }
    }

    /// Rebuilds the provider list from what is installed now, keeping the remote
    /// provider that is already there.
    ///
    /// It is always last — sets lead, and the list is never empty — so `last` is it.
    private func refreshProviders() {
        let remote = searchProviders.last ?? IconifyClient()
        searchProviders = iconSets.installedProviders() + [remote]
    }

    /// Stores a searched-for icon, carrying its credit into the manifest — §5.4
    /// makes attribution a hard requirement, not a display-time nicety.
    private func adopt(_ result: IconSearchResult, image: CGImage, for app: AppInfo) {
        apply(store.setCustomIcon(image, for: app.iconIdentity,
                                  origin: .search,
                                  credit: result.credit,
                                  creditURL: result.creditURL?.absoluteString,
                                  provider: result.providerID,
                                  license: result.license),
              for: app)
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
        IconRow(
            app: app,
            icon: icon(for: app),
            status: rowStatus(for: app),
            hasOverride: hasOverride(app),
            isPinnedToSystemIcon: statuses[app.iconIdentity.storageKey]?.isPinnedToSystemIcon == true,
            isDropTarget: dropTarget == app.iconIdentity.storageKey,
            onChooseFile: { chooseFile(for: app) },
            onSearch: { searchingApp = app },
            onUseOriginalArtwork: { useOriginalArtwork(for: app) },
            onUseSystemIcon: { useSystemIcon(for: app) },
            onDrop: { adopt($0, for: app) },
            onDropTargeted: { targeted in
                if targeted {
                    dropTarget = app.iconIdentity.storageKey
                } else if dropTarget == app.iconIdentity.storageKey {
                    dropTarget = nil
                }
            })
    }

    /// What the row's caption says, including transient states the status fetch
    /// doesn't know about.
    private func rowStatus(for app: AppInfo) -> String {
        if let label = inFlight[app.iconIdentity.storageKey] { return label }
        return statuses[app.iconIdentity.storageKey]?.label ?? "Checking…"
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Reset All Icons", role: .destructive, action: resetAll)
                Spacer()
                Button("Icon Sets…") { managingSets = true }
            }

            Text(iconSets.records.isEmpty
                 ? "Install an icon set for a few thousand app icons to pick from, offline, with matches suggested per app."
                 : "Icon sets are offered in each app's search sheet, with matches suggested for that app.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        iconResolver.icon(for: app.iconIdentity) ?? app.icon
    }

    private func hasOverride(_ app: AppInfo) -> Bool {
        guard let status = statuses[app.iconIdentity.storageKey] else { return false }
        return status.hasCustomIcon || status.isPinnedToSystemIcon
    }

    private func chooseFile(for app: AppInfo) {
        let panel = NSOpenPanel()
        // `.image` covers everything ImageIO decodes *and* SVG, which conforms to
        // `public.image` without ImageIO being able to read a byte of it. PDF is
        // listed separately because Core Graphics renders it natively
        // (`UNJAILED.md §6.1`). The real gate is `IconImport`, which decides from
        // the bytes rather than trusting any of this.
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        importFile(url, for: app)
    }

    /// Takes on a dragged or pasted URL: a file is imported directly, an http(s)
    /// link is fetched first. Returns whether the drop was accepted — refusing it
    /// makes the drag snap back, which is the platform's own way of saying "not
    /// this, not now", and is better than silently dropping it on the floor.
    @discardableResult
    private func adopt(_ url: URL, for app: AppInfo) -> Bool {
        guard !url.isFileURL else {
            return importFile(url, for: app)
        }
        guard RemoteIconFetcher.isFetchable(url) else {
            problem = .unfetchableLink(app: app)
            return false
        }
        guard claim(app, saying: "Downloading…") else { return false }

        let key = app.iconIdentity.storageKey
        Task {
            let fetched = await fetchedImage(from: url, for: app)
            await MainActor.run {
                inFlight[key] = nil
                switch fetched {
                case .failure(let failure):
                    problem = failure
                case .success(let image):
                    // Provenance is captured at save time, not display time
                    // (§5.4) — the link the user dragged from is the credit.
                    apply(store.setCustomIcon(image, for: app.iconIdentity,
                                              origin: .search,
                                              creditURL: url.absoluteString,
                                              provider: "web"),
                          for: app)
                }
            }
        }
        // Accepted: the download is under way and the row says so.
        return true
    }

    /// Downloads `url` and decodes what comes back. Both halves can fail and they
    /// fail differently — a link that never answered isn't a file Zap turned down —
    /// so each failure arrives already phrased for the alert.
    private func fetchedImage(from url: URL, for app: AppInfo) async -> Result<CGImage, IconProblem> {
        switch await RemoteIconFetcher.fetch(url) {
        case .failure(let error):
            return .failure(.fetchFailed(error.message, app: app))
        case .success(let data):
            // SVG arrives by this route too — it is most of what a browser has to
            // drag — so the bytes go through the same door a chosen file does.
            switch await IconImport.image(from: data) {
            case .failure(let rejection): return .failure(.rejected(rejection, app: app))
            case .success(let image): return .success(image)
            }
        }
    }

    /// Reads a local file and adopts it. Returns whether the file was taken on —
    /// the answer a drop needs, and `true` means "started", not "finished": an SVG
    /// goes through a web view, so the outcome lands later, in the row or an alert.
    @discardableResult
    private func importFile(_ url: URL, for app: AppInfo) -> Bool {
        guard claim(app, saying: "Adding…") else { return false }

        let key = app.iconIdentity.storageKey
        Task {
            let imported = await IconImport.image(contentsOf: url)
            await MainActor.run {
                inFlight[key] = nil
                switch imported {
                case .failure(let rejection):
                    apply(.failure(rejection), for: app)
                case .success(let image):
                    apply(store.setCustomIcon(image, for: app.iconIdentity), for: app)
                }
            }
        }
        return true
    }

    /// Marks `app` as busy, or refuses when it already is.
    ///
    /// One import per app at a time. Two in flight would race: the first to finish
    /// clears the caption for both, and the last to *land* wins the icon, which
    /// need not be the one the user asked for last.
    private func claim(_ app: AppInfo, saying label: String) -> Bool {
        guard inFlight[app.iconIdentity.storageKey] == nil else {
            problem = .alreadyInFlight(app: app)
            return false
        }
        inFlight[app.iconIdentity.storageKey] = label
        return true
    }

    /// Shared outcome handling for every ingestion path.
    ///
    /// Nothing clears `problem` on success: an alert is dismissed by the person
    /// reading it, not by the next thing that happens to go right.
    private func apply(_ result: Result<IconManifest.Entry, IconImageValidator.Rejection>,
                       for app: AppInfo) {
        switch result {
        case .failure(let rejection):
            problem = .rejected(rejection, app: app)
        case .success:
            // A custom icon that the current mode would ignore is a trap; adopt
            // the mode that honours it.
            if !preferences.iconSourceMode.usesCustomIcons {
                preferences.iconSourceMode = .originalPlusCustom
            }
            refresh(app.iconIdentity)
        }
    }

    private func useOriginalArtwork(for app: AppInfo) {
        store.clearOverride(for: app.iconIdentity)
        refresh(app.iconIdentity)
    }

    private func useSystemIcon(for app: AppInfo) {
        store.pinToSystemIcon(for: app.iconIdentity)
        refresh(app.iconIdentity)
    }

    private func resetAll() {
        store.removeAll()
        iconResolver.invalidate()
        reloadStatuses()
    }

    /// Re-resolves one app and re-reads its status.
    private func refresh(_ identity: IconIdentity) {
        iconResolver.invalidate(identity)
        reloadStatuses()
    }

    // MARK: Loading

    private func reload() {
        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))

        // Apps with a stored override that aren't running right now would
        // otherwise be unreachable — the user could never undo them.
        let offline = Self.offlineKeys(manifestKeys: Array(store.manifest.entries.keys),
                                       running: running)
            .map(Self.offlineApp(forKey:))

        apps = (running + offline)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        reloadStatuses()
        refreshProviders()
    }

    /// Statuses decode bundle artwork, so they're gathered off the main thread.
    private func reloadStatuses() {
        IconArtworkStatus.load(for: apps.map(\.iconIdentity), store: store) { resolved in
            statuses = resolved
        }
    }

    /// Which manifest entries still need a row of their own.
    ///
    /// Matched against **every** key a running app could be stored under, not just
    /// the one it would be written to now. An icon set before overrides were keyed
    /// by path is still filed under the bundle identifier, and comparing only the
    /// path meant that entry looked like a different, absent app — so a second row
    /// appeared for something already in the list, and acting on it raced the real
    /// row. Exactly the upgrade this key change is supposed to be invisible to.
    static func offlineKeys(manifestKeys: [String], running: [AppInfo]) -> [String] {
        let covered = Set(running.flatMap { $0.iconIdentity.lookupKeys })
        return manifestKeys.filter { !covered.contains($0) }
    }

    /// Builds a row for a manifest entry whose app isn't running.
    ///
    /// A path key names the app well enough on its own — the bundle is right there,
    /// so Finder can supply the icon and the file name supplies the label. Asking
    /// `NSWorkspace` about it by identifier would find the browser a wrapper
    /// borrowed its identifier from, and label three different apps "Google Chrome".
    ///
    /// The path goes in `bundleIdentifier` deliberately, and it is the one place in
    /// the app where that field isn't reverse-DNS. Reading the real identifier out
    /// of the bundle would be more honest and would break these rows: `AppInfo.id`
    /// is `bundleIdentifier` plus the pid, every offline row shares the pid `-1`,
    /// and three wrappers all answering `com.google.Chrome` would collide into one
    /// `List` identity. The path keeps them distinct, which is the whole point of
    /// the row. Nothing downstream of here reads the field expecting an identifier
    /// — `iconIdentity` is what the store and resolver use, and it round-trips.
    private static func offlineApp(forKey key: String) -> AppInfo {
        guard IconIdentity.isPath(key) else {
            return AppInfo(bundleIdentifier: key,
                           name: displayName(forBundleID: key) ?? key,
                           processIdentifier: -1,
                           icon: icon(forBundleID: key))
        }
        return AppInfo(bundleIdentifier: key,
                       name: IconIdentity.displayName(forPathKey: key) ?? key,
                       processIdentifier: -1,
                       icon: NSWorkspace.shared.icon(forFile: key),
                       bundleURL: URL(fileURLWithPath: key))
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
