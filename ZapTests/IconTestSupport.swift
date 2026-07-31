import CoreGraphics
import Foundation
@testable import Zap

/// Shared fixtures for the icon tests: synthetic images, and app bundles built in
/// a temporary directory (`UNJAILED.md §9`).
enum IconTestSupport {

    // MARK: Images

    /// A solid rectangle (`filled`) or a centred ellipse, so tests can pick a
    /// full-bleed or a free-form shape.
    static func makeImage(width: Int, height: Int, filled: Bool = true) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        if filled {
            context.fill(rect)
        } else {
            context.fillEllipse(in: rect)
        }
        return context.makeImage()!
    }

    /// Writes a synthetic PNG, returning the URL. Fails the build of the fixture
    /// loudly rather than silently producing an unreadable file.
    @discardableResult
    static func writePNG(width: Int, height: Int, to url: URL, filled: Bool = true) -> URL {
        let image = makeImage(width: width, height: height, filled: filled)
        guard case .success = IconImageValidator.writePNG(image, to: url) else {
            fatalError("couldn't write the test PNG at \(url.path)")
        }
        return url
    }

    // MARK: Directories

    /// Callers must remove this in `tearDown`. `try!` rather than `try?` so a
    /// fixture that can't be set up fails as itself, instead of as a confusing
    /// "file not found" further downstream.
    static func makeTemporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ZapIconTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Bundles

    /// Builds a minimal app bundle: `Contents/Info.plist` plus whatever files the
    /// test wants in `Contents/Resources`.
    ///
    /// Real `.icns` encoding isn't needed for the resolution-order tests — those
    /// only ask which files a bundle *declares*, and existence is what decides
    /// that. Tests that actually load artwork use PNGs written by `writePNG`.
    @discardableResult
    static func makeBundle(named name: String, in directory: URL,
                           info: [String: Any],
                           resources: [String: Data] = [:]) throws -> URL {
        let bundleURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))

        for (fileName, contents) in resources {
            try contents.write(to: resourcesURL.appendingPathComponent(fileName))
        }
        return bundleURL
    }

    /// Placeholder bytes for a file whose *existence* is what a test is asserting.
    static let placeholderBytes = Data("not really an icns".utf8)
}

// MARK: - Result conveniences

/// Lives here rather than in one test file, since several of them use it.
extension Result {
    /// The success value, or `nil` — so a test can `XCTUnwrap` it. Named to stay
    /// clear of the `success`/`failure` cases themselves.
    var successValue: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }

    /// The failure value, or `nil`.
    var failureValue: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
