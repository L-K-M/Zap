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
/// **All five the design note named, and they are not equivalent.** The word "icon
/// theme" covers three quite different things here, which is why every row carries
/// a `summary` and why the order below is the order the picker offers them:
///
/// | | |
/// |---|---|
/// | Papirus, Tela | thousands of branded application logos — Firefox, Slack, Docker |
/// | Numix Circle | the same idea, drawn as flat discs |
/// | Breeze | ~200 app icons, nearly all of them KDE's own applications |
/// | Adwaita | no colour application icons at all — 16 px monochrome glyphs under generic freedesktop names |
///
/// Measured, not assumed: against a sample of eighteen common desktop applications
/// Papirus answers for sixteen, Numix Circle seventeen, Tela fifteen, and Breeze
/// none — while answering for six of eight KDE applications. Adwaita's `master` has
/// no full-colour `apps` directory whatsoever; its application-shaped icons are
/// `symbolic/legacy`, drawn at 16 px in a single grey.
///
/// The two weak ones are still here because a set that covers your case beats a set
/// that covers the average one: Krita and Kdenlive are cross-platform and Breeze
/// draws them, and Adwaita is the right answer for anyone who wants a uniform
/// monochrome row. The `summary` is what keeps that a choice rather than a surprise.
enum IconSetCatalogue {

    static let papirus = IconSet(
        id: "papirus",
        name: "Papirus",
        summary: "Thousands of branded app icons, flat and colourful. The broadest coverage here.",
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
        summary: "Thousands of branded app icons, flat with a softer palette than Papirus.",
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
        summary: "Branded app icons drawn as flat coloured discs — a uniformly round row.",
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

    static let breeze = IconSet(
        id: "breeze",
        name: "Breeze",
        summary: "KDE's own. About 200 full-colour icons, nearly all of them KDE applications "
            + "— Krita, Kdenlive, Kate — rather than the wider desktop.",
        owner: "KDE",
        repository: "breeze-icons",
        branch: "master",
        // The repository ships `COPYING.LIB`, which is the LGPL 2.1, and states no
        // licence anywhere else. Linked to the file itself rather than to a
        // canonical SPDX page, so the credit points at what Breeze actually carries.
        license: "LGPL-2.1",
        licenseURL: URL(string: "https://github.com/KDE/breeze-icons/blob/master/COPYING.LIB"),
        homepage: URL(string: "https://github.com/KDE/breeze-icons"),
        // `breeze-icons-master/icons/apps/48/kate.svg` → `kate.svg`. 48 is where
        // nearly all of them are: the other sizes hold a few dozen between them.
        archiveGlob: "*/icons/apps/48/*.svg",
        strippedComponents: 4)

    static let adwaita = IconSet(
        id: "adwaita",
        name: "Adwaita",
        summary: "GNOME's own. Monochrome 16 px glyphs under generic names — `web-browser`, "
            + "`utilities-terminal` — not branded artwork. A uniform grey row.",
        owner: "GNOME",
        repository: "adwaita-icon-theme",
        branch: "master",
        license: "LGPL-3.0 or CC BY-SA 3.0",
        licenseURL: URL(string: "https://github.com/GNOME/adwaita-icon-theme/blob/master/COPYING"),
        homepage: URL(string: "https://github.com/GNOME/adwaita-icon-theme"),
        // `symbolic/legacy`, because that is where Adwaita's application-shaped
        // icons are and there is nowhere else: `master` has no full-colour `apps`
        // directory. The names all end `-symbolic`, which the guesser handles —
        // "Web Browser" reaches `web-browser-symbolic` on the word-boundary prefix
        // tier — so they are matchable, if oddly titled.
        archiveGlob: "*/Adwaita/symbolic/legacy/*.svg",
        strippedComponents: 4)

    /// Everything Zap can install, in the order the picker offers them — broadest
    /// coverage first, so the set most likely to have the icon is the one already
    /// selected when the sheet opens.
    static let all: [IconSet] = [papirus, tela, numixCircle, breeze, adwaita]

    static func set(withID id: String) -> IconSet? {
        all.first { $0.id == id }
    }
}
