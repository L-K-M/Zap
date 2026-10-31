import CoreGraphics
import Foundation

/// CoreGraphics can return a valid tap after silently removing keyboard events.
/// Verify its individual server registration rather than trusting its port alone.
final class SystemEventTapConnection: EventTapConnection {
    private let tap: CFMachPort
    private let source: CFRunLoopSource
    private let registrationID: UInt32

    var isValid: Bool { CFMachPortIsValid(tap) && CFRunLoopSourceIsValid(source) }
    var isEnabled: Bool { isValid && CGEvent.tapIsEnabled(tap: tap) }
    var registeredEvents: CGEventMask? {
        Self.registrations()?.first { $0.eventTapID == registrationID }?.eventsOfInterest
    }

    private init(tap: CFMachPort, source: CFRunLoopSource, registrationID: UInt32) {
        self.tap = tap
        self.source = source
        self.registrationID = registrationID
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    deinit { invalidate() }

    static func create(events: CGEventMask, callback: CGEventTapCallBack,
                       userInfo: UnsafeMutableRawPointer) -> SystemEventTapConnection? {
        guard let before = registrations() else { return nil }
        let previousIDs = Set(before.map(\.eventTapID))
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                         place: .headInsertEventTap,
                                         options: .defaultTap,
                                         eventsOfInterest: events,
                                         callback: callback, userInfo: userInfo)
        else { return nil }

        // The server ID is not the CFMachPort's local Mach port name. Identify
        // the newly-created registration, even if another framework owns a tap.
        let created = registrations()?.filter {
            $0.tappingProcess == getpid() && !previousIDs.contains($0.eventTapID)
                && $0.tapPoint == .cgSessionEventTap
        }
        guard let created, created.count == 1, let registration = created.first,
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else {
            CFMachPortInvalidate(tap)
            return nil
        }
        return SystemEventTapConnection(tap: tap, source: source,
                                        registrationID: registration.eventTapID)
    }

    func setEnabled(_ enabled: Bool) {
        guard isValid else { return }
        CGEvent.tapEnable(tap: tap, enable: enabled)
    }

    func invalidate() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        CFMachPortInvalidate(tap)
    }

    private static func registrations() -> [CGEventTapInformation]? {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success else { return nil }
        // Allow room for taps installed between the count and list calls.
        var taps = [CGEventTapInformation](repeating: .init(), count: Int(count) + 16)
        guard CGGetEventTapList(UInt32(taps.count), &taps, &count) == .success,
              count <= taps.count else { return nil }
        return Array(taps.prefix(Int(count)))
    }
}
