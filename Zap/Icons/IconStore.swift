import CoreGraphics
import Foundation

/// Owns `~/Library/Application Support/Zap/Icons` — the user's icon overrides and
/// the manifest indexing them (`UNJAILED.md §7`).
///
/// `UserDefaults` is a plist read in full at launch, so image blobs don't belong
/// in it. Everything written here is Zap's own PNG output: a chosen file is
/// decoded, bounded and re-encoded rather than copied, so the original container
/// never lands on disk.
///
/// Safe to read from a background queue — `IconResolver` warms its cache off the
/// main thread while Settings mutates the same store.
final class IconStore {

    /// Directory holding `manifest.json` and one PNG per overridden app.
    let directory: URL

    private let fileManager: FileManager
    private let lock = NSLock()
    private var storedManifest: IconManifest

    private static let manifestFileName = "manifest.json"

    init(directory: URL = IconStore.defaultDirectory(), fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.storedManifest = Self.loadManifest(from: directory.appendingPathComponent(Self.manifestFileName))
    }

    /// `~/Library/Application Support/Zap/Icons`, falling back to a temporary
    /// directory if Application Support is somehow unavailable.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Zap/Icons", isDirectory: true)
    }

    // MARK: Reading

    /// The current, validated manifest.
    var manifest: IconManifest {
        lock.lock()
        defer { lock.unlock() }
        return storedManifest
    }

    func entry(forBundleID bundleID: String) -> IconManifest.Entry? {
        lock.lock()
        defer { lock.unlock() }
        return storedManifest.entries[bundleID]
    }

    /// Whether this app is pinned to the system icon, opting out of un-jailing.
    func isPinnedToSystemIcon(_ bundleID: String) -> Bool {
        entry(forBundleID: bundleID)?.origin == .system
    }

    /// The stored override file for `bundleID`, bounds-checked against the icons
    /// directory. `nil` when there is no override or its name can't be trusted.
    func imageURL(forBundleID bundleID: String) -> URL? {
        guard let entry = entry(forBundleID: bundleID),
              entry.origin.needsFile,
              let file = entry.file else { return nil }
        return IconManifest.resolvedURL(forFile: file, in: directory)
    }

    /// Decodes the user's override for `bundleID`, or `nil` when there isn't one.
    func customImage(forBundleID bundleID: String) -> CGImage? {
        guard let url = imageURL(forBundleID: bundleID) else { return nil }
        switch IconImageValidator.decode(contentsOf: url) {
        case .success(let image): return image
        case .failure: return nil
        }
    }

    /// Re-reads the manifest from disk, discarding any in-memory state.
    func reload() {
        let loaded = Self.loadManifest(from: manifestURL)
        lock.lock()
        storedManifest = loaded
        lock.unlock()
    }

    // MARK: Writing

    /// Adopts the image at `url` as `bundleID`'s icon: validated, bounded, and
    /// re-encoded to PNG inside the icons directory.
    @discardableResult
    func setCustomIcon(from url: URL, forBundleID bundleID: String,
                       origin: IconManifest.Origin = .file,
                       credit: String? = nil, creditURL: String? = nil,
                       provider: String? = nil, license: String? = nil,
                       now: Date = Date()) -> Result<IconManifest.Entry, IconImageValidator.Rejection> {
        switch IconImageValidator.decode(contentsOf: url) {
        case .failure(let rejection):
            return .failure(rejection)
        case .success(let image):
            return setCustomIcon(image, forBundleID: bundleID, origin: origin, credit: credit,
                                 creditURL: creditURL, provider: provider, license: license, now: now)
        }
    }

    /// Adopts an already-decoded image as `bundleID`'s icon.
    @discardableResult
    func setCustomIcon(_ image: CGImage, forBundleID bundleID: String,
                       origin: IconManifest.Origin = .file,
                       credit: String? = nil, creditURL: String? = nil,
                       provider: String? = nil, license: String? = nil,
                       now: Date = Date()) -> Result<IconManifest.Entry, IconImageValidator.Rejection> {
        guard IconManifest.isPlausibleBundleID(bundleID) else { return .failure(.unreadable) }

        let fileName = IconManifest.fileName(forBundleID: bundleID)
        guard let destination = IconManifest.resolvedURL(forFile: fileName, in: directory) else {
            return .failure(.notEncodable)
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Zap: couldn't create the icons directory: \(error.localizedDescription)")
            return .failure(.notEncodable)
        }

        if case .failure(let rejection) = IconImageValidator.writePNG(image, to: destination) {
            return .failure(rejection)
        }

        let entry = IconManifest.Entry(
            file: fileName,
            source: origin.rawValue,
            provider: provider,
            credit: credit,
            creditURL: creditURL,
            license: license,
            addedAt: now)

        update { $0.entries[bundleID] = entry }
        return .success(entry)
    }

    /// Pins `bundleID` to the system icon — no artwork recovery, no override.
    func pinToSystemIcon(forBundleID bundleID: String, now: Date = Date()) {
        guard IconManifest.isPlausibleBundleID(bundleID) else { return }
        removeFile(forBundleID: bundleID)
        update {
            $0.entries[bundleID] = IconManifest.Entry(
                source: IconManifest.Origin.system.rawValue, addedAt: now)
        }
    }

    /// Drops any override or pin for `bundleID`, returning it to the global
    /// setting's behaviour. Deletes the stored PNG too — an undo story that is
    /// just "remove a row", as promised in `UNJAILED.md §1.1`.
    func clearOverride(forBundleID bundleID: String) {
        removeFile(forBundleID: bundleID)
        update { $0.entries[bundleID] = nil }
    }

    /// Drops every override and deletes every stored PNG.
    func removeAll() {
        let bundleIDs = Array(manifest.entries.keys)
        for bundleID in bundleIDs {
            removeFile(forBundleID: bundleID)
        }
        update { $0.entries.removeAll() }
    }

    // MARK: Private

    private var manifestURL: URL {
        directory.appendingPathComponent(Self.manifestFileName)
    }

    private func removeFile(forBundleID bundleID: String) {
        guard let url = imageURL(forBundleID: bundleID) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Applies `change` to the manifest and writes it back out.
    private func update(_ change: (inout IconManifest) -> Void) {
        lock.lock()
        var updated = storedManifest
        change(&updated)
        updated = updated.validated()
        storedManifest = updated
        lock.unlock()
        write(updated)
    }

    private func write(_ manifest: IconManifest) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        } catch {
            NSLog("Zap: couldn't write the icon manifest: \(error.localizedDescription)")
        }
    }

    /// Reads and validates the manifest, falling back to an empty one for a
    /// missing, unreadable or malformed file.
    private static func loadManifest(from url: URL) -> IconManifest {
        guard let data = try? Data(contentsOf: url) else { return IconManifest() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(IconManifest.self, from: data) else {
            NSLog("Zap: the icon manifest couldn't be parsed; starting from an empty one.")
            return IconManifest()
        }
        return manifest.validated()
    }
}
