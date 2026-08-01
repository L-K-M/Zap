import AppKit
import SwiftUI

/// One app's row in the Icons settings tab: what Zap will draw for it, what that
/// artwork is, and the ways to change it.
///
/// Deliberately dumb — it holds no state and reaches for nothing. `IconsView` owns
/// the store, the resolver and every decision; this just renders what it's handed
/// and reports back.
struct IconRow: View {

    let app: AppInfo
    /// The icon Zap would actually draw, already resolved.
    let icon: NSImage?
    /// Caption under the app name.
    let status: String
    /// Whether there is an override to revert.
    let hasOverride: Bool
    /// Whether this app is already pinned to the system icon.
    let isPinnedToSystemIcon: Bool
    /// Whether a drag is currently over this row.
    let isDropTarget: Bool

    var onChooseFile: () -> Void
    var onUseOriginalArtwork: () -> Void
    var onUseSystemIcon: () -> Void
    /// Returns whether the drop was accepted; refusing makes the drag snap back.
    var onDrop: (URL) -> Bool
    var onDropTargeted: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon ?? NSImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Choose File…", action: onChooseFile)
                Button("Use Original Artwork", action: onUseOriginalArtwork)
                    .disabled(!hasOverride)
                Button("Use System Icon", action: onUseSystemIcon)
                    .disabled(isPinnedToSystemIcon)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // §5.3: the browser is the search box. A drag from one carries a URL rather
        // than a file, and that is the more important ingestion path of the two.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return onDrop(url)
        } isTargeted: onDropTargeted
        .listRowBackground(isDropTarget ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}
