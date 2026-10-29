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
    private func segmentedControl(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl { return control }
        return view.subviews.lazy.compactMap { self.segmentedControl(in: $0) }.first
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
            controller.setShowsDisplays(false)
            let icons = try XCTUnwrap(controller.tabViewItems.first { $0.label == "Icons" })
            let iconsController = try XCTUnwrap(icons.viewController)
            controller.selectedTabViewItemIndex = try XCTUnwrap(controller.tabViewItems.firstIndex(of: icons))

            controller.setShowsDisplays(true)
            XCTAssertEqual(controller.tabViewItems.map(\.label),
                           ["General", "Exclusions", "Displays", "Appearance", "Icons", "Permissions", "About"])
            XCTAssertTrue(controller.tabView.selectedTabViewItem === icons)
            let displays = controller.tabViewItems[2]

            controller.setShowsDisplays(false)
            XCTAssertTrue(controller.tabView.selectedTabViewItem === icons)
            XCTAssertTrue(icons.viewController === iconsController)

            controller.setShowsDisplays(true)
            XCTAssertTrue(controller.tabViewItems[2] === displays)
            XCTAssertTrue(controller.tabView.selectedTabViewItem === icons)
        }
    }

    @MainActor
    func testRemovingSelectedDisplaysPaneSelectsAnExistingPane() throws {
        try withSettings(.nativeTabs) { root in
            let controller = try XCTUnwrap(root as? SettingsTabViewController)
            controller.setShowsDisplays(true)
            controller.selectedTabViewItemIndex = 2
            controller.setShowsDisplays(false)

            let selected = try XCTUnwrap(controller.tabView.selectedTabViewItem)
            XCTAssertNotEqual(selected.label, "Displays")
            XCTAssertTrue(controller.tabViewItems.contains(selected))
        }
    }

    @MainActor
    func testInactiveSettingsPanesRemainLazy() throws {
        try withSettings(.nativeTabs) { root in
            let controller = try XCTUnwrap(root as? SettingsTabViewController)
            XCTAssertEqual(controller.tabStyle, .segmentedControlOnTop)
            let icons = try XCTUnwrap(controller.tabViewItems.first { $0.label == "Icons" })
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

            let selector = try XCTUnwrap(segmentedControl(in: hosting.view))
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
}
