import CoreGraphics
import Foundation

/// The one door bytes the user supplied come through on their way to becoming an
/// icon.
///
/// `IconImageValidator` answers "is this bitmap acceptable?". This answers the
/// question standing in front of it — *what is this?* — which stopped having the
/// answer "whatever ImageIO decodes" the moment SVG arrived (`UNJAILED.md §6.1`,
/// §6.3). SVG is markup, not a container ImageIO has ever read, and it reaches Zap
/// by exactly the routes a PNG does: a file chosen in the panel, a file dropped on
/// a row, a link dragged out of a browser. Deciding from the *bytes*, in one place,
/// is what keeps those paths agreeing about what Zap accepts — a second ingestion
/// path that skipped this is precisely how SVG came to be refused with "that file
/// isn't an image Zap can read".
///
/// `async` because rasterising SVG drives a `WKWebView`. Bitmaps never suspend —
/// and neither does a cache hit, which `IconRenderCache` makes the common case for
/// markup that has been seen before.
enum IconImport {

    /// Which decoder some bytes are headed for.
    ///
    /// Split out from the import itself so the *decision* is testable without
    /// standing up a web view — the render is on `UNJAILED.md §9`'s manual list,
    /// but which of the two decoders runs should never have to be.
    enum Route: Equatable {
        /// Markup for `SVGRasterizer`.
        case svg
        /// A container for ImageIO, via `IconImageValidator`.
        case bitmap
        /// Past `Limits.maximumSourceBytes`; neither decoder is asked.
        case tooLarge(bytes: Int)
    }

    /// Where `data` will go. Sniffed from the bytes, never from an extension or a
    /// `Content-Type` (§6.1) — the size gate comes first so a decompression bomb is
    /// refused before anything looks at its contents.
    static func route(for data: Data) -> Route {
        guard data.count <= IconImageValidator.Limits.maximumSourceBytes else {
            return .tooLarge(bytes: data.count)
        }
        return SVGRasterizer.isSVG(data) ? .svg : .bitmap
    }

    // MARK: Importing

    /// Decodes `data`, rasterising it first when it turns out to be SVG.
    ///
    /// `side` bounds the longest edge of the result. It defaults to the master size
    /// Zap stores, and the search sheet asks for something much smaller for its
    /// preview grid — two dozen full-size renders to draw them at 56 pt is a real
    /// memory cost for pictures the user may never scroll to. Both branches honour
    /// it, and neither upscales: a source smaller than `side` comes back untouched.
    static func image(from data: Data,
                      side: Int = IconImageValidator.Limits.masterLongestEdge,
                      cache: IconRenderCache = .shared)
    async -> Result<CGImage, IconImageValidator.Rejection> {
        switch route(for: data) {
        case .tooLarge(let bytes):
            return .failure(.fileTooLarge(bytes: bytes))
        case .bitmap:
            return IconImageValidator.decode(data: data)
                .map { IconRenderer.downsample($0, longestEdge: side) }
        case .svg:
            // Cached here rather than inside the rasteriser, so it covers the one
            // door every route already comes through and the rasteriser stays a
            // thing that renders rather than a thing that also remembers.
            if let cached = cache.image(for: data, side: side) { return .success(cached) }
            switch await SVGRasterizer.rasterize(data, side: side) {
            case .success(let image):
                cache.store(image, for: data, side: side)
                return .success(image)
            case .failure(let error):
                return .failure(.svgNotRendered(reason: error.message))
            }
        }
    }

    /// Reads and decodes the file at `url`.
    static func image(contentsOf url: URL,
                      cache: IconRenderCache = .shared)
    async -> Result<CGImage, IconImageValidator.Rejection> {
        // Size from the filesystem first, so an oversized file is refused without
        // being pulled into memory to find out. `route` checks again on the bytes,
        // which is what catches a file with no readable size.
        if let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           byteCount > IconImageValidator.Limits.maximumSourceBytes {
            return .failure(.fileTooLarge(bytes: byteCount))
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.unreadable)
        }
        return await image(from: data, cache: cache)
    }
}
