import AppKit
import Combine
import CoreGraphics

/// Resolves a bundle identifier to the artwork the switcher should draw, and is
/// the only part of this feature the ⌘-Tab hot path touches (`UNJAILED.md §8.2`).
///
/// The rule is that `icon(forBundleID:)` costs a dictionary lookup and nothing
/// else. Everything expensive — reading a bundle, decoding, resampling — happens
/// on a background queue, either warmed at launch or kicked off by the first miss.
/// A miss returns `nil`, which the caller reads as "use the system icon", so the
/// switcher never blocks and never waits on I/O.
///
/// Masters are not kept in memory: 40 apps at 1024² RGBA would be 160 MB, so each
/// icon is resampled to its display size before being cached and re-resolved when
/// the icon size changes.
final class IconResolver {

    /// What Settings shows about one app's artwork.
    struct Status: Equatable {
        /// The shape of the app's own artwork, or `nil` when none was readable.
        var shape: IconShape?
        /// Whether the user has supplied a file for this app.
        var hasCustomIcon: Bool
        /// Whether this app is pinned to the system icon.
        var isPinnedToSystemIcon: Bool

        var label: String {
            if isPinnedToSystemIcon { return "System icon" }
            if hasCustomIcon { return "Custom icon" }
            guard let shape else { return "No original artwork found" }
            return shape.label
        }
    }

    /// Corner rounding applied to full-bleed artwork so an un-masked square icon
    /// doesn't read as the only hard-cornered thing on screen (`UNJAILED.md §4.2`).
    /// A fixed fraction of the shorter edge for now — §8.4 wants it on the
    /// Appearance tab alongside the other layout controls, which is phase 2.
    static let fullBleedCornerRadiusFraction = 0.225

    let store: IconStore

    private let queue = DispatchQueue(label: "com.zapapp.icon-resolver", qos: .utility)
    private let lock = NSLock()
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    /// A resolved icon, or a resolved *absence* of one — distinguishing "we looked
    /// and there's nothing" from "we haven't looked yet".
    private enum Resolution {
        case useSystemIcon
        case image(NSImage)
    }

    private var cache: [String: Resolution] = [:]
    private var inFlight: Set<String> = []
    /// Every bundle identifier seen, so an invalidation can re-warm them all
    /// rather than waiting for each to be missed again.
    private var known: Set<String> = []
    /// Bumped on every invalidation. Work enqueued under an older generation is
    /// discarded when it lands, so a resolve started before an icon-size change
    /// can't overwrite the cache with an icon at the old size.
    private var generation = 0

    /// Mirrors of main-thread-owned state, so background resolution never reads
    /// `Preferences` or `NSScreen` off the main thread.
    private var mode: IconSourceMode
    private var iconSize: Double
    private var targetPixelSize: Int
    private var backingScale: CGFloat

    // MARK: Lifecycle

    init(preferences: Preferences, store: IconStore = IconStore()) {
        let scale = Self.maximumBackingScale()
        self.store = store
        self.mode = preferences.iconSourceMode
        self.iconSize = preferences.iconSize
        self.backingScale = scale
        self.targetPixelSize = Self.pixelSize(forIconSize: preferences.iconSize, scale: scale)

        // `dropFirst` on both: a `@Published` publisher replays its current value
        // on subscribe, and both are already mirrored above.

        // The source mode changes what gets drawn, so it invalidates immediately.
        preferences.$iconSourceMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.apply(mode: mode)
            }
            .store(in: &cancellables)

        // Icon size only changes the resolution icons are cached at. Debounced
        // because it's driven by a slider.
        preferences.$iconSize
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] iconSize in
                self?.apply(iconSize: iconSize)
            }
            .store(in: &cancellables)

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            self?.warm(bundleIDs: [bundleID])
        }

        // Plugging in a sharper display makes every cached icon too soft for it,
        // and the icon size alone would never notice.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshTargetSize()
        }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: Hot path

    /// The artwork to draw for `bundleID`, or `nil` to fall back to the system
    /// icon. A dictionary lookup; a miss schedules the work and returns `nil`.
    func icon(forBundleID bundleID: String) -> NSImage? {
        lock.lock()
        known.insert(bundleID)
        let cached = cache[bundleID]
        var pendingGeneration: Int?
        if cached == nil, !inFlight.contains(bundleID) {
            inFlight.insert(bundleID)
            pendingGeneration = generation
        }
        lock.unlock()

        if let pendingGeneration { enqueueResolve(bundleID, generation: pendingGeneration) }

        if case .image(let image)? = cached { return image }
        return nil
    }

    /// Resolves `bundleIDs` ahead of time so the first ⌘-Tab after launch already
    /// has them.
    func warm(bundleIDs: [String]) {
        var pending: [String] = []
        lock.lock()
        let generation = self.generation
        for bundleID in bundleIDs {
            known.insert(bundleID)
            guard cache[bundleID] == nil, !inFlight.contains(bundleID) else { continue }
            inFlight.insert(bundleID)
            pending.append(bundleID)
        }
        lock.unlock()

        for bundleID in pending { enqueueResolve(bundleID, generation: generation) }
    }

    /// Drops cached artwork. Pass a bundle identifier to invalidate one app (after
    /// the user changes its icon), or `nil` for all of them.
    func invalidate(bundleID: String? = nil) {
        var toWarm: [String] = []
        lock.lock()
        // Retire everything already in flight along with the cached values: those
        // results were computed for the settings we just left.
        generation &+= 1
        inFlight.removeAll()
        if let bundleID {
            cache[bundleID] = nil
            toWarm = [bundleID]
        } else {
            cache.removeAll()
            toWarm = Array(known)
        }
        lock.unlock()

        warm(bundleIDs: toWarm)
    }

    // MARK: Settings

    /// Describes one app's artwork. Decodes the bundle's icon, so it blocks —
    /// call it off the main thread.
    func status(forBundleID bundleID: String) -> Status {
        let entry = store.entry(forBundleID: bundleID)
        if entry?.origin == .system {
            return Status(shape: nil, hasCustomIcon: false, isPinnedToSystemIcon: true)
        }
        if store.imageURL(forBundleID: bundleID) != nil {
            return Status(shape: nil, hasCustomIcon: true, isPinnedToSystemIcon: false)
        }
        let shape = BundleArtwork.image(forBundleID: bundleID).map { IconShapeClassifier.classify($0) }
        return Status(shape: shape, hasCustomIcon: false, isPinnedToSystemIcon: false)
    }

    /// Describes several apps at once, off the main thread, calling `completion`
    /// back on the main queue.
    func statuses(forBundleIDs bundleIDs: [String], completion: @escaping ([String: Status]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var result: [String: Status] = [:]
            for bundleID in bundleIDs {
                result[bundleID] = self.status(forBundleID: bundleID)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: Resolution

    private func enqueueResolve(_ bundleID: String, generation: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            let resolution = self.resolve(bundleID)
            self.lock.lock()
            // Dropped wholesale if an invalidation happened while this was in
            // flight — including the in-flight marker, which by then belongs to
            // whatever re-warm replaced it.
            if generation == self.generation {
                self.cache[bundleID] = resolution
                self.inFlight.remove(bundleID)
            }
            self.lock.unlock()
        }
    }

    /// The resolution ladder from `UNJAILED.md §3`, first hit wins.
    private func resolve(_ bundleID: String) -> Resolution {
        lock.lock()
        let mode = self.mode
        let pixelSize = self.targetPixelSize
        let scale = self.backingScale
        lock.unlock()

        guard mode.usesBundleArtwork else { return .useSystemIcon }
        // A per-app pin opts this app out entirely.
        guard !store.isPinnedToSystemIcon(bundleID) else { return .useSystemIcon }

        var artwork: CGImage?
        var isCustom = false

        if mode.usesCustomIcons, let custom = store.customImage(forBundleID: bundleID) {
            artwork = custom
            isCustom = true
        }
        if artwork == nil {
            artwork = BundleArtwork.image(forBundleID: bundleID)
        }
        guard var image = artwork else { return .useSystemIcon }

        // A user-chosen file is taken at face value; the app's own artwork is
        // classified so a modern full-bleed square doesn't come back hard-cornered.
        if !isCustom {
            let shape = IconShapeClassifier.classify(image)
            guard shape.isWorthSubstituting else { return .useSystemIcon }
            if shape.needsCornerMask {
                image = Self.maskingCorners(image, radiusFraction: Self.fullBleedCornerRadiusFraction)
            }
        }

        let sized = Self.downsample(image, longestEdge: pixelSize)
        let points = NSSize(width: CGFloat(sized.width) / scale, height: CGFloat(sized.height) / scale)
        return .image(NSImage(cgImage: sized, size: points))
    }

    // MARK: Main-thread state

    private func apply(mode: IconSourceMode) {
        lock.lock()
        self.mode = mode
        lock.unlock()
        invalidate()
    }

    private func apply(iconSize: Double) {
        lock.lock()
        self.iconSize = iconSize
        lock.unlock()
        refreshTargetSize()
    }

    /// Recomputes the resolution icons are cached at, from the current icon size
    /// and the sharpest attached display. Invalidates only when it really changed,
    /// so an irrelevant display change doesn't throw the cache away.
    ///
    /// Main thread only — `NSScreen` is.
    private func refreshTargetSize() {
        let scale = Self.maximumBackingScale()
        lock.lock()
        let pixelSize = Self.pixelSize(forIconSize: iconSize, scale: scale)
        let unchanged = pixelSize == targetPixelSize && scale == backingScale
        targetPixelSize = pixelSize
        backingScale = scale
        lock.unlock()

        guard !unchanged else { return }
        invalidate()
    }

    /// Pixels an icon needs at `iconSize` points on the sharpest attached display,
    /// rounded up to a whole pixel and never below a floor that keeps a
    /// small-icon-size setting from caching something unusably soft.
    static func pixelSize(forIconSize iconSize: Double, scale: CGFloat) -> Int {
        let pixels = Int((iconSize * Double(max(scale, 1))).rounded(.up))
        return max(IconImageValidator.Limits.warnBelowPixels, pixels)
    }

    /// Must be called on the main thread — `NSScreen` is main-thread-only.
    private static func maximumBackingScale() -> CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    // MARK: Image work

    /// Resamples `image` so its longest edge is `longestEdge`, never upscaling.
    static func downsample(_ image: CGImage, longestEdge: Int) -> CGImage {
        let sourceLongest = max(image.width, image.height)
        guard longestEdge > 0, sourceLongest > longestEdge else { return image }

        let scale = Double(longestEdge) / Double(sourceLongest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = makeContext(width: width, height: height) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage() ?? image
    }

    /// Clips `image` to a rounded rectangle, for full-bleed artwork that would
    /// otherwise be the only hard-cornered thing in the row.
    static func maskingCorners(_ image: CGImage, radiusFraction: Double) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let context = makeContext(width: width, height: height) else {
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let radius = CGFloat(radiusFraction) * min(rect.width, rect.height)
        context.interpolationQuality = .high
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    /// An sRGB bitmap context with alpha, so everything downstream — the alpha
    /// classifier included — works in a known colour space (`UNJAILED.md §6.4`).
    private static func makeContext(width: Int, height: Int) -> CGContext? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil, width: width, height: height,
                         bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
