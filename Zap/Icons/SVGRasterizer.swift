import AppKit
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
/// Rendering fetched SVG means parsing untrusted markup, so: JavaScript off, no
/// persistent data store, a navigation delegate that permits exactly one page
/// navigation, and — the part navigation policy does *not* cover — a **Content
/// Security Policy** forbidding every network subresource.
///
/// That last one matters. `decidePolicyFor` only sees page-level navigations, so
/// on its own it would let `<image href="https://tracker/pixel.png">`, a CSS
/// `url(…)` or `<use href="https://…">` inside a hostile SVG fire silently and
/// leak the user's IP. `default-src 'none'` is what actually makes "nothing but
/// the markup we handed it" true.
///
/// This was a `WKContentRuleList` first, and that shipped broken: compiling one
/// can simply fail on a given machine, which it did, and the fail-closed branch
/// then refused *every* SVG. A policy carried in the document has no compile step,
/// no on-disk store and no async path that can fail — it either parses with the
/// document or there is no document. Fewer ways to be wrong, same guarantee, and
/// it is the mechanism the web platform provides for exactly this.
///
/// It runs once per icon inside a Settings sheet — never on the switcher's hot
/// path — and the result is baked to PNG on disk, so the cost is paid once.
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

    /// How long the document may take to load before the render is abandoned.
    static let timeout: TimeInterval = 10

    /// How long the render itself may take, once the page is up. Shorter, because
    /// by then the work left is a single capture.
    static let renderTimeout: TimeInterval = 5

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

    /// Forbids every subresource the markup might reach for.
    ///
    /// `default-src 'none'` covers images, fonts, stylesheets, `<use href="https://…">`
    /// and anything else with a URL. The exceptions are all sources that cannot
    /// reach the network, and that is the whole rule:
    ///
    /// - `style-src 'unsafe-inline'` — the wrapper's own `<style>` block is inline,
    ///   and so are an SVG's, which can't fetch anything on their own.
    /// - `img-src data:` and `font-src data:` — a `data:` URI is bytes already in
    ///   hand, not a request. Artwork that embeds a bitmap or self-contains its
    ///   typeface still draws; drop `font-src` and an SVG with `@font-face` full of
    ///   base64 renders in the wrong face with nothing to say why.
    ///
    /// Anything naming a scheme or a host belongs in neither list.
    ///
    /// `base-uri` and `form-action` are spelled out because they are the two
    /// directives that do **not** fall back to `default-src`. Nothing here can
    /// exploit their absence today — a `<base>` in `<body>` is ignored by the
    /// parser, its consequences would hit `default-src` anyway, and submitting a
    /// form needs either JavaScript or a click, neither of which a headless render
    /// has. They are named so the policy states the whole guarantee by itself,
    /// rather than resting on conditions kept three methods away that could each
    /// change without anyone rereading this line.
    static let contentSecurityPolicy = "default-src 'none'; base-uri 'none'; "
        + "form-action 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:"

    /// Wraps SVG markup in a minimal document that scales it to fill the viewport
    /// on a transparent background.
    ///
    /// The policy goes first in `<head>`, before anything that could load: a `<meta>`
    /// CSP applies from the point the parser reads it, so putting it after the markup
    /// would be decoration.
    static func htmlDocument(forSVG svg: String) -> String {
        """
        <!DOCTYPE html><html><head>\
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta charset="utf-8">
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
    /// Keeps `webView` in a window for the length of the render — see `hostWindow(for:)`.
    private var host: NSWindow?
    private var completion: ((Result<CGImage, RasterizeError>) -> Void)?
    private var selfRetain: SVGRasterizer?
    private var timeoutWork: DispatchWorkItem?
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
        self.host = Self.hostWindow(for: webView, side: side)

        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(.timedOut)) }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: timeout)

        // `baseURL: nil` leaves the document with no origin and nothing to resolve
        // a relative URL against — the property §6.3 wants from `data:`. The
        // document carries its own Content Security Policy, so there is nothing to
        // set up first and no way for this to be reached unprotected.
        webView.loadHTMLString(Self.htmlDocument(forSVG: markup), baseURL: nil)
    }

    /// Parks `webView` in a window, because a detached one renders nothing.
    ///
    /// WebKit only paints a web view that belongs to a window, and it stops
    /// painting for windows the system treats as invisible. A `WKWebView` built
    /// with a frame and never added to anything therefore loads the document,
    /// reports `didFinish`, and hands back an empty `takeSnapshot` — which is what
    /// left every icon-search preview spinning forever with nothing to show.
    ///
    /// So it gets a real window, ordered in so it can't be dismissed as occluded,
    /// but borderless, transparent, click-through, kept out of window cycling,
    /// pinned below the desktop and parked far off every screen. It renders; it
    /// cannot be seen, hit, or cycled to.
    private static func hostWindow(for webView: WKWebView, side: Int) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: side, height: side),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .ignoresCycle]
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        // Ordered *back*: it joins the window list without becoming key, so the
        // Settings sheet the user is looking at keeps focus.
        window.orderBack(nil)
        return window
    }

    /// Main queue only. Safe to call more than once; only the first lands.
    private func finish(_ result: Result<CGImage, RasterizeError>) {
        guard let completion else { return }
        self.completion = nil
        // Stop the deadline from firing over a snapshot that is already in flight.
        timeoutWork?.cancel()
        timeoutWork = nil
        webView?.navigationDelegate = nil
        // Take the window down before letting go of the view it hosts, so nothing
        // is left ordered in on a render that timed out.
        host?.orderOut(nil)
        host?.contentView = nil
        host = nil
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
        // The page is up, so the load deadline is the wrong one to be holding — but
        // dropping it outright would leave the render with no escape hatch, and a
        // wedged one would then retain this rasterizer (and its web view) for the
        // rest of the session, stalling the preview loop that awaits it. Swap it
        // for a shorter one instead: still fails closed, just on the right clock.
        timeoutWork?.cancel()
        let renderDeadline = DispatchWorkItem { [weak self] in self?.finish(.failure(.timedOut)) }
        timeoutWork = renderDeadline
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.renderTimeout, execute: renderDeadline)

        // PDF rather than `takeSnapshot`, because a snapshot comes back composited
        // on opaque white. Every icon then reads as `.fullBleed` to the alpha
        // classifier and gets corner-masked into a white tile — which is what an
        // SVG with nothing but a `<path>` in it looked like.
        //
        // A PDF page carries only the marks the document actually drew, so the
        // alpha is decided by the context it is drawn into, and that context is
        // ours. Public API either way; this one just doesn't paint a background
        // nobody asked for.
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: side, height: side)
        webView.createPDF(configuration: configuration) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                // Logged, not swallowed. Every one of these failures looks identical
                // in the UI — a picture that didn't draw — and telling them apart
                // from the outside cost a release once already.
                NSLog("Zap: SVG PDF render failed: %@", error.localizedDescription)
                self.finish(.failure(.snapshotFailed))
            case .success(let data):
                guard let image = Self.image(fromPDF: data, side: self.side) else {
                    NSLog("Zap: SVG PDF had no drawable page")
                    self.finish(.failure(.snapshotFailed))
                    return
                }
                self.finish(.success(image))
            }
        }
    }

    /// Draws the first page of `data` into a transparent square bitmap.
    ///
    /// The transparency is this function's, not WebKit's: `IconRenderer.makeContext`
    /// hands back a cleared sRGB context with an alpha channel, and a PDF page adds
    /// only what the document drew. Nothing paints the background because nothing
    /// in the document ever did.
    ///
    /// Fitted rather than stretched — the page is centred at the largest scale that
    /// keeps it whole, so a non-square viewBox letterboxes into transparency instead
    /// of distorting.
    static func image(fromPDF data: Data, side: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1),
              let context = IconRenderer.makeContext(width: side, height: side) else { return nil }

        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }

        let scale = min(CGFloat(side) / box.width, CGFloat(side) / box.height)
        context.translateBy(x: (CGFloat(side) - box.width * scale) / 2,
                            y: (CGFloat(side) - box.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.interpolationQuality = .high
        context.drawPDFPage(page)
        return context.makeImage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Zap: SVG navigation failed: %@", error.localizedDescription)
        finish(.failure(.snapshotFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("Zap: SVG load failed: %@", error.localizedDescription)
        finish(.failure(.snapshotFailed))
    }
}
