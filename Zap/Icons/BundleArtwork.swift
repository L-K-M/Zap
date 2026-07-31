import AppKit
import CoreGraphics
import Foundation

/// Reads an app's own, unmasked icon artwork out of its bundle
/// (`UNJAILED.md §4.1`) — rung 2 of the resolution ladder, and the one that needs
/// no network, no configuration and no user decisions.
///
/// Read-only throughout. Every other de-jailer works by writing into the target
/// app (an `Icon\r` file, an extended attribute, a resource fork), which can't
/// touch system or App Store apps, reverts on update, and leaves detritus that
/// trips `codesign`. Zap draws its own icon row, so it substitutes at draw time
/// instead and never writes into a bundle it doesn't own. Reading is not blocked
/// by SIP — SIP stops *writes* to `/System` — so Finder's and Safari's artwork is
/// as readable as anyone else's.
enum BundleArtwork {

    /// Where a bundle says its artwork lives.
    enum Source: Equatable {
        /// A file in `Contents/Resources` — `.icns`, or a loose PNG.
        case file(URL)
        /// A name to look up in the bundle's compiled asset catalog.
        case assetCatalog(String)
    }

    // MARK: Resolution

    /// The artwork sources declared by the bundle at `bundleURL`, in the order
    /// they should be tried (`UNJAILED.md §4.1`):
    ///
    /// 1. `CFBundleIconFile` — the classic `.icns` in `Contents/Resources`
    /// 2. `CFBundleIconName` — compiled into `Assets.car`
    /// 3. `CFBundleIconFiles` — loose PNGs (Catalyst / iOS-on-Silicon)
    /// 4. any `.icns` in `Contents/Resources`, largest first
    ///
    /// File sources are only returned when the file actually exists, so callers
    /// can try them in order without re-checking.
    static func sources(forBundleAt bundleURL: URL,
                        fileManager: FileManager = .default) -> [Source] {
        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let info = infoDictionary(forBundleAt: bundleURL)

        var sources: [Source] = []
        var seenFiles: Set<String> = []

        func appendFile(named name: String, defaultExtension: String) {
            for url in candidateURLs(forResourceNamed: name, in: resources,
                                     defaultExtension: defaultExtension) {
                guard fileManager.fileExists(atPath: url.path) else { continue }
                guard seenFiles.insert(url.standardizedFileURL.path).inserted else { continue }
                sources.append(.file(url))
            }
        }

        // 1. CFBundleIconFile. The extension is routinely omitted — "AppIcon"
        //    rather than "AppIcon.icns" — so both spellings are tried.
        if let iconFile = info["CFBundleIconFile"] as? String, !iconFile.isEmpty {
            appendFile(named: iconFile, defaultExtension: "icns")
        }

        // 2. CFBundleIconName, compiled into Assets.car.
        if let iconName = info["CFBundleIconName"] as? String, !iconName.isEmpty {
            sources.append(.assetCatalog(iconName))
        }

        // 3. CFBundleIconFiles, loose files without extensions.
        if let iconFiles = info["CFBundleIconFiles"] as? [String] {
            for name in iconFiles where !name.isEmpty {
                appendFile(named: name, defaultExtension: "png")
            }
        }

        // 4. Any other `.icns` sitting in Resources, largest file first. Appended
        //    unconditionally rather than only when nothing was declared, so a
        //    declared icon that turns out not to decode still has a fallback.
        for url in loose(icnsIn: resources, fileManager: fileManager) {
            guard seenFiles.insert(url.standardizedFileURL.path).inserted else { continue }
            sources.append(.file(url))
        }

        return sources
    }

    /// The bundle's `Info.plist`, read directly rather than through `Bundle` so a
    /// malformed or missing plist is just an empty result.
    static func infoDictionary(forBundleAt bundleURL: URL) -> [String: Any] {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return [:] }
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return (plist as? [String: Any]) ?? [:]
    }

    /// The name/extension spellings to try for a declared resource name.
    static func candidateURLs(forResourceNamed name: String, in resources: URL,
                              defaultExtension: String) -> [URL] {
        // Guard against a bundle declaring a path rather than a name; only the
        // last component is ever used.
        let leaf = (name as NSString).lastPathComponent
        guard !leaf.isEmpty, leaf != ".", leaf != ".." else { return [] }

        var urls = [resources.appendingPathComponent(leaf)]
        if (leaf as NSString).pathExtension.isEmpty {
            urls.append(resources.appendingPathComponent("\(leaf).\(defaultExtension)"))
        }
        return urls
    }

    /// Every `.icns` directly inside `resources`, largest file first.
    private static func loose(icnsIn resources: URL, fileManager: FileManager) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: resources, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return [] }

        return contents
            .filter { $0.pathExtension.lowercased() == "icns" }
            .sorted { left, right in
                let leftSize = (try? left.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let rightSize = (try? right.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if leftSize != rightSize { return leftSize > rightSize }
                // Deterministic order when sizes tie, so the result is stable.
                return left.lastPathComponent < right.lastPathComponent
            }
    }

    // MARK: Loading

    /// The best artwork available for the bundle at `bundleURL`, bounded to the
    /// stored master size, or `nil` when nothing readable is declared.
    static func image(forBundleAt bundleURL: URL) -> CGImage? {
        for source in sources(forBundleAt: bundleURL) {
            if let image = load(source, bundleURL: bundleURL) { return image }
        }
        return nil
    }

    /// The best artwork available for an installed app, located via `NSWorkspace`.
    static func image(forBundleID bundleID: String) -> CGImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return image(forBundleAt: url)
    }

    /// Loads one source, or `nil` when it can't be read.
    static func load(_ source: Source, bundleURL: URL) -> CGImage? {
        switch source {
        case .file(let url):
            // The same gate a user-chosen file goes through: bundles are not
            // hostile, but the size and decode bounds are worth having anyway.
            switch IconImageValidator.decode(contentsOf: url) {
            case .success(let image): return image
            case .failure: return nil
            }

        case .assetCatalog(let name):
            return assetCatalogImage(named: name, bundleURL: bundleURL)
        }
    }

    /// Reads a named image out of a *foreign* bundle's compiled asset catalog.
    ///
    /// `Bundle.image(forResource:)` is documented to work on any bundle, not just
    /// `Bundle.main`, and unlike `NSImage(named:)` it doesn't consult the shared
    /// image cache — which makes it the public route into another app's
    /// `Assets.car`, with no CoreUI SPI and no `assetutil` subprocess.
    ///
    /// **Unverified on Tahoe.** This is the load-bearing claim in `UNJAILED.md
    /// §4.1`/§12 and it was written without a machine to check it on. Tahoe-era
    /// apps also compile a layered Icon Composer `.icon` into the catalog, and
    /// whether this flattens it, returns one variant, or returns nothing is
    /// unknown. A `nil` here is deliberately not an error: it just falls through
    /// to the next source, and then to the system icon.
    private static func assetCatalogImage(named name: String, bundleURL: URL) -> CGImage? {
        guard let bundle = Bundle(url: bundleURL),
              let image = bundle.image(forResource: name) else { return nil }

        // Ask for the master size so `NSImage` picks its highest-resolution
        // representation rather than the one matching its nominal point size.
        var proposed = CGRect(x: 0, y: 0,
                              width: CGFloat(IconImageValidator.Limits.masterLongestEdge),
                              height: CGFloat(IconImageValidator.Limits.masterLongestEdge))
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }
}
