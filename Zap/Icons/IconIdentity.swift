import Foundation

/// How Zap tells one app from another when it stores an icon for it.
///
/// The bundle identifier is the obvious key, and was the only one for a while. It
/// is not unique. Site-specific-browser wrappers — Coherence, Unite, and the
/// Chrome/Electron family generally — ship one app bundle per site, and every one
/// of them reports the browser's identifier. Three separate apps in
/// `/Applications`, each with its own name and its own artwork, all of them
/// `com.google.Chrome`:
///
/// ```
/// /Applications/Claude ★.app/Contents/Resources/Claude ★.app
/// /Applications/CodeNomad.app/Contents/Resources/CodeNomad.app
/// /Applications/CodeNomad Dev.app/Contents/Resources/CodeNomad Dev.app
/// ```
///
/// Keyed by identifier, giving one of those a custom icon gave it to all three.
///
/// The bundle path is unique where the identifier isn't, so that is what a new
/// override is written under. `legacyKey` is what keeps every icon set before this
/// change working — a lookup tries the path and then the identifier, so nothing
/// needed migrating and no entry was dropped.
///
/// The cost, stated plainly: an app that *moves* loses its icon, where an
/// identifier would have followed it. Updating an app in place doesn't move it,
/// re-picking the file fixes it, and `UNJAILED.md §7`'s "survives updates" promise
/// still holds — what it gives up is surviving a drag to another folder.
struct IconIdentity: Equatable, Hashable {

    let bundleIdentifier: String

    /// Where the app lives, when Zap knows. `nil` for an app known only by
    /// identifier — a manifest entry whose app isn't running, say.
    let bundleURL: URL?

    init(bundleIdentifier: String, bundleURL: URL? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
    }

    /// Identity is the storage key's, not the stored properties'.
    ///
    /// `IconResolver` caches on this type, so two references to one app have to
    /// land on the same entry. Synthesised conformance would compare the raw URL,
    /// which `storageKey` standardises — leaving `/Applications/./Safari.app` and
    /// `/Applications/Safari.app` as two apps to the cache and one to the store:
    /// a resolve done twice, and an `invalidate` that clears only one of them.
    static func == (lhs: IconIdentity, rhs: IconIdentity) -> Bool {
        lhs.storageKey == rhs.storageKey
    }

    /// Must stay in step with `==` above — and must be the instance method, since
    /// a `static` one would leave `Hashable` synthesised and equal values hashing
    /// apart, which compiles and is worse than either choice made deliberately.
    func hash(into hasher: inout Hasher) {
        hasher.combine(storageKey)
    }

    /// What a new override is stored under.
    var storageKey: String {
        guard let bundleURL else { return bundleIdentifier }
        return bundleURL.standardizedFileURL.path
    }

    /// A key the same app may already be stored under, from before overrides were
    /// keyed by path. `nil` when it would only repeat `storageKey`.
    ///
    /// Note that this reads `bundleIdentifier`, which `==` above does *not*: two
    /// identities equal by path could in principle name different identifiers and
    /// so offer different fallbacks. One app bundle reports one identifier, so
    /// there is no such pair to construct — but a future call site pairing a stale
    /// identifier with a fresh path would be the way to build one.
    var legacyKey: String? {
        storageKey == bundleIdentifier ? nil : bundleIdentifier
    }

    /// Every key this app could be found under, most specific first.
    var lookupKeys: [String] {
        guard let legacyKey else { return [storageKey] }
        return [storageKey, legacyKey]
    }

    /// Whether `key` is a stored bundle path rather than an identifier.
    ///
    /// Settings needs this for the rows it lists straight out of the manifest,
    /// whose apps aren't running: a path names the app well enough to show a name
    /// and an icon for it, where `NSWorkspace`'s identifier lookup would find the
    /// browser the wrapper borrowed its identifier from — or nothing at all.
    static func isPath(_ key: String) -> Bool {
        key.hasPrefix("/")
    }

    /// The app's name as its path tells it, e.g. `Claude ★` — for the same rows.
    static func displayName(forPathKey key: String) -> String? {
        guard isPath(key) else { return nil }
        let name = URL(fileURLWithPath: key).deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : name
    }
}
