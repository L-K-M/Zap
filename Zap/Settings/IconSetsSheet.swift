import SwiftUI

/// Installs, updates and removes the Linux icon themes Zap can fetch
/// (`UNJAILED.md §5.6`).
///
/// A sheet rather than a tab: this is a thing you do once and then forget, and the
/// place you find it from is the icon row where you wanted a better icon. What it
/// deliberately isn't is an icon browser — picking stays per app, in the search
/// sheet, which is where the app you're picking for is.
struct IconSetsSheet: View {

    @ObservedObject var library: IconSetLibrary
    var onDone: () -> Void

    @State private var problem: IconProblem?
    /// A one-line outcome for the things that go *right* but produce nothing to
    /// look at — "already up to date" being the whole reason update checks are
    /// conditional requests.
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon sets")
                .font(.headline)

            Text("Icon themes from the Linux desktop: thousands of app icons drawn to one brief, "
                 + "under a stated licence. Zap downloads a set, keeps the app icons out of it and "
                 + "throws the rest away — then you pick from it per app, like any other source.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(IconSetCatalogue.all) { set in
                row(for: set)
            }
            .listStyle(.inset)
            .frame(minHeight: 180)

            if let note {
                Label(note, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Sets are downloaded from the theme's own repository, and only when you ask. "
                 + "Nothing about your apps is ever sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
        .alert(iconProblem: $problem)
    }

    // MARK: Rows

    private func row(for set: IconSet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name)
                    .font(.body.weight(.medium))
                Text(status(for: set))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let homepage = set.homepage {
                    Link(set.license, destination: set.licenseURL ?? homepage)
                        .font(.caption)
                }
            }
            Spacer(minLength: 8)
            buttons(for: set)
        }
        .padding(.vertical, 4)
    }

    /// What the row says about a set right now.
    private func status(for set: IconSet) -> String {
        if library.installing == set.id { return "Downloading…" }
        guard let record = library.record(for: set) else {
            return "Not installed"
        }
        return "\(record.iconCount.formatted()) icons · installed "
            + record.installedAt.formatted(date: .abbreviated, time: .omitted)
    }

    @ViewBuilder
    private func buttons(for set: IconSet) -> some View {
        let busy = library.installing != nil
        if library.isInstalled(set) {
            HStack(spacing: 8) {
                Button("Check for Updates") { install(set) }
                    .disabled(busy)
                Button("Remove", role: .destructive) {
                    library.remove(set)
                    note = "Removed \(set.name). Icons you already picked from it are unaffected."
                }
                .disabled(busy)
            }
        } else {
            Button("Install") { install(set) }
                .disabled(busy)
        }
    }

    // MARK: Actions

    private func install(_ set: IconSet) {
        note = nil
        // `@MainActor` explicitly: everything touched here publishes — `library`'s
        // state and this sheet's — and only the download and unpack inside
        // `install` run elsewhere.
        Task { @MainActor in
            switch await library.install(set) {
            case .failure(let error):
                problem = .setInstallFailed(error.message, set: set)
            case .success(.unchanged):
                note = "\(set.name) is already up to date."
            case .success(.installed(let installation)):
                note = "\(set.name): \(installation.iconCount.formatted()) icons ready."
            }
        }
    }
}
