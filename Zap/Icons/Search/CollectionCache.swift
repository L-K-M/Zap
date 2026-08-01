import Foundation

/// Iconify's `/collections` metadata, fetched once and reused.
///
/// Search returns bare `prefix:name` identifiers, so the set's display name and
/// licence — the things `UNJAILED.md §5.4` requires before a provider may ship —
/// have to come from here. One fetch per client, not one per result.
final class CollectionCache {

    private let session: URLSession
    private let host: String
    private let lock = NSLock()
    private var cached: [String: IconCollection]?

    init(session: URLSession, host: String) {
        self.session = session
        self.host = host
    }

    /// The set metadata, fetching it on first use. Returns an empty map on any
    /// failure: a missing licence is worth degrading the credit line over, not
    /// worth failing the whole search for.
    func sets() async -> [String: IconCollection] {
        lock.lock()
        let existing = cached
        lock.unlock()
        if let existing { return existing }

        guard let url = URL(string: "\(host)/collections"),
              let (data, _) = try? await session.data(from: url),
              let decoded = try? JSONDecoder().decode([String: IconCollection].self, from: data)
        else { return [:] }

        // A concurrent caller may have raced us here; both computed the same
        // thing, so last write wins is fine.
        lock.lock()
        cached = decoded
        lock.unlock()
        return decoded
    }
}
