import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures small still previews of individual windows, off the switcher hot path.
///
/// An `actor` so capture work and the backing cache are serialized without locks;
/// callers `await` a thumbnail and apply it to the overlay on the main actor.
///
/// Two capture backends:
/// - **macOS 14+:** ScreenCaptureKit (`SCScreenshotManager`), the supported path.
/// - **macOS 13:** `CGWindowListCreateImage` (deprecated in 14) as a fallback.
///
/// Both require **Screen Recording** permission; callers must gate use behind
/// `ScreenRecordingAuthorizer.isGranted`. Minimized or off-screen windows have no
/// backing store and yield `nil`, so the overlay keeps its placeholder glyph.
actor WindowThumbnailProvider {

    private var cache: LRUImageCache

    /// How long a fetched window list stays valid before we re-enumerate. A whole
    /// preview batch is captured well within this window, so the expensive
    /// system-wide `SCShareableContent` enumeration runs once per batch rather
    /// than once per window.
    private let contentTTL: TimeInterval

    /// Most-recent shareable-content snapshot and the time it was taken. macOS 14+
    /// only; typed `Any?` so the property needs no availability annotation.
    private var cachedContent: Any?
    private var cachedContentAt: TimeInterval = 0

    init(capacity: Int = 24, maxAge: TimeInterval = 5, contentTTL: TimeInterval = 1) {
        cache = LRUImageCache(capacity: capacity, maxAge: maxAge)
        self.contentTTL = contentTTL
    }

    /// Returns a cached or freshly-captured thumbnail for `windowID`, scaled so its
    /// longest edge is at most `maxDimension` points. `nil` when capture fails.
    func thumbnail(for windowID: CGWindowID, maxDimension: CGFloat) async -> NSImage? {
        let now = Date.timeIntervalSinceReferenceDate
        if let cached = cache.value(for: windowID, now: now) {
            return cached
        }

        let cgImage: CGImage?
        if #available(macOS 14.0, *) {
            cgImage = await captureModern(windowID: windowID, maxDimension: maxDimension)
        } else {
            cgImage = captureLegacy(windowID: windowID, maxDimension: maxDimension)
        }
        guard let cgImage else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.insert(image, for: windowID, now: Date.timeIntervalSinceReferenceDate)
        return image
    }

    /// Drops all cached thumbnails (e.g. when previews are turned off).
    func clear() {
        cache.removeAll()
        cachedContent = nil
        cachedContentAt = 0
    }

    // MARK: Capture backends

    /// Returns a recent shareable-content snapshot, reusing the cached one while it
    /// is still within `contentTTL`. Enumerating every on-screen window is the
    /// expensive part of a capture, so sharing one snapshot across a preview batch
    /// keeps the switcher's run loop responsive (an overloaded run loop gets the
    /// ⌘+Tab event tap disabled by timeout, dropping the commit on key release).
    @available(macOS 14.0, *)
    private func shareableContent() async -> SCShareableContent? {
        let now = Date.timeIntervalSinceReferenceDate
        if let content = cachedContent as? SCShareableContent, now - cachedContentAt < contentTTL {
            return content
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }
        cachedContent = content
        cachedContentAt = Date.timeIntervalSinceReferenceDate
        return content
    }

    @available(macOS 14.0, *)
    private func captureModern(windowID: CGWindowID, maxDimension: CGFloat) async -> CGImage? {
        guard
            let content = await shareableContent(),
            let window = content.windows.first(where: { $0.windowID == windowID })
        else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Width/height are kept proportional to the window so the capture scales
        // uniformly without distortion.
        let scale = Self.scaleFactor(for: window.frame.size, maxDimension: maxDimension)
        config.width = max(1, Int((window.frame.width * scale).rounded()))
        config.height = max(1, Int((window.frame.height * scale).rounded()))
        config.showsCursor = false

        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// `CGWindowListCreateImage` is deprecated in macOS 14 but is the only
    /// screenshot path on macOS 13, where `SCScreenshotManager` is unavailable.
    /// It cannot size its capture, so the result is downsampled before it can be
    /// wrapped in an `NSImage` and cached — otherwise every cached thumbnail
    /// holds a full-resolution bitmap.
    @available(macOS, deprecated: 14.0)
    private func captureLegacy(windowID: CGWindowID, maxDimension: CGFloat) -> CGImage? {
        guard let captured = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                                     [.boundsIgnoreFraming, .nominalResolution]) else {
            return nil
        }
        return Self.downsample(captured, maxDimension: maxDimension)
    }

    /// Returns `image` scaled so its longest edge is at most `maxDimension`
    /// pixels — exposed for unit testing. An image that already fits is returned
    /// unchanged (no upscaling, no reallocation). `nil` when `maxDimension` is
    /// not finite or is below 1, or when the output context cannot be allocated;
    /// callers must not substitute the full-size original.
    static func downsample(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
        guard maxDimension.isFinite, maxDimension >= 1 else { return nil }

        // Fractional limits can't be met exactly: rounding a scaled pixel count
        // up would exceed the promise, so the limit is floored to whole pixels.
        let limit = maxDimension.rounded(.down)
        let size = CGSize(width: image.width, height: image.height)
        let scale = scaleFactor(for: size, maxDimension: limit)
        guard scale < 1 else { return image }

        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Downscale factor that fits `size`'s longest edge within `maxDimension`
    /// (never upscales).
    private static func scaleFactor(for size: CGSize, maxDimension: CGFloat) -> CGFloat {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return 1 }
        return maxDimension / longest
    }
}
