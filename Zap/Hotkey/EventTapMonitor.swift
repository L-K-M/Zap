import AppKit
import CoreGraphics

/// Intercepts ⌘+Tab using a `CGEventTap` and drives the custom switcher.
///
/// The tap is attached to the **main** run loop, so all callbacks run on the main
/// thread and may touch UI directly. Requires Accessibility permission.
final class EventTapMonitor {

    // MARK: Callbacks (set by the controller)

    /// Called when the user cycles. `forward == false` means reverse (Shift held).
    var onCycle: ((_ forward: Bool) -> Void)?
    /// Called when the Command key is released while the overlay is visible.
    var onCommit: (() -> Void)?
    /// Called when the user presses Escape while the overlay is visible. The
    /// controller decides whether that clears the search query or cancels.
    var onEscape: (() -> Void)?
    /// Called when one of the dual-purpose action keys (Q/H/W) goes down
    /// mid-session. `character` is the layout-aware letter the key would type
    /// (for type-to-search; `nil` if it types nothing) and `isRepeat` marks the
    /// auto-repeat events of a held key. The controller decides by context
    /// whether the key acts (quit/hide/close) or types.
    var onShortcutKey: ((_ key: ShortcutKey, _ character: Character?, _ isRepeat: Bool) -> Void)?
    /// Called when a dual-purpose action key is released, resolving a potential
    /// tap-vs-hold in favor of the tap.
    var onShortcutKeyUp: ((_ key: ShortcutKey) -> Void)?
    /// Called when the user presses an arrow key. Down enters/advances the window
    /// list/grid; Up steps back (eventually returning focus to the app row);
    /// Left/Right move within a preview-grid row — or, while the app row is
    /// focused, move the app selection itself.
    var onNavigateWindows: ((_ direction: WindowNavDirection) -> Void)?
    /// Called when the user types a printable character mid-session (no ⌘-combo
    /// of our own). The controller uses it for type-to-search and number-key jumps.
    /// The character is layout-aware (see `typedCharacter(for:)`).
    var onType: ((_ character: Character) -> Void)?
    /// Called when the user presses Delete/Backspace mid-session, to edit the
    /// type-to-search query.
    var onDeleteBackward: (() -> Void)?
    /// Whether a switch session is currently active (overlay shown or pending).
    /// Drives commit/cancel behavior.
    var isSwitching: () -> Bool = { false }

    // MARK: State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { eventTap != nil }

    // MARK: Lifecycle

    /// Installs the tap. Returns `false` if it could not be created (usually means
    /// Accessibility permission is missing).
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        // Key-ups are tapped only to resolve the tap-vs-hold of the dual-purpose
        // action keys (Q/H/W); all others pass straight through.
        let mask: CGEventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<EventTapMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func setEnabled(_ enabled: Bool) {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: enabled)
    }

    // MARK: Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if the system disabled our tap (e.g. slow callback / user input).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let commandDown = flags.contains(.maskCommand)
        let shiftDown = flags.contains(.maskShift)
        // Only Command and (optionally) Shift may be held for our trigger. Any of
        // Control / Option / Function present means this is some other shortcut
        // (e.g. ⌃⌘Tab, ⌥⌘Tab) that we must not consume.
        let foreignModifiers = flags.contains(.maskControl)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskSecondaryFn)
        let cleanCommand = commandDown && !foreignModifiers

        switch type {
        case .flagsChanged:
            // Commit the selection when Command is released while visible.
            if isSwitching() && !commandDown {
                onCommit?()
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // ⌘+Tab (forward) / ⌘+Shift+Tab (reverse): consume and drive switcher.
            // Require exactly Command with optional Shift — reject Control/Option/Fn
            // so we don't steal other system shortcuts that include Tab.
            if cleanCommand && keyCode == KeyCode.tab {
                onCycle?(!shiftDown)
                return nil
            }

            // ⌘+` reverse-cycles, but ONLY while a switch session is already
            // active. Outside a session ⌘+` is the native "cycle windows of the
            // front app" shortcut and must be left alone.
            if cleanCommand && keyCode == KeyCode.grave && isSwitching() {
                onCycle?(false)
                return nil
            }

            guard isSwitching() else {
                return Unmanaged.passUnretained(event)
            }

            // Keys handled only while the overlay is up.
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            switch keyCode {
            case KeyCode.escape:
                onEscape?()
                return nil
            case KeyCode.q:
                // Q/H/W double as shortcuts (quit/hide/close window) and search
                // letters; forward both readings for the controller to route.
                onShortcutKey?(.quit, typedCharacter(for: event), isRepeat)
                return nil
            case KeyCode.h:
                onShortcutKey?(.hide, typedCharacter(for: event), isRepeat)
                return nil
            case KeyCode.w:
                onShortcutKey?(.closeWindow, typedCharacter(for: event), isRepeat)
                return nil
            case KeyCode.arrowDown:
                onNavigateWindows?(.down)
                return nil
            case KeyCode.arrowUp:
                onNavigateWindows?(.up)
                return nil
            case KeyCode.arrowLeft:
                onNavigateWindows?(.left)
                return nil
            case KeyCode.arrowRight:
                onNavigateWindows?(.right)
                return nil
            case KeyCode.delete:
                // Backspace edits the type-to-search query.
                onDeleteBackward?()
                return nil
            default:
                // Forward a printable character for type-to-search / number-key
                // jumps; otherwise swallow the key so it doesn't leak to the front
                // app mid-switch.
                if let character = typedCharacter(for: event) {
                    onType?(character)
                }
                return nil
            }

        case .keyUp:
            guard isSwitching() else {
                return Unmanaged.passUnretained(event)
            }
            // Releasing a dual-purpose key resolves its tap-vs-hold; consume the
            // key-up for symmetry with its consumed key-down.
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case KeyCode.q:
                onShortcutKeyUp?(.quit)
                return nil
            case KeyCode.h:
                onShortcutKeyUp?(.hide)
                return nil
            case KeyCode.w:
                onShortcutKeyUp?(.closeWindow)
                return nil
            default:
                return Unmanaged.passUnretained(event)
            }

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// The character a key event would type with its modifiers cleared, so it's the
    /// plain (lowercased, unshifted) letter/digit. Reading it from the event makes
    /// this layout-aware — an AZERTY `A` is reported as `a`, not the US `q` at that
    /// position — unlike the position-based `KeyCode` constants. Clearing the flags
    /// first also avoids Command suppressing text generation. Returns `nil` for keys
    /// that produce no text (function keys, etc.).
    private func typedCharacter(for event: CGEvent) -> Character? {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let savedFlags = event.flags
        event.flags = []
        event.keyboardGetUnicodeString(maxStringLength: characters.count,
                                       actualStringLength: &length,
                                       unicodeString: &characters)
        event.flags = savedFlags
        guard length > 0 else { return nil }
        return String(decoding: characters.prefix(length), as: UTF16.self).first
    }
}
