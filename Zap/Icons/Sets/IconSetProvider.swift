import Foundation

/// One installed icon theme, as something the search sheet can search.
///
/// The whole set is on disk (`IconSetLibrary`), so this provider is the odd one
/// out: nothing it does touches the network, and its `disclosure` is `nil` for the
/// same reason. `UNJAILED.md §5.6` asks for the corpus to be local precisely so
/// that searching a theme is free, instant and unobservable — which also makes
/// suggesting matches unconditionally reasonable, where a remote provider has to
/// wait to be asked (§5.5).
///
/// Icon names are held as a value rather than re-read per query. A theme is a few
/// thousand strings; searching them is a scan of memory, and the alternative — a
/// directory listing per keystroke — would be slower and would race the installer.
struct IconSetProvider: IconSearchProvider {

    /// Named `iconSet` rather than `set`: inside a computed property's body the
    /// parser reads a leading `set` as the start of a setter, so `{ iconSet.id }` is a
    /// syntax error rather than a property access.
    let iconSet: IconSet
    /// Where the icons are, as `IconSetLibrary` laid them out.
    let directory: URL
    /// Every icon in the set, without the `.svg`.
    let iconNames: Set<String>

    var id: String { iconSet.id }
    var displayName: String { iconSet.name }
    /// Nothing is sent, so there is nothing to disclose — and a wall saying so
    /// before every first search would be a notice about an event that can't happen.
    var disclosure: String? { nil }

    // MARK: Searching

    func search(query: String, limit: Int) async -> Result<[IconSearchResult], IconSearchError> {
        .success(Self.ranked(query: query, in: iconNames, limit: limit)
            .compactMap(result(forIconName:)))
    }

    /// The set's own guesses for an app, best first (`IconNameGuess`).
    func suggestions(appName: String, bundleIdentifier: String, limit: Int) async -> [IconSearchResult] {
        IconNameGuess.matches(appName: appName, bundleIdentifier: bundleIdentifier,
                              in: iconNames, limit: limit)
            .compactMap { result(forIconName: $0.iconName) }
    }

    /// Ranks `iconNames` against a typed query. Pure, so the ordering is testable
    /// without a theme on disk.
    ///
    /// Three tiers and no fuzziness. A theme's names are already normalised — short,
    /// lowercase, hyphenated — so substring matching finds what is there, and
    /// anything cleverer would mostly reorder near-identical names. Ties break on
    /// length: for `mail`, `mail` should come before `mail-client-list`.
    static func ranked(query: String, in iconNames: Set<String>, limit: Int) -> [String] {
        let needle = IconNameGuess.normalised(query)
        guard !needle.isEmpty, limit > 0 else { return [] }

        var scored: [(name: String, score: Int)] = []
        for name in iconNames {
            let score: Int
            if name == needle { score = 3 }
            else if name.hasPrefix(needle) { score = 2 }
            else if name.contains(needle) { score = 1 }
            else { continue }
            scored.append((name, score))
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.name.count != $1.name.count { return $0.name.count < $1.name.count }
                return $0.name < $1.name
            }
            .prefix(limit)
            .map { $0.name }
    }

    // MARK: Fetching

    func fetchImageData(for result: IconSearchResult) async -> Result<Data, IconSearchError> {
        guard let name = Self.iconName(fromResultID: result.id, setID: iconSet.id),
              iconNames.contains(name),
              let url = fileURL(forIconName: name) else {
            return .failure(.unavailable("That icon isn't in the installed copy of \(iconSet.name)."))
        }

        // Bounded like any other source, even though Zap unpacked this file itself:
        // the limit is about what gets decoded, and the archive it came out of was
        // downloaded (`UNJAILED.md §6.4`).
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= IconImageValidator.Limits.maximumSourceBytes else {
            return .failure(.unavailable("That icon is larger than Zap will read."))
        }
        do {
            return .success(try Data(contentsOf: url))
        } catch {
            return .failure(.unavailable(error.localizedDescription))
        }
    }

    // MARK: Results and paths

    /// A result for one icon, or `nil` when the name can't be resolved to a file
    /// inside the set.
    ///
    /// Optional rather than falling back to the set's directory for `imageURL`. A
    /// result whose artwork can't be located has nothing truthful to put there — the
    /// directory is the parent of every icon in the set, not this one's artwork —
    /// and it would fail in `fetchImageData` anyway, so it is better never offered.
    /// Every caller `compactMap`s, so an unresolvable name drops out of the grid
    /// instead of becoming a cell that can only disappoint.
    func result(forIconName name: String) -> IconSearchResult? {
        guard let url = fileURL(forIconName: name) else { return nil }
        return IconSearchResult(
            id: Self.resultID(setID: iconSet.id, iconName: name),
            title: name.replacingOccurrences(of: "-", with: " "),
            providerID: iconSet.id,
            imageURL: url,
            isVector: true,
            credit: iconSet.creditedName,
            creditURL: iconSet.homepage,
            license: iconSet.license)
    }

    static func resultID(setID: String, iconName: String) -> String { "\(setID):\(iconName)" }

    static func iconName(fromResultID id: String, setID: String) -> String? {
        let prefix = "\(setID):"
        guard id.hasPrefix(prefix) else { return nil }
        let name = String(id.dropFirst(prefix.count))
        return name.isEmpty ? nil : name
    }

    /// Resolves an icon name to a file inside the set's directory, or `nil` if it
    /// would land anywhere else.
    ///
    /// The same bounds check `IconManifest.resolvedURL(forFile:in:)` does, and for a
    /// stronger reason: these names come out of an archive downloaded from the
    /// internet, and themes are full of symlinks. Comparing the *resolved* paths is
    /// what stops an aliased `something.svg → /etc/passwd` from being read, while
    /// leaving the many legitimate aliases that point within the set working.
    func fileURL(forIconName name: String) -> URL? {
        guard !name.isEmpty, name.count <= 255, !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              !name.contains("\0"), !name.contains("..") else { return nil }

        let candidate = directory.appendingPathComponent("\(name).svg")
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolved.hasPrefix(root + "/") else { return nil }
        return candidate
    }
}
