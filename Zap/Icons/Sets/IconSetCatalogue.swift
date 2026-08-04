import Foundation

/// The icon themes Zap knows how to fetch.
///
/// A list rather than a feature: adding one is a row here, which is what
/// `UNJAILED.md §5.6`'s "several sets, not one" asks for. Each row carries the
/// layout its archive actually has, because extracting selectively means knowing
/// where the application icons live — and a wrong guess is caught at install time
/// rather than shipping as a set that silently has nothing in it
/// (`IconSetInstaller` fails when a glob matches no files).
///
/// **Which sets, and why not the obvious five.** The design note names Papirus,
/// Numix, Tela, Adwaita and Breeze. Probing them settled it: Adwaita and Breeze are
/// overwhelmingly UI symbolics rather than application artwork, and Numix's *own*
/// repository carries barely twenty app icons — the large set everyone means by
/// "Numix" is the separate `numix-icon-theme-circle`. The three below each answer
/// for the great majority of a sample of common desktop apps; the two dropped
/// answered for almost none of it.
enum IconSetCatalogue {

    static let papirus = IconSet(
        id: "papirus",
        name: "Papirus",
        owner: "PapirusDevelopmentTeam",
        repository: "papirus-icon-theme",
        branch: "master",
        license: "GPL-3.0",
        licenseURL: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html"),
        homepage: URL(string: "https://github.com/PapirusDevelopmentTeam/papirus-icon-theme"),
        // `papirus-icon-theme-master/Papirus/64x64/apps/firefox.svg` → `firefox.svg`.
        // 64 px is the largest fixed size Papirus ships and its icons are SVG, so
        // the size in the path bounds nothing about how sharply they render.
        archiveGlob: "*/Papirus/64x64/apps/*.svg",
        strippedComponents: 4)

    static let tela = IconSet(
        id: "tela",
        name: "Tela",
        owner: "vinceliuice",
        repository: "Tela-icon-theme",
        branch: "master",
        license: "GPL-3.0",
        licenseURL: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html"),
        homepage: URL(string: "https://github.com/vinceliuice/Tela-icon-theme"),
        // Tela is built rather than shipped: the repository holds sources and an
        // installer, and the application icons are the scalable ones under `src`.
        // `Tela-icon-theme-master/src/scalable/apps/firefox.svg` → `firefox.svg`.
        archiveGlob: "*/src/scalable/apps/*.svg",
        strippedComponents: 4)

    static let numixCircle = IconSet(
        id: "numix-circle",
        name: "Numix Circle",
        owner: "numixproject",
        repository: "numix-icon-theme-circle",
        branch: "master",
        license: "GPL-3.0",
        licenseURL: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html"),
        homepage: URL(string: "https://github.com/numixproject/numix-icon-theme-circle"),
        // `numix-icon-theme-circle-master/Numix-Circle/48/apps/firefox.svg`. The 48
        // names the theme's nominal size; the files under it are SVG.
        archiveGlob: "*/Numix-Circle/48/apps/*.svg",
        strippedComponents: 4)

    /// Everything Zap can install, in the order the picker offers them.
    static let all: [IconSet] = [papirus, tela, numixCircle]

    static func set(withID id: String) -> IconSet? {
        all.first { $0.id == id }
    }
}
