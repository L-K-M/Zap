import CoreGraphics
import CryptoKit
import Foundation

/// Keeps rendered SVG on disk so the same markup is never rasterised twice.
///
/// Rasterising is the most expensive thing in the feature and got twice as
/// expensive when transparency started coming from two renders instead of one
/// (`SVGRasterizer`). The work is also repeated far more than it looks: searching
/// the same word twice re-renders the same two dozen icons, and every icon set
/// worth browsing will be browsed more than once.
///
/// Content-addressed rather than keyed by where the bytes came from, because the
/// same artwork arrives by several routes — a file the user picked, a link dragged
/// from a browser, a search result — and none of them says anything the SHA of the
/// markup doesn't say better. Two apps given the same icon render it once.
///
/// What lands on disk is Zap's own PNG output, exactly as in `IconStore`, so
/// nothing of the source container survives here either (`UNJAILED.md §6.4`) —
/// but it lives in `~/Library/Caches` rather than beside the icons, because
/// everything in it can be made again and a stored icon cannot.
struct IconRenderCache {

    static let shared = IconRenderCache()

    let directory: URL

    /// How many renders to keep.
    ///
    /// Most entries are 128 px previews and cost a few KB; the rest are 1024 px
    /// masters, which for flat icon artwork land somewhere in the hundreds of KB.
    /// So a few hundred entries is tens of megabytes at worst, not the single digits
    /// this comment used to claim — still small next to what re-rendering them
    /// costs, and bounded so a long browsing session can't grow without limit.
    let maximumEntries: Int

    init(directory: URL = IconRenderCache.defaultDirectory(), maximumEntries: Int = 256) {
        self.directory = directory
        self.maximumEntries = maximumEntries
    }

    /// `~/Library/Caches`, not Application Support next to the icons themselves.
    ///
    /// The two directories mean different things and this is the difference: a
    /// stored icon is the user's choice and cannot be re-derived — the SVG it came
    /// from may be long gone — while everything here is reproducible from markup
    /// Zap will fetch again anyway. So this doesn't belong in a backup, and the
    /// system is welcome to reclaim it under disk pressure. A purged cache is a
    /// slow render, which is the same thing a miss already is.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Zap/RenderCache", isDirectory: true)
    }

    // MARK: Key

    /// The cache key for some markup at a size: a digest of the bytes, and the size
    /// they were rendered at.
    ///
    /// The size is part of the key rather than something to resample from, because
    /// the two sizes in use are a 128 px preview and a 1024 px master — resampling
    /// the preview up to a master would hand back something four times softer than
    /// what was asked for, which is the sort of saving nobody wants.
    static func key(for data: Data, side: Int) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(digest)-\(side).png"
    }

    // MARK: Reading and writing

    /// The stored render, or `nil` for a miss. A miss is always safe — the caller
    /// renders and stores.
    func image(for data: Data, side: Int) -> CGImage? {
        guard let url = url(for: data, side: side),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        switch IconImageValidator.decode(contentsOf: url) {
        case .success(let image):
            return image
        case .failure:
            // Unreadable means truncated or corrupt, not malicious — this is Zap's
            // own output. Drop it so the next render replaces it.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Stores a render. Failures are silent on purpose: a cache that can't write is
    /// a slow cache, not a broken feature, and the caller already has the image.
    func store(_ image: CGImage, for data: Data, side: Int) {
        guard let url = url(for: data, side: side) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Zap: couldn't create the render cache directory: %@", error.localizedDescription)
            return
        }
        guard case .success = IconImageValidator.writePNG(image, to: url) else { return }
        prune()
    }

    /// Deletes everything. For a "clear cached renders" affordance, and for tests.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Private

    private func url(for data: Data, side: Int) -> URL? {
        // Bounds-checked the same way stored icons are: the name is generated from
        // a digest, so it cannot escape, and this says so rather than assuming it.
        IconManifest.resolvedURL(forFile: Self.key(for: data, side: side), in: directory)
    }

    /// Keeps the newest `maximumEntries` and drops the rest.
    ///
    /// By modification date, which for a cache written once per render is also
    /// least-recently-*made*. Not least-recently-used — tracking that would mean
    /// writing to disk on every read, which is most of what the cache exists to
    /// avoid.
    private func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]),
              entries.count > maximumEntries else { return }

        let byAge = entries.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return leftDate > rightDate
        }
        for stale in byAge.dropFirst(maximumEntries) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
