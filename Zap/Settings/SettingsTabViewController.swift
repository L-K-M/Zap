import AppKit
import SwiftUI

/// Keeps the native segmented selector separate from its borderless content.
/// SwiftUI's macOS TabView uses a bezel that draws a line beside the tab labels;
/// changing that view's border alone has no effect while its own tabs are shown.
final class SettingsTabViewController: NSTabViewController {

    private let displaysItem: NSTabViewItem

    init(preferences: Preferences, inputMode: InputModeReporter,
         updateChecker: UpdateChecker, icons: ZapIcons, showsDisplays: Bool) {
        displaysItem = Self.item("Displays", content: DisplaysView(preferences: preferences))
        super.init(nibName: nil, bundle: nil)

        tabStyle = .segmentedControlOnTop
        tabView.tabViewType = .noTabsNoBorder
        canPropagateSelectedChildViewControllerTitle = false
        transitionOptions = []

        addTabViewItem(Self.item("General", content: GeneralView(
            preferences: preferences, updateChecker: updateChecker)))
        addTabViewItem(Self.item("Exclusions", content: ExclusionsView(preferences: preferences)))
        addTabViewItem(Self.item("Appearance", content: AppearanceView(preferences: preferences)))
        addTabViewItem(Self.item("Icons", content: IconsView(preferences: preferences, icons: icons)))
        addTabViewItem(Self.item("Permissions", content: PermissionsView(inputMode: inputMode)))
        addTabViewItem(Self.item("About", content: AboutView(preferences: preferences)))
        setShowsDisplays(showsDisplays)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    /// Insert/remove only the conditional pane. AppKit adjusts the selected index
    /// around it and keeps the other hosting controllers, including SwiftUI state.
    func setShowsDisplays(_ showsDisplays: Bool) {
        let isShown = tabViewItems.contains { $0 === displaysItem }
        guard showsDisplays != isShown else { return }

        if showsDisplays {
            insertTabViewItem(displaysItem, at: 2)
        } else {
            removeTabViewItem(displaysItem)
        }
    }

    private static func item<Content: View>(_ title: String, content: Content) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: PaneController(content: content))
        item.label = title
        return item
    }

    /// NSHostingController initializes its view eagerly. Delay creating it until
    /// AppKit selects the pane, so inactive tabs do not mount their SwiftUI trees.
    private final class PaneController<Content: View>: NSViewController {
        private let content: Content

        init(content: Content) {
            self.content = content
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }

        override func loadView() {
            let hosting = NSHostingController(rootView: content)
            addChild(hosting)
            view = NSView()
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hosting.view)
            NSLayoutConstraint.activate([
                hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
}
