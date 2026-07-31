import Foundation

/// The on-disk index of a user's icon overrides (`UNJAILED.md §7`).
///
/// Treated as untrusted input on every load. A manifest can be hand-edited, can
/// arrive inside a shared icon pack, and names files that Zap will go on to read —
/// so `validated()` clamps every number, falls back on every unparseable enum, and
/// drops any entry whose file name could escape the icons directory. This mirrors
/// what `AppearancePreset.apply(to:)` does for imported themes.
struct IconManifest: Codable, Equatable {

    /// Bumped only for a breaking layout change; unknown future versions still load
    /// entry-by-entry rather than failing wholesale.
    static let currentVersion = 1

    var version: Int
    /// Keyed by bundle identifier.
    var entries: [String: Entry]

    init(version: Int = IconManifest.currentVersion, entries: [String: Entry] = [:]) {
        self.version = version
        self.entries = entries
    }

    /// Where an app's icon came from.
    enum Origin: String, Codable, Equatable, CaseIterable {
        /// A file the user picked.
        case file
        /// A result from an icon search provider (`UNJAILED.md §5.2`).
        case search
        /// The app bundle's own recovered artwork.
        case originalArtwork
        /// Pinned to the system icon — this app opts out of un-jailing.
        case system

        /// Whether an entry with this origin names a file in the icons directory.
        var needsFile: Bool { self != .system }
    }

    /// One app's override. Every field is optional so a malformed or partial
    /// manifest still decodes; `validated()` is what makes it trustworthy.
    struct Entry: Codable, Equatable {
        /// File name only, never a path — resolved against the icons directory and
        /// bounds-checked on load.
        var file: String?
        var source: String?
        var provider: String?
        var credit: String?
        var creditURL: String?
        var license: String?
        var addedAt: Date?
        /// Per-app override of the global bleed (`UNJAILED.md §8.3`); phase 2 reads it.
        var bleed: Double?
        /// Per-app override of "trim transparent edges".
        var trim: Bool?

        init(file: String? = nil, source: String? = nil, provider: String? = nil,
             credit: String? = nil, creditURL: String? = nil, license: String? = nil,
             addedAt: Date? = nil, bleed: Double? = nil, trim: Bool? = nil) {
            self.file = file
            self.source = source
            self.provider = provider
            self.credit = credit
            self.creditURL = creditURL
            self.license = license
            self.addedAt = addedAt
            self.bleed = bleed
            self.trim = trim
        }

        /// The parsed origin, falling back to `.file` for anything unrecognised.
        var origin: Origin {
            source.flatMap(Origin.init(rawValue:)) ?? .file
        }
    }

    // MARK: Validation

    /// The widest bleed a per-app override may request, matching the global
    /// setting's range in `UNJAILED.md §7`.
    static let maximumBleed = 0.15

    /// Returns a copy safe to act on: unparseable origins normalised, numbers
    /// clamped, and every entry dropped whose file name is missing, unsafe, or
    /// not a PNG.
    func validated() -> IconManifest {
        var safe: [String: Entry] = [:]
        for (bundleID, entry) in entries {
            guard Self.isPlausibleBundleID(bundleID) else { continue }

            let origin = entry.origin
            if origin.needsFile {
                guard let file = entry.file, Self.isSafeFileName(file) else { continue }
                safe[bundleID] = Self.clamped(entry, origin: origin, file: file)
            } else {
                // A system pin names no file, so drop any it happens to carry.
                safe[bundleID] = Self.clamped(entry, origin: origin, file: nil)
            }
        }
        return IconManifest(version: Self.currentVersion, entries: safe)
    }

    private static func clamped(_ entry: Entry, origin: Origin, file: String?) -> Entry {
        var result = entry
        result.file = file
        result.source = origin.rawValue
        result.bleed = entry.bleed.flatMap { value in
            value.isFinite ? Swift.min(Swift.max(value, 0), maximumBleed) : nil
        }
        return result
    }

    /// Whether `name` is a bare file name that cannot escape the icons directory.
    ///
    /// Rejects path separators, relative components, hidden files and anything
    /// that isn't a PNG — Zap only ever writes PNGs there, so an entry naming
    /// something else was not written by Zap.
    static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        guard !name.hasPrefix(".") else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains(":") else { return false }
        guard !name.contains("\0"), !name.contains("..") else { return false }
        guard (name as NSString).pathComponents.count == 1 else { return false }
        return (name as NSString).pathExtension.lowercased() == "png"
    }

    /// A light sanity check on a manifest key. Bundle identifiers are reverse-DNS
    /// in practice; this only refuses the ones that could not name a real app.
    static func isPlausibleBundleID(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty, bundleID.count <= 255 else { return false }
        return !bundleID.contains("\0")
    }

    /// The file name Zap writes for `bundleID`, with every character outside a
    /// conservative allow-list replaced. Bundle identifiers come from whatever
    /// bundle happens to be installed, so the name is generated rather than
    /// trusted; the result always satisfies `isSafeFileName(_:)`.
    static func fileName(forBundleID bundleID: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        var stem = String(bundleID.prefix(200).map { allowed.contains($0) ? $0 : "_" })

        // Dots survive so the common case reads as the identifier itself
        // (`com.apple.Safari.png`), but never as a relative component, a leading
        // dot, or a trailing one — a trailing dot would meet the ".png" suffix and
        // make a ".." that this function's own safety check rejects. Each pass
        // strictly shortens the string, so this terminates.
        while stem.contains("..") { stem = stem.replacingOccurrences(of: "..", with: "_") }
        while stem.hasPrefix(".") { stem.removeFirst() }
        while stem.hasSuffix(".") { stem.removeLast() }
        if stem.isEmpty { stem = "icon" }

        // Sanitising can map two different identifiers onto one stem, which would
        // show one app's icon for another. A short digest keeps them apart, and
        // only appears when sanitising actually changed something.
        if stem != bundleID { stem += "-\(shortDigest(of: bundleID))" }

        return "\(stem).png"
    }

    /// A stable 32-bit FNV-1a digest, base-36.
    ///
    /// Deliberately not `hashValue`: Swift seeds that per process, so it would
    /// name the same app's icon differently on every launch.
    static func shortDigest(of string: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(hash, radix: 36)
    }

    /// Resolves `file` inside `directory`, returning `nil` unless the result really
    /// lands inside it. The name check alone is not enough: `directory` itself may
    /// contain symlinks, so the resolved paths are compared.
    static func resolvedURL(forFile file: String, in directory: URL) -> URL? {
        guard isSafeFileName(file) else { return nil }
        let candidate = directory.appendingPathComponent(file)
        let resolvedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedCandidate.hasPrefix(resolvedDirectory + "/") else { return nil }
        return candidate
    }
}
