import Foundation

/// Iconify's public API — ~300k icons across 200+ open sets, no key, no quota
/// (`UNJAILED.md §5.2`).
///
/// The keyless fallback the design study picks once SVG rasterisation exists: it
/// is the largest corpus Zap can reach without asking the user to sign up for
/// anything, and its sets carry real licences, which is what makes it creditable
/// under §5.4. Everything it returns is SVG, so results go through
/// `SVGRasterizer` before they become icons.
struct IconifyClient: IconSearchProvider {

    let id = "iconify"
    let displayName = "Iconify"
    var disclosure: String? {
        "Sends only the words you type to api.iconify.design. Your app list, your bundle identifiers and the app you're changing are never sent."
    }

    private let session: URLSession
    private let host = "https://api.iconify.design"
    /// Set metadata, fetched once per client and reused. Licences live here rather
    /// than on the search response, which returns bare `prefix:name` strings.
    private let collections: CollectionCache

    init(session: URLSession = .shared) {
        self.session = session
        self.collections = CollectionCache(session: session, host: host)
    }

    // MARK: Search

    func search(query: String, limit: Int = 48) async -> Result<[IconSearchResult], IconSearchError> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success([]) }

        var components = URLComponents(string: "\(host)/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 128)))),
        ]
        guard let url = components?.url else { return .failure(.decoding) }

        let payload: SearchPayload
        switch await get(url, as: SearchPayload.self) {
        case .failure(let error): return .failure(error)
        case .success(let decoded): payload = decoded
        }

        let sets = await collections.sets()
        return .success(payload.icons.compactMap { Self.result(forIconID: $0, sets: sets, host: host) })
    }

    /// Turns a `prefix:name` identifier into a result, attaching the set's name and
    /// licence. Pure, so the mapping is testable against a canned payload.
    static func result(forIconID iconID: String,
                       sets: [String: IconCollection],
                       host: String) -> IconSearchResult? {
        let parts = iconID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let (prefix, name) = (parts[0], parts[1])

        // Percent-encoded rather than interpolated raw: Iconify identifiers are
        // conventionally `[a-z0-9-]`, but nothing here enforces that, and a name
        // carrying `?`, `#` or `/` would otherwise silently address the wrong
        // resource — or none.
        guard let safePrefix = prefix.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let safeName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        // Ask for the master size directly; Iconify rasterises nothing, but the
        // height hint sets the SVG's intrinsic size, which the rasteriser scales to.
        guard let imageURL = URL(string:
            "\(host)/\(safePrefix)/\(safeName).svg?height=\(IconImageValidator.Limits.masterLongestEdge)")
        else { return nil }

        let collection = sets[prefix]
        return IconSearchResult(
            id: "iconify:\(iconID)",
            title: name.replacingOccurrences(of: "-", with: " "),
            providerID: "iconify",
            imageURL: imageURL,
            isVector: true,
            credit: collection?.name ?? prefix,
            creditURL: URL(string: "https://icon-sets.iconify.design/\(safePrefix)/\(safeName)/"),
            license: collection?.license?.title)
    }

    // MARK: Fetching

    func fetchImageData(for result: IconSearchResult) async -> Result<Data, IconSearchError> {
        switch await RemoteIconFetcher.fetch(result.imageURL, session: session) {
        case .success(let data): return .success(data)
        case .failure(let error): return .failure(.network(error.message))
        }
    }

    // MARK: Transport

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async -> Result<T, IconSearchError> {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(.network("The provider returned HTTP \(http.statusCode)."))
            }
            guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                return .failure(.decoding)
            }
            return .success(decoded)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: Payloads

    /// `/search` returns identifiers only; everything else about a set comes from
    /// `/collections`.
    struct SearchPayload: Decodable, Equatable {
        var icons: [String]
    }
}

/// One Iconify icon set's metadata, as `/collections` reports it.
struct IconCollection: Decodable, Equatable {
    var name: String?
    var license: License?

    struct License: Decodable, Equatable {
        var title: String?
        var url: String?
    }
}
