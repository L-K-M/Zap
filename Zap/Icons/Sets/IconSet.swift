import Foundation

/// One downloadable icon theme, and everything Zap needs to fetch and unpack it.
///
/// Linux desktops have large, coherent, freely licensed icon themes, and
/// `UNJAILED.md §5.6` settles what Zap does with them: fetch and update them
/// itself, let the user pick from one per app, and ship none of them in the binary.
///
/// **The whole archive is downloaded and almost all of it thrown away.** A theme
/// ships every context (apps, places, devices, mimetypes, actions…) at every size,
/// and Zap wants application icons at one size. Papirus is 31 MB compressed and
/// about 4 MB of that is worth keeping. Extracting by glob is what makes that
/// difference, so the download is large and what stays on disk is not.
///
/// Downloading beats indexing, which was the first design. An index needs a
/// listing API, and the obvious one — jsDelivr — refuses Papirus outright at
/// 50 MB, resolves versions from an unsorted list where a 2002 tag can come last,
/// and would still cost a request per icon. A tarball has none of those problems
/// and leaves searching entirely offline afterwards.
struct IconSet: Identifiable, Equatable {

    /// Stable, and what the manifest records as the provider for an adopted icon.
    let id: String
    let name: String

    /// One line on what is actually in this set, shown in the manager.
    ///
    /// Not decoration. These themes differ enormously in what "icon theme" means —
    /// thousands of branded app logos in one, two hundred of a single desktop's own
    /// applications in another, monochrome 16 px glyphs in a third — and a name and
    /// a licence say none of that. Without this, choosing between them means
    /// installing one to find out, and "Adwaita" in particular delivers something
    /// nobody would guess from the word.
    let summary: String

    /// Where it lives. Archives come from `github.com/<owner>/<repository>`, which
    /// is upstream rather than a mirror — Pling hosts Papirus too, but 15 months
    /// behind, with an empty licence field and download links that expire.
    let owner: String
    let repository: String
    /// The branch to archive. A branch rather than a tag so no API call is needed to
    /// find the newest one; freshness comes from re-downloading, and `ETag` says
    /// whether that is worth doing.
    let branch: String

    /// Stated because §5.4 makes attribution the condition for a source existing.
    let license: String
    let licenseURL: URL?
    let homepage: URL?

    /// Which paths inside the archive are worth extracting, as `tar` matches them.
    /// The leading `*` is the archive's own root directory, which carries the commit
    /// or tag in its name and so can't be written out here.
    let archiveGlob: String

    /// How many leading path components `tar` should drop, so the icons land
    /// directly in the set's directory rather than nested under the layout they
    /// happened to have upstream. Must match `archiveGlob`: count its components
    /// up to but excluding the file itself.
    let strippedComponents: Int

    /// `https://github.com/<owner>/<repository>/archive/refs/heads/<branch>.tar.gz`
    var archiveURL: URL? {
        URL(string: "https://github.com/\(owner)/\(repository)/archive/refs/heads/\(branch).tar.gz")
    }

    /// A short line for the picker and for the manifest's credit.
    var attribution: String { "\(name) · \(license)" }
}
