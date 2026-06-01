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

    init(capacity: Int = 24, maxAge: TimeInterval = 5) {
        cache = LRUImageCache(capacity: capacity, maxAge: maxAge)
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
            cgImage = captureLegacy(windowID: windowID)
        }
        guard let cgImage else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.insert(image, for: windowID, now: Date.timeIntervalSinceReferenceDate)
        return image
    }

    /// Drops all cached thumbnails (e.g. when previews are turned off).
    func clear() {
        cache.removeAll()
    }

    // MARK: Capture backends

    @available(macOS 14.0, *)
    private func captureModern(windowID: CGWindowID, maxDimension: CGFloat) async -> CGImage? {
        guard
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
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
    @available(macOS, deprecated: 14.0)
    private func captureLegacy(windowID: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .nominalResolution])
    }

    /// Downscale factor that fits `size`'s longest edge within `maxDimension`
    /// (never upscales).
    private static func scaleFactor(for size: CGSize, maxDimension: CGFloat) -> CGFloat {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return 1 }
        return maxDimension / longest
    }
}
