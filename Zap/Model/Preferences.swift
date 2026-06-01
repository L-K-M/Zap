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
        static let showDelayMs = 150.0
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
        static let showAppName = "showAppName"
        static let showDelayMs = "showDelayMs"
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

    @Published var showAppName: Bool {
        didSet { defaults.set(showAppName, forKey: Key.showAppName) }
    }

    @Published var showDelayMs: Double {
        didSet { defaults.set(showDelayMs, forKey: Key.showDelayMs) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
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

        backgroundColorHex = defaults.string(forKey: Key.backgroundColorHex) ?? Default.backgroundColorHex
        highlightColorHex = defaults.string(forKey: Key.highlightColorHex) ?? Default.highlightColorHex
        labelColorHex = defaults.string(forKey: Key.labelColorHex) ?? Default.labelColorHex

        backgroundOpacity = defaults.object(forKey: Key.backgroundOpacity) as? Double ?? Default.backgroundOpacity
        highlightOpacity = defaults.object(forKey: Key.highlightOpacity) as? Double ?? Default.highlightOpacity
        iconSize = defaults.object(forKey: Key.iconSize) as? Double ?? Default.iconSize
        cornerRadius = defaults.object(forKey: Key.cornerRadius) as? Double ?? Default.cornerRadius
        showAppName = defaults.object(forKey: Key.showAppName) as? Bool ?? true
        showDelayMs = defaults.object(forKey: Key.showDelayMs) as? Double ?? Default.showDelayMs
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        useAlternateHotkey = defaults.object(forKey: Key.useAlternateHotkey) as? Bool ?? false
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
        } catch {
            NSLog("Zap: failed to update launch-at-login: \(error.localizedDescription)")
        }
    }
}
