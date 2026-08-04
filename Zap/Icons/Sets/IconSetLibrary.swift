import Foundation

/// Owns `~/Library/Application Support/Zap/IconSets` — the themes the user has
/// installed, and what Zap knows about each one.
///
/// Application Support rather than Caches, unlike `IconRenderCache`: a theme the
/// user installed is a choice they made, it is ~4 MB, and re-making it means a
/// 31 MB download. The renders derived *from* it stay in Caches, where the system
/// is welcome to reclaim them.
///
/// Observable because the Settings UI is the only thing that drives it: installing
/// is a button, and the button has to say "Downloading…", then "4,213 icons", then
/// let you remove it again. Driven from the main thread like `Preferences`, with
/// `install` hopping back to it around the download and unpack — which are the only
/// things here that take long enough to be worth being elsewhere.
final class IconSetLibrary: ObservableObject {

    static let shared = IconSetLibrary()

    let directory: URL

    /// What is installed, keyed by `IconSet.id`.
    @Published private(set) var records: [String: Record]

    /// Which set is being downloaded or unpacked right now, if any. One at a time:
    /// each install is tens of megabytes and a `tar`, and two at once buys nothing.
    @Published private(set) var installing: String?

    private static let recordsFileName = "sets.json"

    init(directory: URL = IconSetLibrary.defaultDirectory()) {
        self.directory = directory
        self.records = Self.loadRecords(from: directory.appendingPathComponent(Self.recordsFileName))
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Zap/IconSets", isDirectory: true)
    }

    /// One installed theme, as recorded on disk.
    struct Record: Codable, Equatable {
        let id: String
        let installedAt: Date
        let iconCount: Int
        /// The archive's `ETag` at install time — what makes the next update check
        /// a conditional request rather than a re-download.
        let etag: String?
    }

    // MARK: Where a set lives

    /// Set identifiers are Zap's own, from a compile-time catalogue, so they can't
    /// arrive hostile. Checked anyway, because this one builds a path: the rule is
    /// stated where the path is made rather than assumed from where the id came
    /// from, and `IconSetCatalogueTests` holds the catalogue to it.
    static func isSafeSetID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        return id.allSatisfy { $0.isASCII && ($0.isLowercase && $0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// Where `id`'s icons live, or `nil` if that identifier can't name a directory.
    func directory(forSetID id: String) -> URL? {
        guard Self.isSafeSetID(id) else { return nil }
        return directory.appendingPathComponent(id, isDirectory: true)
    }

    func isInstalled(_ set: IconSet) -> Bool { records[set.id] != nil }

    func record(for set: IconSet) -> Record? { records[set.id] }

    // MARK: Installing

    /// Downloads and unpacks `set`, replacing any copy already installed.
    ///
    /// Also the update path: an installed set passes its `ETag` along, so a theme
    /// that hasn't moved answers 304 and nothing is downloaded.
    ///
    /// `IconSetInstaller.install` is a plain `async` function on no actor, so the
    /// download and the `tar` run off the main thread; everything that publishes is
    /// hopped back onto it explicitly.
    func install(_ set: IconSet, session: URLSession = .shared)
    async -> Result<IconSetInstaller.Outcome, IconSetInstaller.InstallError> {
        guard let destination = directory(forSetID: set.id) else { return .failure(.badURL) }

        let previousETag = records[set.id]?.etag
        await MainActor.run { installing = set.id }

        let outcome = await IconSetInstaller.install(set, into: destination,
                                                    ifNoneMatch: previousETag,
                                                    session: session)
        await MainActor.run {
            installing = nil
            if case .success(.installed(let installation)) = outcome {
                records[set.id] = Record(id: set.id, installedAt: Date(),
                                         iconCount: installation.iconCount,
                                         etag: installation.etag)
                saveRecords()
            }
        }
        return outcome
    }

    /// Deletes an installed set's icons and forgets it.
    ///
    /// Icons already adopted from it are untouched — they were re-encoded into
    /// Zap's own PNGs at adoption time (`IconStore`), so nothing here is load-bearing
    /// for an icon the user is already using.
    func remove(_ set: IconSet) {
        if let destination = directory(forSetID: set.id) {
            try? FileManager.default.removeItem(at: destination)
        }
        records[set.id] = nil
        saveRecords()
    }

    // MARK: Searching

    /// A search provider over one installed set, or `nil` when it isn't installed
    /// (or its directory has been emptied behind Zap's back).
    ///
    /// The icon names are read here, once, and handed to the provider as a value.
    /// Searching then touches no disk at all — which is what lets a set be searched
    /// as fast as it can be typed at, and what keeps `IconSearchProvider`'s async
    /// surface honest about doing nothing remote.
    func provider(for set: IconSet) -> IconSetProvider? {
        guard records[set.id] != nil, let destination = directory(forSetID: set.id) else { return nil }
        let names = IconSetInstaller.installedIconNames(in: destination)
        guard !names.isEmpty else { return nil }
        return IconSetProvider(set: set, directory: destination, iconNames: names)
    }

    /// Providers for every installed set, in catalogue order.
    func installedProviders() -> [IconSetProvider] {
        IconSetCatalogue.all.compactMap { provider(for: $0) }
    }

    // MARK: Persistence

    private func saveRecords() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: directory.appendingPathComponent(Self.recordsFileName), options: .atomic)
        } catch {
            NSLog("Zap: couldn't save the icon set index: %@", error.localizedDescription)
        }
    }

    /// Reads the index, dropping anything it can't vouch for.
    ///
    /// A record for a set no longer in the catalogue is dropped rather than kept:
    /// nothing can search it, so it would only be a row that says a theme is
    /// installed and offers nothing to do with it.
    private static func loadRecords(from url: URL) -> [String: Record] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return decoded.filter { IconSetCatalogue.set(withID: $0.key) != nil && isSafeSetID($0.key) }
    }
}
