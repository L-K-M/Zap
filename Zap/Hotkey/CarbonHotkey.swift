import AppKit
import Carbon.HIToolbox

/// A global hotkey registered via Carbon's `RegisterEventHotKey`.
///
/// Used as the fallback trigger when Accessibility permission is unavailable
/// (Carbon hotkeys need no special permission, but cannot observe modifier
/// release — so the switcher uses an auto-commit timer in that mode).
final class CarbonHotkey {

    /// Invoked on the main thread when the hotkey fires.
    var onPressed: (() -> Void)?

    private let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Four-char signature `'ZAPH'`.
    private static let signature: OSType = 0x5A41_5048

    init(identifier: UInt32) {
        self.identifier = identifier
    }

    deinit { unregister() }

    /// Handles a `kEventHotKeyPressed` event delivered to the installed handler.
    ///
    /// Several handlers can share `GetApplicationEventTarget()`, so this must not
    /// consume foreign events: a nil event, a missing or malformed
    /// `kEventParamDirectObject` hotkey ID, or a signature/ID that is not this
    /// hotkey's returns `eventNotHandledErr` so the event can reach its owner.
    /// Only a matching `'ZAPH'` event schedules `onPressed` on the main queue
    /// and returns `noErr`.
    func handleHotkeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var pressedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedID
        )
        guard status == noErr else { return OSStatus(eventNotHandledErr) }

        guard pressedID.signature == Self.signature && pressedID.id == identifier else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [self] in onPressed?() }
        return noErr
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerCallback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
            return me.handleHotkeyEvent(event)
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            // Roll back the installed handler so a failed registration doesn't
            // leave a dangling event handler behind.
            unregister()
            NSLog("Zap: failed to register Carbon hotkey \(identifier): status \(registerStatus)")
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
