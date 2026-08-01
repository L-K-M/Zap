import AppKit

/// Zap's main menu, which exists almost entirely so text fields work.
///
/// On macOS the standard editing shortcuts — ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z — are not built
/// into `NSTextField`. They are **key equivalents on the main menu**, dispatched
/// down the responder chain to whatever is focused. A menu-bar agent that never
/// sets `NSApp.mainMenu` therefore has text fields that silently ignore all of
/// them, which is what Settings and the icon-search sheet were doing: typing
/// worked, selecting all did not.
///
/// Every item targets `nil`, so AppKit routes it to the first responder that can
/// handle it. Nothing here needs a target of its own.
///
/// The menu bar is only *drawn* while Zap is `.regular` — that is, while the
/// Settings window is open (`SettingsWindowController`). The rest of the time it
/// is installed and invisible, which is exactly what an agent app wants.
enum MainMenu {

    /// Builds and installs the menu. Call once, at launch.
    static func install(into application: NSApplication) {
        let menu = NSMenu()
        menu.addItem(appMenuItem(named: application.appName))
        menu.addItem(editMenuItem())
        menu.addItem(windowMenuItem())
        application.mainMenu = menu
        // `windowsMenu` is deliberately left unset. Handing AppKit the Window menu
        // makes it list every window Zap owns, and most of Zap's windows are not
        // the kind anyone should be offered: the switcher panel and the offscreen
        // host `SVGRasterizer` renders in. The three items below reach the focused
        // window through the responder chain without any of that.
    }

    // MARK: Menus

    /// The first menu is always the application menu, whatever it is called — so
    /// there has to be one even though Edit is the point of the exercise.
    private static func appMenuItem(named appName: String) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)

        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings),
                     keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)),
                     keyEquivalent: "h")

        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)

        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    /// The reason this file exists.
    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)),
                     keyEquivalent: "a")

        item.submenu = menu
        return item
    }

    /// ⌘W to close Settings, and ⌘M to minimise it — the other keyboard commands
    /// a window is expected to answer.
    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")

        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        item.submenu = menu
        return item
    }
}

private extension NSApplication {
    /// The name to put in the application menu, from the bundle rather than hard-coded.
    var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Zap"
    }
}
