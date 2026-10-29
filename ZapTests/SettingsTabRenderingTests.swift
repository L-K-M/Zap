import AppKit
import PictKit
import SwiftUI
import XCTest
@testable import Zap

final class SettingsTabRenderingTests: XCTestCase {

    private enum Container {
        case swiftUIRoot
        case nativeTabs
    }

    @MainActor
    private func withSettings(_ container: Container, _ check: (NSViewController) throws -> Void) throws {
        let suite = "SettingsTabRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let preferences = Preferences(defaults: defaults)
        let icons = ZapIcons(preferences: preferences, store: IconStore(directory: directory))
        let checker = UpdateChecker(configuration: .init(owner: "example", repo: "Zap"), defaults: defaults)
        let controller: NSViewController
        switch container {
        case .swiftUIRoot:
            controller = NSHostingController(rootView: SettingsView(
                preferences: preferences, inputMode: InputModeReporter(),
                updateChecker: checker, icons: icons))
        case .nativeTabs:
            controller = SettingsTabViewController(
                preferences: preferences, inputMode: InputModeReporter(),
                updateChecker: checker, icons: icons, showsDisplays: false)
        }
        controller.view.frame = NSRect(x: 0, y: 0, width: 720, height: 480)
        controller.view.layoutSubtreeIfNeeded()
        try check(controller)
    }

    @MainActor
    private func tabView(in view: NSView) -> NSTabView? {
        if let tabView = view as? NSTabView { return tabView }
        return view.subviews.lazy.compactMap { self.tabView(in: $0) }.first
    }

    @MainActor
    private func tabBar(in view: NSView) -> SettingsTabBar? {
        if let control = view as? SettingsTabBar { return control }
        return view.subviews.lazy.compactMap { self.tabBar(in: $0) }.first
    }

    @MainActor
    private func nativeTabs(in controller: SettingsTabViewController) throws -> NSTabViewController {
        try XCTUnwrap(controller.children.compactMap { $0 as? NSTabViewController }.first)
    }

    @MainActor
    func testSettingsPaneDoesNotDrawATabBezel() throws {
        try withSettings(.swiftUIRoot) { controller in
            let tabs = try XCTUnwrap(tabView(in: controller.view))
            XCTAssertEqual(tabs.tabViewBorderType, .none,
                           "A native bezel draws the unwanted line beside the settings tabs")
        }
    }

    @MainActor
    func testChangingDisplayAvailabilityPreservesSelectionAndPaneControllers() throws {
        try withSettings(.nativeTabs) { root in
            let controller = try XCTUnwrap(root as? SettingsTabViewController)
            let tabs = try nativeTabs(in: controller)
            controller.setShowsDisplays(false)
            let icons = try XCTUnwrap(tabs.tabViewItems.first { $0.label == "Icons" })
            let iconsController = try XCTUnwrap(icons.viewController)
            tabs.selectedTabViewItemIndex = try XCTUnwrap(tabs.tabViewItems.firstIndex(of: icons))

            controller.setShowsDisplays(true)
            XCTAssertEqual(tabs.tabViewItems.map(\.label),
                           ["General", "Exclusions", "Displays", "Appearance", "Icons", "Permissions", "About"])
            XCTAssertTrue(tabs.tabView.selectedTabViewItem === icons)
            let displays = tabs.tabViewItems[2]

            controller.setShowsDisplays(false)
            XCTAssertTrue(tabs.tabView.selectedTabViewItem === icons)
            XCTAssertTrue(icons.viewController === iconsController)

            controller.setShowsDisplays(true)
            XCTAssertTrue(tabs.tabViewItems[2] === displays)
            XCTAssertTrue(tabs.tabView.selectedTabViewItem === icons)
        }
    }

    @MainActor
    func testRemovingSelectedDisplaysPaneSelectsAnExistingPane() throws {
        try withSettings(.nativeTabs) { root in
            let controller = try XCTUnwrap(root as? SettingsTabViewController)
            let tabs = try nativeTabs(in: controller)
            controller.setShowsDisplays(true)
            tabs.selectedTabViewItemIndex = 2
            controller.setShowsDisplays(false)

            let selected = try XCTUnwrap(tabs.tabView.selectedTabViewItem)
            XCTAssertNotEqual(selected.label, "Displays")
            XCTAssertTrue(tabs.tabViewItems.contains(selected))
        }
    }

    @MainActor
    func testInactiveSettingsPanesRemainLazy() throws {
        try withSettings(.nativeTabs) { root in
            let controller = try XCTUnwrap(root as? SettingsTabViewController)
            let tabs = try nativeTabs(in: controller)
            XCTAssertEqual(tabs.tabStyle, .unspecified)
            let icons = try XCTUnwrap(tabs.tabViewItems.first { $0.label == "Icons" })
            XCTAssertFalse(try XCTUnwrap(icons.viewController).isViewLoaded)
        }
    }

    @MainActor
    func testTabSelectorFitsTheMinimumSettingsWindow() throws {
        try withSettings(.swiftUIRoot) { root in
            let hosting = try XCTUnwrap(root as? NSHostingController<SettingsView>)
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            defer { window.close() }
            // setContentSize can force a window below its minimum; test the
            // minimum measured by the actual hosted settings content instead.
            window.setContentSize(hosting.sizeThatFits(in: .zero))
            hosting.view.layoutSubtreeIfNeeded()

            let selector = try XCTUnwrap(tabBar(in: hosting.view))
            let frame = selector.convert(selector.bounds, to: hosting.view)
            XCTAssertGreaterThanOrEqual(frame.minX, hosting.view.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, hosting.view.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.width, selector.intrinsicContentSize.width - 1)
            XCTAssertGreaterThanOrEqual(hosting.sizeThatFits(in: .zero).width,
                                        selector.intrinsicContentSize.width - 1)

            window.setContentSize(NSSize(width: 960, height: 700))
            hosting.view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(hosting.view.bounds.width, 960)
            XCTAssertGreaterThanOrEqual(hosting.view.bounds.height, 700)
        }
    }

    @MainActor
    func testCustomTabsHaveSpaceBelowTheWindowHeader() throws {
        try withSettings(.nativeTabs) { root in
            let bar = try XCTUnwrap(tabBar(in: root.view))
            let frame = bar.convert(bar.bounds, to: root.view)
            XCTAssertGreaterThanOrEqual(root.view.bounds.maxY - frame.maxY, 16)
        }
    }

    @MainActor
    func testCustomTabsTrackNativeSelectionAndExposeSelectedTab() throws {
        try withSettings(.nativeTabs) { root in
            let controller = try XCTUnwrap(root as? SettingsTabViewController)
            let tabs = try nativeTabs(in: controller)
            let bar = try XCTUnwrap(tabBar(in: root.view))
            tabs.selectedTabViewItemIndex = 3

            XCTAssertEqual(bar.selectedIndex, 3)
            let buttons = bar.arrangedSubviews.compactMap { $0 as? SettingsTabButton }
            XCTAssertEqual(buttons.filter { $0.state == .on }.map(\.title), [tabs.tabViewItems[3].label])
            XCTAssertEqual(bar.accessibilityRole(), .tabGroup)
            XCTAssertTrue(bar.isAccessibilityElement())
            XCTAssertTrue(buttons[3].isAccessibilityElement())
            XCTAssertEqual(buttons[3].accessibilityRole(), .radioButton)
            XCTAssertEqual(buttons[3].accessibilitySubrole(), .tabButtonSubrole)
            XCTAssertEqual((buttons[3].accessibilityValue() as? NSNumber)?.boolValue, true)
            XCTAssertEqual((buttons[0].accessibilityValue() as? NSNumber)?.boolValue, false)
        }
    }

    @MainActor
    func testClickAndArrowKeysSelectTheMatchingPane() throws {
        try withSettings(.nativeTabs) { root in
            let controller = try XCTUnwrap(root as? SettingsTabViewController)
            let tabs = try nativeTabs(in: controller)
            let bar = try XCTUnwrap(tabBar(in: root.view))
            let buttons = bar.arrangedSubviews.compactMap { $0 as? SettingsTabButton }
            buttons[1].performClick(nil)
            XCTAssertEqual(tabs.selectedTabViewItemIndex, 1)

            let right = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{F703}",
                charactersIgnoringModifiers: "\u{F703}", isARepeat: false,
                keyCode: UInt16(KeyCode.arrowRight)))
            buttons[1].keyDown(with: right)
            XCTAssertEqual(tabs.selectedTabViewItemIndex, 2)
            XCTAssertEqual(bar.selectedIndex, 2)
        }
    }

    @MainActor
    func testDisplayChangesPreserveKeyboardFocusInTheTabRow() throws {
        try withSettings(.nativeTabs) { root in
            let controller = try XCTUnwrap(root as? SettingsTabViewController)
            let window = NSWindow(contentViewController: root)
            defer { window.close() }
            let bar = try XCTUnwrap(tabBar(in: root.view))
            let icons = try XCTUnwrap(bar.arrangedSubviews.first { ($0 as? NSButton)?.title == "Icons" })
            XCTAssertTrue(window.makeFirstResponder(icons))

            controller.setShowsDisplays(true)
            XCTAssertTrue(window.firstResponder === icons)
            controller.setShowsDisplays(false)
            XCTAssertTrue(window.firstResponder === icons)
        }
    }
}
