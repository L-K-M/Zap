import ServiceManagement
import XCTest
@testable import Zap

/// Tests launch-at-login handling when `SMAppService` reports
/// `.requiresApproval` — a registered-but-pending item must read as on, must be
/// cancellable, and must not be registered or unregistered redundantly. A
/// stateful fake stands in for the real service; no actual login item is touched.
final class LoginItemApprovalTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ch.lkmc.Zap.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private struct FakeError: Error {}

    /// Stateful fake standing in for `SMAppService.mainApp`: a successful
    /// register lands the item in `statusAfterRegister` (a fresh registration
    /// awaits approval until the user allows it in System Settings) and a
    /// successful unregister lands it in `.notRegistered`.
    private final class FakeService {
        var status: SMAppService.Status
        var statusAfterRegister: SMAppService.Status = .requiresApproval
        var registerCalls = 0
        var unregisterCalls = 0
        var registerError: Error?
        var unregisterError: Error?
        var openSettingsCalls = 0

        init(status: SMAppService.Status) {
            self.status = status
        }

        lazy var service = LoginItemService(
            status: { self.status },
            register: {
                self.registerCalls += 1
                if let error = self.registerError { throw error }
                self.status = self.statusAfterRegister
            },
            unregister: {
                self.unregisterCalls += 1
                if let error = self.unregisterError { throw error }
                self.status = .notRegistered
            },
            openSettings: { self.openSettingsCalls += 1 }
        )
    }

    private func makePreferences(status: SMAppService.Status) -> (Preferences, FakeService) {
        let fake = FakeService(status: status)
        return (Preferences(defaults: defaults, loginItemService: fake.service), fake)
    }

    func testInitialRequiresApprovalShowsOnAndPending() {
        let (preferences, _) = makePreferences(status: .requiresApproval)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertTrue(preferences.launchAtLoginRequiresApproval)
    }

    func testTurningPendingApprovalOffUnregisters() {
        let (preferences, fake) = makePreferences(status: .requiresApproval)
        preferences.launchAtLogin = false
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertFalse(preferences.launchAtLoginRequiresApproval)
        XCTAssertEqual(defaults.object(forKey: "launchAtLogin") as? Bool, false)
    }

    func testTurningEnabledOffUnregisters() {
        let (preferences, fake) = makePreferences(status: .enabled)
        preferences.launchAtLogin = false
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertEqual(defaults.object(forKey: "launchAtLogin") as? Bool, false)
    }

    func testTurningOffWhenNotRegisteredDoesNotUnregister() {
        let (preferences, fake) = makePreferences(status: .notRegistered)
        preferences.launchAtLogin = false
        XCTAssertEqual(fake.registerCalls, 0)
        XCTAssertEqual(fake.unregisterCalls, 0)
    }

    func testTurningOnWhilePendingDoesNotRegisterAgain() {
        let (preferences, fake) = makePreferences(status: .requiresApproval)
        preferences.launchAtLogin = true
        XCTAssertEqual(fake.registerCalls, 0)
        XCTAssertTrue(preferences.launchAtLoginRequiresApproval)
    }

    func testSuccessfulRegisterIntoPendingApprovalLeavesOnAndPending() {
        let (preferences, fake) = makePreferences(status: .notRegistered)
        preferences.launchAtLogin = true
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertTrue(preferences.launchAtLoginRequiresApproval)
        XCTAssertNil(preferences.launchAtLoginError)
    }

    func testFailedUnregisterRollsBackOnAndPending() {
        let (preferences, fake) = makePreferences(status: .requiresApproval)
        fake.unregisterError = FakeError()
        preferences.launchAtLogin = false
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertTrue(preferences.launchAtLoginRequiresApproval)
        XCTAssertNotNil(preferences.launchAtLoginError)
    }

    func testFailedRegisterRollsBackToOff() {
        let (preferences, fake) = makePreferences(status: .notRegistered)
        fake.registerError = FakeError()
        preferences.launchAtLogin = true
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertFalse(preferences.launchAtLoginRequiresApproval)
        XCTAssertNotNil(preferences.launchAtLoginError)
    }

    func testRefreshAfterApprovalClearsFlagWithoutWrites() {
        let (preferences, fake) = makePreferences(status: .requiresApproval)
        fake.status = .enabled // the user approved in System Settings meanwhile
        preferences.refreshLaunchAtLoginStatus()
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertFalse(preferences.launchAtLoginRequiresApproval)
        XCTAssertEqual(fake.registerCalls, 0)
        XCTAssertEqual(fake.unregisterCalls, 0)
    }

    func testOpenSettingsReachesTheService() {
        // The pending-approval hint deep-links to System Settings via the
        // service boundary, not by reaching for SMAppService in the UI.
        let (preferences, fake) = makePreferences(status: .requiresApproval)
        preferences.openLoginItemSettings()
        XCTAssertEqual(fake.openSettingsCalls, 1)
    }
}
