import XCTest
@testable import Zap

/// The hidden-app snapshot carried on `AppInfo` for the overlay's badge.
final class AppInfoHiddenStateTests: XCTestCase {

    func testDefaultsToVisible() {
        let app = AppInfo(bundleIdentifier: "com.example.a", name: "A", processIdentifier: 1)
        XCTAssertFalse(app.isHidden)
    }

    func testHiddenStateIsCarried() {
        let app = AppInfo(bundleIdentifier: "com.example.a", name: "A",
                          processIdentifier: 1, icon: nil, isHidden: true)
        XCTAssertTrue(app.isHidden)
    }

    func testHiddenStateIsNotPartOfIdentity() {
        // Hiding an app must not make it a *different* app: equality drives
        // selection restoration when the list changes mid-session, and `id`
        // drives SwiftUI's ForEach diffing (which should update the row in
        // place, not replace it).
        let visible = AppInfo(bundleIdentifier: "com.example.a", name: "A",
                              processIdentifier: 1, icon: nil, isHidden: false)
        let hidden = AppInfo(bundleIdentifier: "com.example.a", name: "A",
                             processIdentifier: 1, icon: nil, isHidden: true)
        XCTAssertEqual(visible, hidden)
        XCTAssertEqual(visible.id, hidden.id)
    }
}
