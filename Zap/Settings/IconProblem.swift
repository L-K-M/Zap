import SwiftUI

/// Something that went wrong while taking on an icon, phrased for an alert.
///
/// These failures are all direct answers to something the user just did — picked
/// a file, dropped a link, chose a search result — and every one of them means the
/// thing they asked for did not happen. A caption in the corner of the window is
/// the wrong shape for that: it appears far from where they were looking, it sits
/// among two other captions that are always there, and nothing marks it as new. So
/// icon failures interrupt instead, and the caption is gone.
/// `Error` so it can ride in a `Result` alongside the image it failed to produce —
/// the failure is decided where the detail is, not re-derived at the call site.
struct IconProblem: Identifiable, Error {

    let id = UUID()
    /// The alert's title — short, and about what failed rather than why.
    let title: String
    /// The reason, plus what it left unchanged.
    let message: String

    // MARK: Cases

    /// An image Zap looked at and turned down, or couldn't render.
    static func rejected(_ rejection: IconImageValidator.Rejection, app: AppInfo) -> IconProblem {
        IconProblem(title: "Zap couldn't use that image",
                    message: "\(rejection.message) \(app.name)'s icon is unchanged.")
    }

    /// A dragged link that isn't worth trying to fetch.
    static func unfetchableLink(app: AppInfo) -> IconProblem {
        IconProblem(title: "Zap couldn't use that link",
                    message: "Zap can only fetch images from http and https links. "
                        + "\(app.name)'s icon is unchanged.")
    }

    /// A download that didn't arrive.
    static func fetchFailed(_ reason: String, app: AppInfo) -> IconProblem {
        IconProblem(title: "Zap couldn't download that image",
                    message: "\(reason) \(app.name)'s icon is unchanged.")
    }

    /// A second icon offered while the first is still being taken on. Refusing is
    /// deliberate: two in flight race, and the last to land wins rather than the
    /// last one asked for.
    static func alreadyInFlight(app: AppInfo) -> IconProblem {
        IconProblem(title: "One at a time",
                    message: "Zap is still adding an icon for \(app.name). "
                        + "Wait for that to finish, then try again.")
    }

    /// A search that didn't come back with anything usable.
    static func searchFailed(_ reason: String, provider: String) -> IconProblem {
        IconProblem(title: "Zap couldn't search \(provider)", message: reason)
    }

    /// An icon set that didn't download, unpack, or contain anything.
    static func setInstallFailed(_ reason: String, set: IconSet) -> IconProblem {
        IconProblem(title: "Zap couldn't install \(set.name)",
                    message: "\(reason) Nothing on your Mac was changed.")
    }

    /// A set Zap has a record of but can no longer read — its files removed from
    /// under it, or a directory that no longer resolves.
    static func setUnavailable(_ set: IconSet) -> IconProblem {
        IconProblem(title: "\(set.name) isn't available",
                    message: "Zap has a record of \(set.name) but can't read its icons. "
                        + "Install it again from Icon Sets… No icons were changed.")
    }

    /// Results came back but not one of them would draw. Distinct from a failed
    /// search: the provider answered, so the fault is on Zap's side of the line.
    static func previewsUnavailable(provider: String) -> IconProblem {
        IconProblem(title: "Zap couldn't draw those icons",
                    message: "\(provider) returned results, but none of them could be rendered. "
                        + "Picking one will say why.")
    }
}

extension View {

    /// Presents `problem` as a modal alert, clearing it once dismissed.
    ///
    /// Bound to the optional rather than a separate `isPresented` flag, so there is
    /// no state where one says "showing" and the other has nothing to show.
    func alert(iconProblem problem: Binding<IconProblem?>) -> some View {
        alert(problem.wrappedValue?.title ?? "",
              isPresented: Binding(get: { problem.wrappedValue != nil },
                                   set: { if !$0 { problem.wrappedValue = nil } }),
              presenting: problem.wrappedValue) { _ in
            // `.cancel` so Escape dismisses it, not just the button.
            Button("OK", role: .cancel) {}
        } message: { problem in
            Text(problem.message)
        }
    }
}
