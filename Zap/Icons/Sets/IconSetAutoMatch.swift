import Foundation

/// Decides which apps an installed icon set can be applied to **without anyone
/// looking at the result** (`UNJAILED.md §5.6`).
///
/// The picker and this share one guesser and differ only in what they do with a
/// weak answer. In the picker a bad guess costs nothing: it is one cell in a grid
/// the user is already reading, next to a search field. Applied in bulk it costs
/// something real — the wrong logo silently attached to an app, discovered days
/// later in the switcher, with no memory of which of forty icons was guessed.
///
/// So the bar is higher here than there, and it is the only difference:
///
/// | Tier | Picker | Bulk |
/// |---|---|---|
/// | `.known` — a hand-written alias | offers | applies |
/// | `.exact` — the normalised name *is* the icon's | offers | applies |
/// | `.prefix` — word-boundary either way | offers | **skips** |
/// | `.related` — a shared word of four letters | offers | **skips** |
///
/// `.prefix` is the interesting exclusion, because it is right more often than it
/// is wrong — it is what finds `docker` for "Docker Desktop". It is also what
/// finds `chrome-remote-desktop` for an app called Chrome when the theme has no
/// `chrome`, and `ada-lovelace` for one called Ada. Right-more-often-than-not is a
/// good suggestion and a bad automatic action.
enum IconSetAutoMatch {

    /// Whether a match is strong enough to apply unattended.
    static func isConfident(_ confidence: IconNameGuess.Confidence) -> Bool {
        switch confidence {
        case .known, .exact: return true
        case .prefix, .related: return false
        }
    }

    /// The icon this set would apply to an app, or `nil` when nothing reaches the
    /// bar. At most one — a bulk apply picks or it doesn't.
    static func confidentMatch(appName: String, bundleIdentifier: String,
                               in iconNames: Set<String>) -> String? {
        // `matches` is already ranked best-first, so only the head can qualify:
        // if it isn't confident, nothing behind it is either.
        guard let best = IconNameGuess.matches(appName: appName,
                                               bundleIdentifier: bundleIdentifier,
                                               in: iconNames, limit: 1).first,
              isConfident(best.confidence) else { return nil }
        return best.iconName
    }

    /// What a run did, for the summary the user gets afterwards.
    struct Outcome: Equatable {
        /// Icons applied.
        var applied: Int = 0
        /// Apps the set had no confident match for.
        var unmatched: Int = 0
        /// Apps left alone because they already carry the user's own choice.
        var skipped: Int = 0
        /// Matches found whose artwork wouldn't render.
        var failed: Int = 0

        var isEmpty: Bool { applied == 0 && unmatched == 0 && skipped == 0 && failed == 0 }
    }

    /// The sentence shown when a run finishes.
    ///
    /// Phrased around what changed, then what didn't and why — "nothing happened"
    /// is the outcome most in need of an explanation, and the usual reason is that
    /// every app already had an icon the user chose.
    static func summary(_ outcome: Outcome, setName: String) -> String {
        var parts: [String] = []
        parts.append(outcome.applied == 1
            ? "Applied 1 icon from \(setName)."
            : "Applied \(outcome.applied) icons from \(setName).")
        if outcome.skipped > 0 {
            parts.append(outcome.skipped == 1
                ? "1 app kept the icon you'd already given it."
                : "\(outcome.skipped) apps kept the icons you'd already given them.")
        }
        if outcome.unmatched > 0 {
            parts.append(outcome.unmatched == 1
                ? "1 app had no confident match in the set."
                : "\(outcome.unmatched) apps had no confident match in the set.")
        }
        if outcome.failed > 0 {
            parts.append(outcome.failed == 1
                ? "1 icon couldn't be rendered."
                : "\(outcome.failed) icons couldn't be rendered.")
        }
        return parts.joined(separator: " ")
    }
}
