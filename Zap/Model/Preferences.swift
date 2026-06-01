import Foundation
import SwiftUI
import ServiceManagement

/// User-facing settings, backed by `UserDefaults`.
///
/// An `ObservableObject` so SwiftUI settings views update live. A custom
/// `UserDefaults` can be injected for tests.
final class Preferences: ObservableObject {

    static let shared = Preferences()

    private let defaults: UserDefaults

    // MARK: Defaults

    enum Default {
        static let backgroundColorHex = "#1C1C1E"
        static let highlightColorHex = "#0A84FF"
        static let labelColorHex = "#FFFFFF"
        static let backgroundOpacity = 0.55
        static let highlightOpacity = 0.85
        static let iconSize = 80.0
        static let cornerRadius = 18.0
        static let highlightCornerRadius = 14.0
        static let contentPadding = 20.0
        static let showDelayMs = 150.0
        static let windowDwellMs = 400.0
    }

    private enum Key {
        static let excluded = "excludedBundleIDs"
        static let backgroundColorHex = "backgroundColorHex"
        static let highlightColorHex = "highlightColorHex"
        static let labelColorHex = "labelColorHex"
        static let backgroundOpacity = "backgroundOpacity"
        static let highlightOpacity = "highlightOpacity"
        static let iconSize = "iconSize"
        static let cornerRadius = "cornerRadius"
        static let highlightCornerRadius = "highlightCornerRadius"
        static let contentPadding = "contentPadding"
        static let showAppName = "showAppName"
        static let showDelayMs = "showDelayMs"
        static let showWindowList = "showWindowList"
        static let showWindowPreviews = "showWindowPreviews"
        static let windowDwellMs = "windowDwellMs"
        static let launchAtLogin = "launchAtLogin"
        static let useAlternateHotkey = "useAlternateHotkey"
    }

    // MARK: Stored settings

    @Published var excludedBundleIDs: Set<String> {
        didSet { defaults.set(Array(excludedBundleIDs), forKey: Key.excluded) }
    }

    @Published var backgroundColorHex: String {
        didSet { defaults.set(backgroundColorHex, forKey: Key.backgroundColorHex) }
    }

    @Published var highlightColorHex: String {
        didSet { defaults.set(highlightColorHex, forKey: Key.highlightColorHex) }
    }

    @Published var labelColorHex: String {
        didSet { defaults.set(labelColorHex, forKey: Key.labelColorHex) }
    }

    @Published var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: Key.backgroundOpacity) }
    }

    @Published var highlightOpacity: Double {
        didSet { defaults.set(highlightOpacity, forKey: Key.highlightOpacity) }
    }

    @Published var iconSize: Double {
        didSet { defaults.set(iconSize, forKey: Key.iconSize) }
    }

    @Published var cornerRadius: Double {
        didSet { defaults.set(cornerRadius, forKey: Key.cornerRadius) }
    }

    /// Corner radius of the selection highlight behind the focused icon.
    @Published var highlightCornerRadius: Double {
        didSet { defaults.set(highlightCornerRadius, forKey: Key.highlightCornerRadius) }
    }

    /// Padding between the panel's background edge and its icon row.
    @Published var contentPadding: Double {
        didSet { defaults.set(contentPadding, forKey: Key.contentPadding) }
    }

    @Published var showAppName: Bool {
        didSet { defaults.set(showAppName, forKey: Key.showAppName) }
    }

    @Published var showDelayMs: Double {
        didSet { defaults.set(showDelayMs, forKey: Key.showDelayMs) }
    }

    /// Whether dwelling on an app reveals its windows below the switcher.
    @Published var showWindowList: Bool {
        didSet { defaults.set(showWindowList, forKey: Key.showWindowList) }
    }

    /// Whether each window row shows a small live preview of the window. Requires
    /// Screen Recording permission; off by default since it's an extra grant.
    @Published var showWindowPreviews: Bool {
        didSet { defaults.set(showWindowPreviews, forKey: Key.showWindowPreviews) }
    }

    /// How long the selection must rest on an app before its windows appear.
    @Published var windowDwellMs: Double {
        didSet { defaults.set(windowDwellMs, forKey: Key.windowDwellMs) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published var useAlternateHotkey: Bool {
        didSet { defaults.set(useAlternateHotkey, forKey: Key.useAlternateHotkey) }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let excludedArray = defaults.stringArray(forKey: Key.excluded) ?? []
        excludedBundleIDs = Set(excludedArray)

        backgroundColorHex = Self.validColor(defaults.string(forKey: Key.backgroundColorHex), default: Default.backgroundColorHex)
        highlightColorHex = Self.validColor(defaults.string(forKey: Key.highlightColorHex), default: Default.highlightColorHex)
        labelColorHex = Self.validColor(defaults.string(forKey: Key.labelColorHex), default: Default.labelColorHex)

        backgroundOpacity = Self.clamp(defaults.object(forKey: Key.backgroundOpacity) as? Double ?? Default.backgroundOpacity, 0, 1, Default.backgroundOpacity)
        highlightOpacity = Self.clamp(defaults.object(forKey: Key.highlightOpacity) as? Double ?? Default.highlightOpacity, 0, 1, Default.highlightOpacity)
        iconSize = Self.clamp(defaults.object(forKey: Key.iconSize) as? Double ?? Default.iconSize, 24, 256, Default.iconSize)
        cornerRadius = Self.clamp(defaults.object(forKey: Key.cornerRadius) as? Double ?? Default.cornerRadius, 0, 64, Default.cornerRadius)
        highlightCornerRadius = Self.clamp(defaults.object(forKey: Key.highlightCornerRadius) as? Double ?? Default.highlightCornerRadius, 0, 64, Default.highlightCornerRadius)
        contentPadding = Self.clamp(defaults.object(forKey: Key.contentPadding) as? Double ?? Default.contentPadding, 0, 60, Default.contentPadding)
        showAppName = defaults.object(forKey: Key.showAppName) as? Bool ?? true
        showDelayMs = Self.clamp(defaults.object(forKey: Key.showDelayMs) as? Double ?? Default.showDelayMs, 0, 1000, Default.showDelayMs)
        showWindowList = defaults.object(forKey: Key.showWindowList) as? Bool ?? true
        showWindowPreviews = defaults.object(forKey: Key.showWindowPreviews) as? Bool ?? false
        windowDwellMs = Self.clamp(defaults.object(forKey: Key.windowDwellMs) as? Double ?? Default.windowDwellMs, 50, 5000, Default.windowDwellMs)
        useAlternateHotkey = defaults.object(forKey: Key.useAlternateHotkey) as? Bool ?? false

        // Seed launch-at-login from the authoritative system state rather than a
        // possibly-stale stored value, so an external change in System Settings is
        // reflected in the UI.
        launchAtLogin = Self.systemLaunchAtLoginEnabled()
            ?? (defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false)
    }

    // MARK: Validation helpers

    /// Clamps `value` into `[lower, upper]`, falling back to `fallback` for
    /// non-finite (NaN/inf) input from corrupted defaults.
    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lower), upper)
    }

    /// Returns `hex` if it parses to a valid color, otherwise `default`.
    private static func validColor(_ hex: String?, default fallback: String) -> String {
        guard let hex, NSColor(hex: hex) != nil else { return fallback }
        return hex
    }

    /// The current login-item state from `SMAppService`, or `nil` if unavailable.
    private static func systemLaunchAtLoginEnabled() -> Bool? {
        guard #available(macOS 13.0, *) else { return nil }
        switch SMAppService.mainApp.status {
        case .enabled: return true
        case .notRegistered, .notFound: return false
        default: return nil
        }
    }


    // MARK: Exclusions

    func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ excluded: Bool, bundleID: String) {
        if excluded {
            excludedBundleIDs.insert(bundleID)
        } else {
            excludedBundleIDs.remove(bundleID)
        }
    }

    // MARK: Launch at login

    /// Guards `launchAtLogin.didSet` against re-entrancy when we roll the toggle
    /// back after a failed `SMAppService` call.
    private var isSyncingLaunchAtLogin = false

    /// The most recent launch-at-login error, surfaced to Settings.
    @Published private(set) var launchAtLoginError: String?

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            launchAtLoginError = nil
            defaults.set(enabled, forKey: Key.launchAtLogin)
        } catch {
            NSLog("Zap: failed to update launch-at-login: \(error.localizedDescription)")
            launchAtLoginError = error.localizedDescription
            // Roll the toggle back to the real system state so the UI doesn't lie.
            isSyncingLaunchAtLogin = true
            launchAtLogin = Self.systemLaunchAtLoginEnabled() ?? !enabled
            isSyncingLaunchAtLogin = false
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        }
    }

    /// Re-reads the authoritative login-item state (e.g. when Settings appears)
    /// so an external change in System Settings is reflected.
    func refreshLaunchAtLoginStatus() {
        guard let actual = Self.systemLaunchAtLoginEnabled(), actual != launchAtLogin else { return }
        isSyncingLaunchAtLogin = true
        launchAtLogin = actual
        isSyncingLaunchAtLogin = false
        defaults.set(actual, forKey: Key.launchAtLogin)
    }
}
