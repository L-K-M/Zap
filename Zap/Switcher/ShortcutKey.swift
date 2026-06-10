/// An in-switcher action key — Q (quit), H (hide), or W (close window) — pressed
/// while ⌘ is still held. Each doubles as a plain letter for type-to-search, so
/// the event tap forwards both readings and the controller routes by context
/// (see `SwitcherController.shortcutRouting(for:windowFocused:)`).
enum ShortcutKey: Equatable {
    case quit, hide, closeWindow
}
