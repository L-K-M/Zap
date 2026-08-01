import AppKit
import SwiftUI

/// Finds an icon for one app without leaving Zap (`UNJAILED.md §5.2`, §5.5).
///
/// The privacy rules are structural, not advisory: the query is prefilled from the
/// app's name but editable before it goes anywhere, nothing is sent until the user
/// presses Search, the disclosure of what will be sent is shown before the first
/// search of that provider, and the bundle identifier — the thing that would reveal
/// what's installed — never leaves the machine.
struct IconSearchSheet: View {

    let app: AppInfo
    let provider: IconSearchProvider
    @ObservedObject var preferences: Preferences
    /// Called with the chosen result's artwork, already fetched and rasterised.
    var onAdopt: (IconSearchResult, CGImage) -> Void
    var onCancel: () -> Void

    @State private var query: String
    @State private var results: [IconSearchResult] = []
    @State private var previews: [String: NSImage] = [:]
    /// Results whose preview couldn't be rendered. Without this a failed preview
    /// spins forever, which reads as "still loading" and never stops being wrong.
    @State private var previewFailures: Set<String> = []
    @State private var isSearching = false
    @State private var isAdopting = false
    @State private var problem: IconProblem?
    /// Bumped per search, so previews from a replaced one are discarded.
    @State private var previewGeneration = 0
    /// Bumped per search, so a slow earlier search can't land on top of a newer
    /// one — the Search button is disabled while one is running, but `onSubmit`
    /// isn't.
    @State private var searchGeneration = 0

    init(app: AppInfo, provider: IconSearchProvider, preferences: Preferences,
         onAdopt: @escaping (IconSearchResult, CGImage) -> Void,
         onCancel: @escaping () -> Void) {
        self.app = app
        self.provider = provider
        self.preferences = preferences
        self.onAdopt = onAdopt
        self.onCancel = onCancel
        // Prefilled, but the user edits it before anything is sent (§5.5).
        _query = State(initialValue: app.name)
    }

    /// Whether this provider's disclosure has already been read. Persisted rather
    /// than per-sheet: §5.5 asks for it before the first search, and a notice shown
    /// every single time is one the user stops reading.
    private var hasAcknowledgedDisclosure: Bool {
        preferences.acknowledgedSearchProviders.contains(provider.id)
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
                Spacer()
                Button("Cancel", action: onCancel)
            }
        }
        .padding(16)
        .frame(width: 560, height: 460)
        .alert(iconProblem: $problem)
        // Dismissing the sheet retires both generations, which is what the
        // preview loop checks between renders. Without it, cancelling mid-search
        // leaves up to `resultLimit` fetch-and-rasterise rounds running for a
        // sheet that is already gone — each one standing up a `WKWebView` to
        // render a preview nobody can see.
        .onDisappear {
            searchGeneration += 1
            previewGeneration += 1
        }
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
            Button("Continue") {
                preferences.acknowledgedSearchProviders.insert(provider.id)
            }
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
                } else if previewFailures.contains(result.id) {
                    // Still clickable: a preview can fail on a blip that adopting
                    // won't repeat, and picking it now says why rather than nothing.
                    Image(systemName: "questionmark.square.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.tertiary)
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
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        results = []
        previews = [:]
        previewFailures = []
        Task {
            let found = await provider.search(query: text, limit: Self.resultLimit)
            await MainActor.run {
                guard generation == searchGeneration else { return }
                isSearching = false
                switch found {
                case .failure(let error):
                    problem = .searchFailed(error.message, provider: provider.displayName)
                case .success(let items):
                    results = items
                    previewGeneration += 1
                    loadPreviews(items, generation: previewGeneration)
                }
            }
        }
    }

    /// How many results a search asks for — about a screenful of the grid.
    ///
    /// The same number bounds the previews, and that is the point of there being
    /// one: asking for more results than get rendered leaves the surplus on a
    /// spinner that never resolves, because nothing ever tries them. The cap
    /// belongs on what is fetched, not on what is drawn out of it.
    private static let resultLimit = 24

    /// Renders previews **one at a time**. Each render stands up a `WKWebView`,
    /// which is heavyweight enough that two dozen alive at once is a real memory
    /// spike. Sequential awaits keep exactly one alive, so the grid fills in
    /// rather than arriving at once — every result gets its turn.
    ///
    /// `generation` drops results from a search the user has already replaced.
    ///
    /// Every outcome is recorded, success or not. Skipping the failures left their
    /// cells on a spinner that never resolved — the whole grid looked like it was
    /// still loading when in fact nothing was left to wait for.
    private func loadPreviews(_ items: [IconSearchResult], generation: Int) {
        Task {
            var rendered = 0
            for item in items {
                let image = await previewImage(for: item)
                let stale = await MainActor.run { () -> Bool in
                    guard generation == previewGeneration else { return true }
                    if let image {
                        previews[item.id] = NSImage(cgImage: image, size: NSSize(width: 56, height: 56))
                    } else {
                        previewFailures.insert(item.id)
                    }
                    return false
                }
                if stale { return }
                if image != nil { rendered += 1 }
            }
            // Not one of them drew. That is a broken renderer rather than awkward
            // artwork, and it is worth saying so — silence here is what a grid of
            // permanent spinners was.
            if rendered == 0, !items.isEmpty {
                await MainActor.run {
                    guard generation == previewGeneration else { return }
                    problem = .previewsUnavailable(provider: provider.displayName)
                }
            }
        }
    }

    /// One preview, or `nil` if it couldn't be fetched or decoded. Goes through
    /// `IconImport` like every other ingestion path, so a provider that starts
    /// returning bitmaps is decoded rather than refused for not being SVG.
    private func previewImage(for item: IconSearchResult) async -> CGImage? {
        guard case .success(let data) = await provider.fetchImageData(for: item) else { return nil }
        guard case .success(let image) = await IconImport.image(from: data, side: 128) else { return nil }
        return image
    }

    /// Fetches and rasterises the chosen result, then hands it to `onAdopt`.
    ///
    /// Generation-guarded like the search itself. Cancel stays enabled while a
    /// result is being fetched, so without the guard a user who picks an icon and
    /// then changes their mind still gets it: the render finishes after the sheet
    /// is gone and `onAdopt` writes it to the store anyway. Searching again mid-fetch
    /// retires it for the same reason — they have moved on from that result.
    ///
    /// `isAdopting` clears *before* the guard, on every path. It says whether a fetch
    /// is in flight, not whether its result is still wanted — and a retired fetch is
    /// no longer in flight either. Clearing it after the guard would strand it at
    /// `true` for the one case that can actually reach the sheet: `onSubmit` isn't
    /// gated on `isAdopting`, so Return in the search field starts a new search
    /// mid-adopt, and the retired continuation would then leave every result cell
    /// disabled — a sheet that has to be closed and reopened to pick anything.
    private func adopt(_ result: IconSearchResult) {
        isAdopting = true
        let generation = searchGeneration
        Task {
            let fetched = await provider.fetchImageData(for: result)
            guard case .success(let data) = fetched else {
                await MainActor.run {
                    isAdopting = false
                    guard generation == searchGeneration else { return }
                    if case .failure(let error) = fetched {
                        problem = .fetchFailed(error.message, app: app)
                    }
                }
                return
            }
            // Through the same door as a chosen file or a dragged link, so a
            // provider that returns a bitmap is decoded rather than refused for
            // not being SVG — and the refusal, when there is one, is the right one.
            let rendered = await IconImport.image(from: data)
            await MainActor.run {
                isAdopting = false
                guard generation == searchGeneration else { return }
                switch rendered {
                case .failure(let rejection):
                    problem = .rejected(rejection, app: app)
                case .success(let image):
                    onAdopt(result, image)
                }
            }
        }
    }
}
