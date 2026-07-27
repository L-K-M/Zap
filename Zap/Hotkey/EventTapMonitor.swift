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
    /// Called when the user presses "?" mid-session, to show or hide the key
    /// hints. Reported separately from `onType` because recognising it needs the
    /// event's Shift state (see `togglesHelp(shiftedCharacter:)`).
    var onToggleHelp: (() -> Void)?
    /// Whether a switch session is currently active (overlay shown or pending).
    /// Drives commit/cancel behavior.
    var isSwitching: () -> Bool = { false }
    /// Called right after the system disabled the tap and we re-enabled it. Every
    /// event delivered while it was off is lost — including the `flagsChanged`
    /// that reports ⌘ going up, which is what commits a session — so the
    /// controller must reconcile its state against reality rather than keep
    /// waiting for an event that will never arrive.
    ///
    /// Invoked **synchronously from the tap callback**, which is exactly the
    /// context that just ran long enough to get the tap disabled: this handler
    /// must not block. Do the real work on a later run-loop turn.
    var onTapReEnabled: (() -> Void)?

    // MARK: State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Action keys currently held down, keyed by the *key code* that produced them.
    ///
    /// The key-down is matched by the character it types (so the action lands on
    /// the user's real Q/H/W wherever their layout puts them), but the matching
    /// key-up must be recognised even if the event carries no text — otherwise a
    /// quick tap would never resolve and its armed hold would fire, quitting an
    /// app the user only meant to type a letter for. The key code is the one thing
    /// guaranteed to match across the pair.
    private var heldShortcutKeyCodes: [Int64: ShortcutKey] = [:]

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
            // Logged after re-enabling, so getting events flowing again is never
            // behind a (synchronous) log write.
            NSLog("Zap: event tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input"); re-enabled")
            // Anything sent while the tap was off never reached us; let the
            // controller re-sync a session that may have lost its ⌘ key-up.
            onTapReEnabled?()
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
                // "?" toggles the key hints. Checked before type-to-search because
                // it needs the *shifted* reading of the key, which the plain
                // character (modifiers cleared) can't provide.
                if Self.togglesHelp(shiftedCharacter: typedCharacter(for: event, keepingShift: true)) {
                    onToggleHelp?()
                    return nil
                }
                let character = typedCharacter(for: event)
                // Q/H/W double as shortcuts (quit/hide/close window) and search
                // letters; forward both readings for the controller to route. They
                // are matched on the character the key *types*, not its position,
                // so ⌘Q quits on AZERTY/Dvorak/QWERTZ too — matching how macOS
                // itself resolves menu shortcuts.
                if let key = Self.shortcutKey(for: character) {
                    heldShortcutKeyCodes[keyCode] = key
                    onShortcutKey?(key, character, isRepeat)
                    return nil
                }
                // Forward a printable character for type-to-search / number-key
                // jumps; otherwise swallow the key so it doesn't leak to the front
                // app mid-switch.
                if let character {
                    onType?(character)
                }
                return nil
            }

        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // Releasing a dual-purpose key resolves its tap-vs-hold; consume the
            // key-up for symmetry with its consumed key-down. Always clear the
            // held-key bookkeeping, even when the session ended under the finger.
            guard let key = heldShortcutKeyCodes.removeValue(forKey: keyCode), isSwitching() else {
                return Unmanaged.passUnretained(event)
            }
            onShortcutKeyUp?(key)
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// The in-switcher action key a typed character stands for, or `nil` for an
    /// ordinary letter.
    ///
    /// Matched on the character rather than the key's physical position: the
    /// position of `q` on a US keyboard types `a` on AZERTY, so a position-based
    /// match had a French user's ⌘A quitting the highlighted app while ⌘Q did
    /// nothing. macOS resolves its own ⌘Q/⌘W/⌘H the same character-based way.
    /// Pure, so the mapping is unit-testable.
    static func shortcutKey(for character: Character?) -> ShortcutKey? {
        guard let character, let lowered = character.lowercased().first else { return nil }
        switch lowered {
        case "q": return .quit
        case "h": return .hide
        case "w": return .closeWindow
        default: return nil
        }
    }

    /// The character a key event would type with its modifiers cleared, so it's the
    /// plain (lowercased, unshifted) letter/digit. Reading it from the event makes
    /// this layout-aware — an AZERTY `A` is reported as `a`, not the US `q` at that
    /// position — unlike the position-based `KeyCode` constants. Clearing the flags
    /// first also avoids Command suppressing text generation. Returns `nil` for keys
    /// that produce no text (function keys, etc.).
    private func typedCharacter(for event: CGEvent, keepingShift: Bool = false) -> Character? {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let savedFlags = event.flags
        event.flags = keepingShift ? savedFlags.intersection(.maskShift) : []
        event.keyboardGetUnicodeString(maxStringLength: characters.count,
                                       actualStringLength: &length,
                                       unicodeString: &characters)
        event.flags = savedFlags
        guard length > 0 else { return nil }
        return String(decoding: characters.prefix(length), as: UTF16.self).first
    }

    /// Whether a key press means "toggle the key hints".
    ///
    /// Matched on the character the key types **with Shift honoured**, because
    /// "?" is a shifted key almost everywhere and its unshifted twin is a
    /// different character on every layout — "/" on US, "ß" on QWERTZ, "," on
    /// AZERTY. Asking what the key would type with Shift is the only reading that
    /// means the same thing everywhere. Pure, so the rule is unit-testable.
    static func togglesHelp(shiftedCharacter: Character?) -> Bool {
        shiftedCharacter == "?"
    }
}
