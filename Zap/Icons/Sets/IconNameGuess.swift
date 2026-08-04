import Foundation

/// Guesses which icon in a theme belongs to a Mac app, and how confident that is.
///
/// This is the part that decides whether picking from a set feels like a suggestion
/// or like scrolling four thousand files. Themes name icons after Linux binaries
/// and desktop entries; Zap has a display name and a bundle identifier, and the two
/// worlds agree more often than not but never completely:
///
/// | Zap has | The theme has | |
/// |---|---|---|
/// | `Google Chrome` | `google-chrome` | the normalised display name is enough |
/// | `Visual Studio Code` | `visual-studio-code` | likewise |
/// | `Docker Desktop` | `docker` | close, and wrong without help |
/// | `com.tinyspeck.slackmacgap` | `slack` | the identifier says nothing useful |
///
/// So: several candidate spellings, ranked, and a small table for the ones no rule
/// would reach. A miss costs nothing — the user is already in the picker with the
/// whole set to search — which is what lets this be a guess rather than a lookup.
enum IconNameGuess {

    /// How well a candidate matched, best first. `Comparable` so results sort.
    enum Confidence: Int, Comparable {
        /// A hand-written mapping. Nothing outranks knowing.
        case known = 3
        /// The app's name or identifier, normalised, is the icon's name exactly.
        case exact = 2
        /// The icon's name is a word-boundary prefix of the app's, or the reverse:
        /// `docker` for "Docker Desktop", `slack` for "Slack".
        case prefix = 1
        /// The names share a word. Weak, and last.
        case related = 0

        static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Match: Equatable {
        let iconName: String
        let confidence: Confidence
    }

    // MARK: Normalising

    /// An app name as a theme would spell it: lowercased, punctuation to hyphens,
    /// runs collapsed, ends trimmed.
    ///
    /// `Claude ★` becomes `claude`, not `claude-`, because a trailing separator
    /// would miss every icon. Non-ASCII goes the same way as punctuation — themes
    /// name files in ASCII, so anything else can only be noise for matching.
    static func normalised(_ name: String) -> String {
        var out = ""
        var pendingSeparator = false
        for character in name.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                if pendingSeparator, !out.isEmpty { out.append("-") }
                pendingSeparator = false
                out.append(character)
            } else {
                pendingSeparator = true
            }
        }
        return out
    }

    /// The spellings worth trying for an app, most specific first.
    ///
    /// The bundle identifier's last component is included because it is right often
    /// enough to be worth a look (`com.apple.Safari` → `safari`) and wrong in ways
    /// the ranking handles rather than the caller (`…slackmacgap` → `slackmacgap`,
    /// which matches nothing and costs nothing).
    static func candidates(appName: String, bundleIdentifier: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ candidate: String) {
            let normalised = normalised(candidate)
            guard !normalised.isEmpty, seen.insert(normalised).inserted else { return }
            out.append(normalised)
        }

        add(appName)
        // "Google Chrome" also worth trying as "chrome": themes drop the vendor as
        // often as they keep it.
        let words = normalised(appName).split(separator: "-")
        if words.count > 1 {
            add(words.dropFirst().joined(separator: "-"))
            add(words.dropLast().joined(separator: "-"))
            add(String(words[0]))
        }
        // Only when it *is* an identifier. Settings builds rows for apps that aren't
        // running out of manifest keys, and those keys are bundle paths — whose last
        // dot-component is `app`, every time, for every app. Suggesting whatever a
        // theme happens to call `app` for all of them is worse than suggesting
        // nothing, so the tail is taken only from something identifier-shaped.
        if !bundleIdentifier.contains("/"),
           let tail = bundleIdentifier.split(separator: ".").last {
            add(String(tail))
        }
        return out
    }

    // MARK: Matching

    /// The best matches for an app among `iconNames`, ranked and de-duplicated.
    ///
    /// `limit` bounds what the picker shows above the full set; the rest of the
    /// theme is still there to search.
    static func matches(appName: String, bundleIdentifier: String,
                        in iconNames: Set<String>, limit: Int = 12) -> [Match] {
        var best: [String: Confidence] = [:]
        func offer(_ iconName: String, _ confidence: Confidence) {
            guard iconNames.contains(iconName) else { return }
            if let existing = best[iconName], existing >= confidence { return }
            best[iconName] = confidence
        }

        let spellings = candidates(appName: appName, bundleIdentifier: bundleIdentifier)

        for alias in aliases(appName: appName, bundleIdentifier: bundleIdentifier) {
            offer(alias, .known)
        }
        for spelling in spellings {
            offer(spelling, .exact)
        }

        // Word-boundary relations, which is where "Docker Desktop" finds `docker`
        // without the alias table having to know about it.
        for spelling in spellings where !spelling.isEmpty {
            for iconName in iconNames {
                if iconName.hasPrefix(spelling + "-") || spelling.hasPrefix(iconName + "-") {
                    offer(iconName, .prefix)
                }
            }
        }

        let words = Set(spellings.flatMap { $0.split(separator: "-").map(String.init) })
            .filter { $0.count >= 4 }
        for word in words where iconNames.contains(word) {
            offer(word, .related)
        }

        return best
            .map { Match(iconName: $0.key, confidence: $0.value) }
            .sorted {
                $0.confidence != $1.confidence
                    ? $0.confidence > $1.confidence
                    : $0.iconName.count < $1.iconName.count
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Aliases

    /// The ones no rule reaches, keyed by whichever of the two identifies the app
    /// unambiguously.
    ///
    /// Deliberately short. Every entry is a case where the Mac name and the Linux
    /// name genuinely differ rather than one being a normalisation of the other,
    /// and the list is meant to stay browsable rather than become a mapping of the
    /// App Store. The ranking handles everything else.
    static func aliases(appName: String, bundleIdentifier: String) -> [String] {
        if let byIdentifier = aliasesByBundleIdentifier[bundleIdentifier] { return byIdentifier }
        return aliasesByName[normalised(appName)] ?? []
    }

    static let aliasesByBundleIdentifier: [String: [String]] = [
        "com.tinyspeck.slackmacgap": ["slack"],
        "com.microsoft.VSCode": ["visual-studio-code", "code"],
        "com.microsoft.VSCodeInsiders": ["visual-studio-code-insiders"],
        "com.googlecode.iterm2": ["iterm", "utilities-terminal"],
        "com.apple.Safari": ["safari", "webbrowser-app"],
        "com.apple.finder": ["system-file-manager"],
        "com.apple.Terminal": ["utilities-terminal", "terminal"],
        "com.apple.mail": ["internet-mail", "mail-client"],
        "com.apple.iCal": ["office-calendar", "calendar"],
        "com.hnc.Discord": ["discord"],
        "com.spotify.client": ["spotify"],
        "com.docker.docker": ["docker"],
        "com.figma.Desktop": ["figma"],
        "notion.id": ["notion"],
        "md.obsidian": ["obsidian"],
        "com.jetbrains.intellij": ["intellij-idea", "idea"],
        "com.jetbrains.intellij.ce": ["intellij-idea-ce", "idea"],
        "com.todesktop.230313mzl4w4u92": ["cursor"],
        "com.brave.Browser": ["brave"],
        "org.mozilla.firefox": ["firefox"],
        "com.operasoftware.Opera": ["opera"],
        "com.vivaldi.Vivaldi": ["vivaldi"],
        "com.github.GitHubClient": ["github-desktop", "github"],
        "com.postmanlabs.mac": ["postman"],
        "com.electron.dockerdesktop": ["docker"],
    ]

    /// For apps whose identifier is unhelpful or varies, matched on the name.
    static let aliasesByName: [String: [String]] = [
        "visual-studio-code": ["visual-studio-code", "code"],
        "docker-desktop": ["docker"],
        "google-chrome": ["google-chrome", "chrome"],
        "microsoft-edge": ["microsoft-edge", "edge"],
        "activity-monitor": ["utilities-system-monitor"],
        "system-settings": ["preferences-system"],
        "system-preferences": ["preferences-system"],
    ]
}
