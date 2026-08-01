import AppKit
import SwiftUI

/// Finds an icon for one app without leaving Zap (`UNJAILED.md §5.2`, §5.5).
///
/// The privacy rules are structural, not advisory: the query is prefilled from the
/// app's name but editable before it goes anywhere, nothing is sent until the user
/// presses Search, the disclosure of what will be sent is shown before the first
/// search of a session, and the bundle identifier — the thing that would reveal
/// what's installed — never leaves the machine.
struct IconSearchSheet: View {

    let app: AppInfo
    let provider: IconSearchProvider
    /// Called with the chosen result's artwork, already fetched and rasterised.
    var onAdopt: (IconSearchResult, CGImage) -> Void
    var onCancel: () -> Void

    @State private var query: String
    @State private var results: [IconSearchResult] = []
    @State private var previews: [String: NSImage] = [:]
    @State private var isSearching = false
    @State private var isAdopting = false
    @State private var problem: String?
    /// Whether the user has acknowledged what a search sends, this session.
    @State private var hasAcknowledgedDisclosure = false

    init(app: AppInfo, provider: IconSearchProvider,
         onAdopt: @escaping (IconSearchResult, CGImage) -> Void,
         onCancel: @escaping () -> Void) {
        self.app = app
        self.provider = provider
        self.onAdopt = onAdopt
        self.onCancel = onCancel
        // Prefilled, but the user edits it before anything is sent (§5.5).
        _query = State(initialValue: app.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find an icon for \(app.name)")
                .font(.headline)

            if !hasAcknowledgedDisclosure {
                disclosure
            } else {
                searchField
                resultsArea
            }

            Divider()
            HStack {
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", action: onCancel)
            }
        }
        .padding(16)
        .frame(width: 560, height: 460)
    }

    // MARK: Disclosure

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Before Zap searches", systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
            Text(provider.disclosure)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Searching is never automatic — nothing is sent until you press Search, and you can edit the words first.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Continue") { hasAcknowledgedDisclosure = true }
            Spacer()
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack {
            TextField("Search \(provider.displayName)", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(runSearch)
            Button("Search", action: runSearch)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
    }

    private var resultsArea: some View {
        Group {
            if isSearching {
                centered { ProgressView() }
            } else if results.isEmpty {
                centered {
                    Text("No results yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                        ForEach(results) { result in
                            resultCell(result)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultCell(_ result: IconSearchResult) -> some View {
        Button {
            adopt(result)
        } label: {
            VStack(spacing: 4) {
                if let preview = previews[result.id] {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                } else {
                    ProgressView().frame(width: 56, height: 56)
                }
                Text(result.title)
                    .font(.caption)
                    .lineLimit(1)
                Text(result.attributionSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(6)
        }
        .buttonStyle(.plain)
        .disabled(isAdopting)
        .help(result.attributionSummary)
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }.frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func runSearch() {
        let text = query
        isSearching = true
        problem = nil
        results = []
        previews = [:]
        Task {
            let found = await provider.search(query: text, limit: 48)
            await MainActor.run {
                isSearching = false
                switch found {
                case .failure(let error): problem = error.message
                case .success(let items):
                    results = items
                    for item in items.prefix(24) { loadPreview(item) }
                }
            }
        }
    }

    /// Renders one result small, for the grid. Deliberately capped to the first
    /// screenful: rasterising 48 SVGs to preview them would be wasteful.
    private func loadPreview(_ result: IconSearchResult) {
        Task {
            guard case .success(let data) = await provider.fetchImageData(for: result) else { return }
            let rendered = await SVGRasterizer.rasterize(data, side: 128)
            guard case .success(let image) = rendered else { return }
            await MainActor.run {
                previews[result.id] = NSImage(cgImage: image, size: NSSize(width: 56, height: 56))
            }
        }
    }

    private func adopt(_ result: IconSearchResult) {
        isAdopting = true
        problem = nil
        Task {
            let fetched = await provider.fetchImageData(for: result)
            guard case .success(let data) = fetched else {
                await MainActor.run {
                    isAdopting = false
                    if case .failure(let error) = fetched { problem = error.message }
                }
                return
            }
            let rendered = await SVGRasterizer.rasterize(data)
            await MainActor.run {
                isAdopting = false
                switch rendered {
                case .failure(let error): problem = error.message
                case .success(let image): onAdopt(result, image)
                }
            }
        }
    }
}
