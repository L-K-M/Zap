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
    /// Called when the user cancels (Escape) while the overlay is visible.
    var onCancel: (() -> Void)?
    /// Called when the user presses ⌘Q on the selection (optional handler).
    var onQuitSelected: (() -> Void)?
    /// Called when the user presses ⌘W with a window focused in the window list.
    var onCloseWindow: (() -> Void)?
    /// Called when the user presses Down/Up to move through the window list.
    /// `down == true` moves toward the next window; `false` moves back up
    /// (eventually returning focus to the app row).
    var onNavigateWindows: ((_ down: Bool) -> Void)?
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

        let mask: CGEventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
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
            switch keyCode {
            case KeyCode.escape:
                onCancel?()
                return nil
            case KeyCode.q:
                // Quit the highlighted app (Command is still held here).
                onQuitSelected?()
                return nil
            case KeyCode.w:
                // Close the focused window in the window list (if any).
                onCloseWindow?()
                return nil
            case KeyCode.arrowDown:
                onNavigateWindows?(true)
                return nil
            case KeyCode.arrowUp:
                onNavigateWindows?(false)
                return nil
            default:
                // Swallow other keys so they don't leak to the front app mid-switch.
                return nil
            }

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
