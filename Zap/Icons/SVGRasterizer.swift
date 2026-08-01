import CoreGraphics
import WebKit

/// Turns SVG markup into a bitmap, via an offscreen `WKWebView` (`UNJAILED.md §6.3`).
///
/// `NSImage` can't decode SVG and neither can ImageIO, which leaves four options.
/// Bundling SVGKit/librsvg/resvg is out (`AGENTS.md`: no heavy dependencies).
/// CoreSVG's `CGSVGDocumentCreateFromData` works and the repo already tolerates
/// some SPI, but it is undocumented and throws on gradients. A web view is public
/// API, roughly the same amount of code, and renders what a browser renders.
///
/// Rendering fetched SVG means parsing untrusted markup, so: JavaScript off, a
/// navigation delegate that denies everything after the initial in-memory load,
/// and no persistent data store. It runs once per icon inside a Settings sheet —
/// never on the switcher's hot path — and the result is baked to PNG on disk, so
/// the cost is paid exactly once.
final class SVGRasterizer: NSObject, WKNavigationDelegate {

    enum RasterizeError: Error, Equatable {
        case notSVG
        case timedOut
        case snapshotFailed

        var message: String {
            switch self {
            case .notSVG: return "That file doesn't look like an SVG."
            case .timedOut: return "Rendering that SVG took too long."
            case .snapshotFailed: return "Zap couldn't render that SVG."
            }
        }
    }

    /// How long a single render may take before it's abandoned.
    static let timeout: TimeInterval = 10

    // MARK: Pure helpers

    /// Whether `data` plausibly contains SVG markup. Sniffed from the bytes rather
    /// than trusted from an extension or a `Content-Type`, same as every other
    /// format decision in this feature (§6.1).
    static func isSVG(_ data: Data) -> Bool {
        // A generous prefix: an SVG may open with an XML declaration, a doctype,
        // comments, or a byte-order mark before the `<svg` tag.
        let prefix = data.prefix(4096)
        guard let text = String(data: prefix, encoding: .utf8) else { return false }
        return text.range(of: "<svg", options: [.caseInsensitive]) != nil
    }

    /// Wraps SVG markup in a minimal document that scales it to fill the viewport
    /// on a transparent background.
    static func htmlDocument(forSVG svg: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
        html,body{margin:0;padding:0;background:transparent;overflow:hidden}
        svg{width:100vw;height:100vh;display:block}
        </style></head><body>\(svg)</body></html>
        """
    }

    // MARK: Rasterising

    /// Renders `data` into a square bitmap of `side` points. `completion` is called
    /// on the main queue, exactly once.
    static func rasterize(_ data: Data,
                          side: Int = IconImageValidator.Limits.masterLongestEdge,
                          completion: @escaping (Result<CGImage, RasterizeError>) -> Void) {
        guard isSVG(data), let markup = String(data: data, encoding: .utf8) else {
            DispatchQueue.main.async { completion(.failure(.notSVG)) }
            return
        }
        DispatchQueue.main.async {
            // `WKWebView` is main-thread-only, and the instance has to outlive this
            // scope — it is its own delegate for the duration, so it holds itself
            // until `finish` lets go.
            SVGRasterizer(side: side).start(markup: markup, completion: completion)
        }
    }

    /// `async` convenience over the same one-shot render.
    static func rasterize(_ data: Data,
                          side: Int = IconImageValidator.Limits.masterLongestEdge)
    async -> Result<CGImage, RasterizeError> {
        await withCheckedContinuation { continuation in
            rasterize(data, side: side) { continuation.resume(returning: $0) }
        }
    }

    private let side: Int
    private var webView: WKWebView?
    private var completion: ((Result<CGImage, RasterizeError>) -> Void)?
    private var selfRetain: SVGRasterizer?
    private var hasAllowedInitialLoad = false

    private init(side: Int) {
        self.side = max(16, side)
        super.init()
    }

    /// Main queue only.
    private func start(markup: String,
                       completion: @escaping (Result<CGImage, RasterizeError>) -> Void) {
        self.completion = completion
        self.selfRetain = self

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: side, height: side),
                                configuration: configuration)
        webView.navigationDelegate = self
        // So the snapshot carries the SVG's own transparency rather than the web
        // view's default white page.
        webView.underPageBackgroundColor = .clear
        self.webView = webView

        // `baseURL: nil` leaves the document with no origin and nothing to resolve
        // a relative URL against, which is the property §6.3 wants from `data:`.
        webView.loadHTMLString(Self.htmlDocument(forSVG: markup), baseURL: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            self?.finish(.failure(.timedOut))
        }
    }

    /// Main queue only. Safe to call more than once; only the first lands.
    private func finish(_ result: Result<CGImage, RasterizeError>) {
        guard let completion else { return }
        self.completion = nil
        webView?.navigationDelegate = nil
        webView = nil
        completion(result)
        selfRetain = nil
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Exactly one navigation is permitted: the in-memory document we just
        // handed it. Untrusted markup gets no second one, and no network.
        if hasAllowedInitialLoad {
            decisionHandler(.cancel)
        } else {
            hasAllowedInitialLoad = true
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: side, height: side)
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self else { return }
            var proposed = CGRect(x: 0, y: 0, width: self.side, height: self.side)
            guard let cgImage = image?.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
                self.finish(.failure(.snapshotFailed))
                return
            }
            self.finish(.success(cgImage))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(.snapshotFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        finish(.failure(.snapshotFailed))
    }
}
