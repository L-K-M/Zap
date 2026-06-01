import AppKit

/// Program entry point.
///
/// Zap is a menu-bar agent (`LSUIElement`), so it runs as an `.accessory` app
/// with no Dock icon and never appears in its own switcher. A plain
/// `NSApplication` lifecycle (rather than the SwiftUI `App` scene) keeps full
/// control over windowing on macOS 13+.
@main
enum ZapMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
