import AppKit

/// Sets up the status-bar item, the switcher, and the settings window.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let preferences = Preferences.shared
    private lazy var switcher = SwitcherController(preferences: preferences)
    private lazy var settingsWindow = SettingsWindowController(preferences: preferences, inputMode: switcher.inputMode)

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
        item.button?.image = Self.statusBarImage()
        item.menu = buildMenu()
        statusItem = item
    }

    /// Builds the menu-bar icon: the `command` glyph with the app's "flash" bolt
    /// added as a badge in the lower-trailing corner. Rendered as a template image
    /// so the system tints it for light/dark menu bars automatically.
    static func statusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)

        let command = NSImage(systemSymbolName: "command", accessibilityDescription: "Zap")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))

        let image = NSImage(size: size, flipped: false) { _ in
            // Command glyph, nudged toward the top-leading corner to leave room
            // for the bolt badge.
            if let command {
                let s = command.size
                command.draw(in: NSRect(x: 0, y: 18 - s.height, width: s.width, height: s.height))
            }
            // Bolt badge in the lower-trailing corner. A slightly larger bolt is
            // knocked out of the command first, so the badge keeps a transparent
            // border that follows the bolt's own shape (not a boxy halo).
            if let bolt {
                let s = bolt.size
                let frame = NSRect(origin: NSPoint(x: 18 - s.width, y: 0), size: s)
                bolt.draw(in: frame.insetBy(dx: -2.5, dy: -2.5),
                          from: .zero, operation: .destinationOut, fraction: 1)
                bolt.draw(in: frame)
            }
            return true
        }
        image.isTemplate = true
        return image
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
