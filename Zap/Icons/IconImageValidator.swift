import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The format, dimension and safety gate every image passes through before Zap
/// will store or draw it (`UNJAILED.md §6`).
///
/// Zap is unsandboxed and holds Accessibility permission, so ImageIO parsing a
/// file the user dragged in is an in-process parse of untrusted data. The
/// mitigations here are the pragmatic floor described in §6.4: read the header
/// before allocating anything, bound the decode with a thumbnail rather than
/// trusting the header, cap the source size, and re-encode to PNG on save so
/// nothing of the original container survives on disk.
enum IconImageValidator {

    // MARK: Limits

    enum Limits {
        /// Below this an icon is unusably mushy at any switcher size.
        static let hardMinimumPixels = 64
        /// Below this the user gets a warning but the icon is still accepted.
        static let warnBelowPixels = 128
        /// Refuse anything claiming more than this on either axis before decoding.
        static let maximumPixelsPerAxis = 8192
        /// Decompression-bomb guard: 40 MP, checked from the header.
        static let maximumTotalPixels = 40_000_000
        /// Sanity cap on the source file.
        static let maximumSourceBytes = 10 * 1024 * 1024
        /// Longest edge of the master Zap keeps on disk. `iconSize` tops out at
        /// 256 pt, so 512 px covers the worst case at 2× with headroom.
        static let masterLongestEdge = 1024
        /// A 10:1 banner destroys the icon row's rhythm; keep it near square.
        static let minimumAspectRatio = 0.5
        static let maximumAspectRatio = 2.0
    }

    // MARK: Results

    /// Why an image was refused. `Equatable` so tests can assert the exact reason.
    enum Rejection: Error, Equatable {
        /// No decoder, no frames, or unreadable bytes.
        case unreadable
        /// The source file is over `Limits.maximumSourceBytes`.
        case fileTooLarge(bytes: Int)
        /// Under `Limits.hardMinimumPixels` on an axis.
        case tooSmall(width: Int, height: Int)
        /// Over `Limits.maximumPixelsPerAxis` on an axis.
        case tooLarge(width: Int, height: Int)
        /// Over `Limits.maximumTotalPixels` in total.
        case tooManyPixels(count: Int)
        /// Outside 1:2 … 2:1.
        case extremeAspectRatio(ratio: Double)
        /// The decoded image couldn't be written back out as PNG.
        case notEncodable
        /// SVG markup that wouldn't render. Carries the rasteriser's own reason,
        /// which distinguishes "took too long" from "came back blank" — ImageIO
        /// never sees these bytes, so none of the cases above can describe them.
        case svgNotRendered(reason: String)

        var message: String {
            switch self {
            case .unreadable:
                return "That file isn't an image Zap can read."
            case .fileTooLarge(let bytes):
                return "That file is \(bytes / (1024 * 1024)) MB. The limit is \(Limits.maximumSourceBytes / (1024 * 1024)) MB."
            case .tooSmall(let width, let height):
                return "That image is \(width)×\(height). Icons need to be at least \(Limits.hardMinimumPixels)×\(Limits.hardMinimumPixels)."
            case .tooLarge(let width, let height):
                return "That image is \(width)×\(height), past the \(Limits.maximumPixelsPerAxis) px limit."
            case .tooManyPixels:
                return "That image has too many pixels to decode safely."
            case .extremeAspectRatio:
                return "That image is too far from square to sit in the icon row."
            case .notEncodable:
                return "Zap couldn't convert that image to PNG."
            case .svgNotRendered(let reason):
                return reason
            }
        }
    }

    /// What the header said about an accepted image.
    struct Measurements: Equatable {
        var pixelWidth: Int
        var pixelHeight: Int
        /// Accepted, but under `Limits.warnBelowPixels` on an axis — worth telling
        /// the user it will look soft.
        var isLowResolution: Bool
        /// Without alpha there is nothing to un-jail: the result is a rectangle,
        /// just a differently-shaped one. Worth saying so in the UI.
        var hasAlpha: Bool
    }

    // MARK: Pure checks

    /// The §6.2 accept/reject table, as pure arithmetic over what an image header
    /// claims. Runs before any pixels are allocated.
    static func check(pixelWidth: Int, pixelHeight: Int,
                      byteCount: Int? = nil, hasAlpha: Bool = true) -> Result<Measurements, Rejection> {
        if let byteCount, byteCount > Limits.maximumSourceBytes {
            return .failure(.fileTooLarge(bytes: byteCount))
        }
        guard pixelWidth > 0, pixelHeight > 0 else {
            return .failure(.unreadable)
        }
        guard pixelWidth >= Limits.hardMinimumPixels, pixelHeight >= Limits.hardMinimumPixels else {
            return .failure(.tooSmall(width: pixelWidth, height: pixelHeight))
        }
        guard pixelWidth <= Limits.maximumPixelsPerAxis, pixelHeight <= Limits.maximumPixelsPerAxis else {
            return .failure(.tooLarge(width: pixelWidth, height: pixelHeight))
        }
        // Checked separately from the per-axis cap: 8000 × 8000 clears both axes
        // and is still 64 MP.
        guard pixelWidth * pixelHeight <= Limits.maximumTotalPixels else {
            return .failure(.tooManyPixels(count: pixelWidth * pixelHeight))
        }

        let ratio = Double(pixelWidth) / Double(pixelHeight)
        guard ratio >= Limits.minimumAspectRatio, ratio <= Limits.maximumAspectRatio else {
            return .failure(.extremeAspectRatio(ratio: ratio))
        }

        return .success(Measurements(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isLowResolution: pixelWidth < Limits.warnBelowPixels || pixelHeight < Limits.warnBelowPixels,
            hasAlpha: hasAlpha))
    }

    // MARK: Decoding

    /// Validates and decodes the image at `url`, bounded to the stored master
    /// size. The type is taken from the decoded data, never from the extension.
    static func decode(contentsOf url: URL) -> Result<CGImage, Rejection> {
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let byteCount, byteCount > Limits.maximumSourceBytes {
            return .failure(.fileTooLarge(bytes: byteCount))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return .failure(.unreadable)
        }
        return decode(source: source, byteCount: byteCount)
    }

    /// Validates and decodes in-memory image data, bounded to the stored master size.
    static func decode(data: Data) -> Result<CGImage, Rejection> {
        guard data.count <= Limits.maximumSourceBytes else {
            return .failure(.fileTooLarge(bytes: data.count))
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return .failure(.unreadable)
        }
        return decode(source: source, byteCount: data.count)
    }

    /// Measures an image without decoding it — the header check on its own.
    static func measure(contentsOf url: URL) -> Result<Measurements, Rejection> {
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let frame = largestFrame(in: source) else {
            return .failure(.unreadable)
        }
        return check(pixelWidth: frame.width, pixelHeight: frame.height,
                     byteCount: byteCount, hasAlpha: frame.hasAlpha)
    }

    private static func decode(source: CGImageSource, byteCount: Int?) -> Result<CGImage, Rejection> {
        guard let frame = largestFrame(in: source) else { return .failure(.unreadable) }

        // Header check first: reject oversize images before allocating pixels.
        switch check(pixelWidth: frame.width, pixelHeight: frame.height,
                     byteCount: byteCount, hasAlpha: frame.hasAlpha) {
        case .failure(let rejection):
            return .failure(rejection)
        case .success:
            break
        }

        // Decode through a thumbnail so the output allocation is bounded by what
        // we asked for rather than by what the header claimed. Never upscales:
        // a source smaller than the master size comes back at its own size.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Limits.masterLongestEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, frame.index, thumbnailOptions as CFDictionary) else {
            return .failure(.unreadable)
        }
        return .success(image)
    }

    // MARK: Encoding

    /// Re-encodes `image` as PNG at `url`. What lands on disk is then Zap's own
    /// output, so the source container's metadata, colour-profile oddities and any
    /// format-specific payload never persist (`UNJAILED.md §6.4`).
    static func writePNG(_ image: CGImage, to url: URL) -> Result<Void, Rejection> {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return .failure(.notEncodable)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return .failure(.notEncodable) }
        return .success(())
    }

    // MARK: Frames

    /// One frame of a multi-representation image, as reported by its header.
    struct Frame: Equatable {
        var index: Int
        var width: Int
        var height: Int
        var hasAlpha: Bool
    }

    /// The largest representation in `source` by pixel count.
    ///
    /// `.icns` files carry every size from 16 px up in one container, and app
    /// bundles are full of them (`UNJAILED.md §6.1`), so taking index 0 would
    /// often mean taking a 16 px icon.
    static func largestFrame(in source: CGImageSource) -> Frame? {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var best: Frame?
        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0 else { continue }
            let frame = Frame(index: index, width: width, height: height,
                              hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false)
            if let current = best, current.width * current.height >= width * height { continue }
            best = frame
        }
        return best
    }

    /// Shared source options: don't populate Core Graphics' image cache for
    /// something we are about to resample and throw away.
    private static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as [CFString: Any] as CFDictionary
    }
}
