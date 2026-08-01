import Foundation

/// One icon offered by a search provider, with everything needed to fetch it and
/// everything needed to credit it.
///
/// Attribution is carried on the result rather than looked up at save time,
/// because `UNJAILED.md §5.4` makes it a hard requirement: the credit has to reach
/// the manifest, and a provider that can't supply one shouldn't be built.
struct IconSearchResult: Identifiable, Equatable {

    /// Stable and provider-scoped, e.g. `iconify:logos:safari`.
    let id: String
    /// What the sheet shows under the preview.
    let title: String
    /// Which provider produced this (`IconSearchProvider.id`), recorded in the
    /// manifest so an exported icon pack says where its artwork came from.
    let providerID: String
    /// Where the artwork itself lives.
    let imageURL: URL
    /// Whether `imageURL` returns SVG, which needs rasterising first (§6.3).
    let isVector: Bool

    /// Who drew it, when the provider says.
    let credit: String?
    /// Where to link that credit.
    let creditURL: URL?
    /// Licence, as the provider states it.
    let license: String?

    /// A one-line summary for the sheet, e.g. "SVG Logos · CC0 1.0".
    var attributionSummary: String {
        [credit, license].compactMap { $0 }.joined(separator: " · ")
    }
}
