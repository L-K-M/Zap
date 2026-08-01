import Foundation

/// Why a search or fetch didn't produce anything.
enum IconSearchError: Error, Equatable {
    case network(String)
    case decoding
    /// The provider needs a key the user hasn't supplied.
    case notConfigured

    var message: String {
        switch self {
        case .network(let description): return description
        case .decoding: return "That provider returned something Zap couldn't read."
        case .notConfigured: return "That provider needs an API key first."
        }
    }
}

/// A source of icons Zap can search.
///
/// The protocol exists mostly to keep the door open: `UNJAILED.md §5.2` concludes
/// that no viable *general* image search remains, and §12 question 3 leans toward
/// building the protocol and deferring the paid providers. So the shipped
/// implementations are the keyless ones, and a paid or BYO-key provider slots in
/// later without touching anything else.
protocol IconSearchProvider {

    /// Stable identifier, recorded in the manifest.
    var id: String { get }

    /// Name shown in the provider picker.
    var displayName: String { get }

    /// Plain-language statement of what a search sends and to whom, shown before
    /// the first search of a session (`UNJAILED.md §5.5`).
    var disclosure: String { get }

    /// Whether the user must supply a key before this provider works.
    var requiresAPIKey: Bool { get }

    /// Runs a search. Never called automatically — only in response to a click.
    func search(query: String, limit: Int) async -> Result<[IconSearchResult], IconSearchError>

    /// Fetches the artwork bytes for one result, bounded the same way any other
    /// remote image is (§6.4).
    func fetchImageData(for result: IconSearchResult) async -> Result<Data, IconSearchError>
}

extension IconSearchProvider {
    var requiresAPIKey: Bool { false }
}
