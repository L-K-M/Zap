import Foundation

/// Where the switcher gets the artwork it draws for an app.
///
/// macOS 26 composites every app icon into one fixed superellipse, so
/// `NSRunningApplication.icon` hands back a masked (and, for pre-Tahoe artwork,
/// scaled-down and plated) composite. Zap draws its own icon row, so it can
/// substitute at draw time instead — see `UNJAILED.md §3` for the resolution
/// ladder these cases correspond to.
enum IconSourceMode: String, CaseIterable, Identifiable {

    /// Rung 1 — whatever the system hands us. Today's behaviour.
    case system

    /// Rung 2 — the app bundle's own, unmasked artwork when it can be recovered,
    /// falling back to the system icon when it can't.
    case original

    /// Rung 3 — as `original`, but a file the user picked wins over both.
    case originalPlusCustom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System icons"
        case .original: return "Original app artwork when available"
        case .originalPlusCustom: return "Original artwork + my custom icons"
        }
    }

    /// Whether this mode reads artwork out of app bundles at all.
    var usesBundleArtwork: Bool { self != .system }

    /// Whether a user-chosen file overrides the app's own artwork.
    var usesCustomIcons: Bool { self == .originalPlusCustom }

    /// The shipping default: un-jailing is a *restoration* on the systems that
    /// jail icons in the first place, and a no-op change of behaviour on the ones
    /// that don't — so it is only on where it does something.
    static var systemDefault: IconSourceMode {
        isSquircleJailed ? .original : .system
    }

    /// Whether the running system masks app icons into the fixed superellipse
    /// (macOS 26 Tahoe and later). A plain runtime version check rather than an
    /// `#available` clause: the deployment target is macOS 13 and this is a
    /// behavioural question about the host, not an API-availability one.
    static var isSquircleJailed: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }
}
