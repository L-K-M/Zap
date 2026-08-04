import Foundation

/// Why a search or fetch didn't produce anything.
enum IconSearchError: Error, Equatable {
    case network(String)
    case decoding
    /// The provider needs a key the user hasn't supplied.
    case notConfigured
    /// The provider knows about the icon but can't produce it — a local set whose
    /// files have been removed since it was searched, say. Distinct from `.network`
    /// because nothing here went over a wire, and saying "couldn't download" about
    /// a file on disk sends the user looking in the wrong place.
    case unavailable(String)

    var message: String {
        switch self {
        case .network(let description): return description
        case .decoding: return "That provider returned something Zap couldn't read."
        case .notConfigured: return "That provider needs an API key first."
        case .unavailable(let description): return description
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
    ///
    /// `nil` for a provider that sends nothing at all — an installed icon set is
    /// searched entirely on disk (§5.6). Optional rather than a stock "nothing
    /// leaves your Mac" string, because the disclosure is a wall the user has to
    /// dismiss before their first search, and putting one in front of a search that
    /// cannot be observed teaches people to click through the ones that can.
    var disclosure: String? { get }

    /// Whether the user must supply a key before this provider works.
    var requiresAPIKey: Bool { get }

    /// Runs a search. Never called automatically — only in response to a click.
    func search(query: String, limit: Int) async -> Result<[IconSearchResult], IconSearchError>

    /// What this provider would offer for an app before being asked anything
    /// (`UNJAILED.md §5.6`: "the app's name should surface its likely icon first").
    ///
    /// Empty by default, and that is the right answer for every remote provider:
    /// suggesting means searching, searching means sending, and §5.5 says nothing
    /// is sent until the user asks. A provider whose corpus is local has no such
    /// cost, so it overrides this.
    func suggestions(appName: String, bundleIdentifier: String, limit: Int) async -> [IconSearchResult]

    /// Fetches the artwork bytes for one result, bounded the same way any other
    /// remote image is (§6.4).
    func fetchImageData(for result: IconSearchResult) async -> Result<Data, IconSearchError>
}

extension IconSearchProvider {
    var requiresAPIKey: Bool { false }

    func suggestions(appName: String, bundleIdentifier: String, limit: Int) async -> [IconSearchResult] {
        []
    }
}
