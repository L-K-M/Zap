import AppKit

/// Sets up the status-bar item, the switcher, and the settings window.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let preferences = Preferences.shared
    private lazy var switcher = SwitcherController(preferences: preferences)
    private lazy var settingsWindow = SettingsWindowController(preferences: preferences)

    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var isPaused = false

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't install global hooks while running under XCTest.
        guard !Self.isRunningTests else { return }

        setUpStatusItem()
        switcher.start()
        promptForAccessibilityIfNeeded()
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Zap")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Zap Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let pauseItem = NSMenuItem(title: "Pause Zap", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        pauseMenuItem = pauseItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Zap", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: Actions

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            switcher.pause()
        } else {
            switcher.resume()
        }
        pauseMenuItem?.title = isPaused ? "Resume Zap" : "Pause Zap"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    private func promptForAccessibilityIfNeeded() {
        if !switcher.isUsingEventTap {
            AccessibilityAuthorizer.prompt()
        }
    }

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
