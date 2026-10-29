import AppKit
import SwiftUI

/// Custom tabs above a native borderless controller that retains lazy panes.
final class SettingsTabViewController: NSViewController {

    private static let topInset: CGFloat = 16
    private static let horizontalInset: CGFloat = 20
    private let contentController = ContentController()
    private let tabBar = SettingsTabBar()
    private let displaysItem: NSTabViewItem

    var minimumContentSize: NSSize {
        NSSize(width: max(520, tabBar.intrinsicContentSize.width + 2 * Self.horizontalInset),
               height: max(460, tabBar.intrinsicContentSize.height + Self.topInset))
    }

    init(preferences: Preferences, inputMode: InputModeReporter,
         updateChecker: UpdateChecker, icons: ZapIcons, showsDisplays: Bool) {
        displaysItem = Self.item("Displays", content: DisplaysView(preferences: preferences))
        super.init(nibName: nil, bundle: nil)

        contentController.tabStyle = .unspecified
        contentController.tabView.tabViewType = .noTabsNoBorder
        contentController.canPropagateSelectedChildViewControllerTitle = false
        contentController.transitionOptions = []

        contentController.addTabViewItem(Self.item("General", content: GeneralView(
            preferences: preferences, updateChecker: updateChecker)))
        contentController.addTabViewItem(Self.item("Exclusions", content: ExclusionsView(preferences: preferences)))
        contentController.addTabViewItem(Self.item("Appearance", content: AppearanceView(preferences: preferences)))
        contentController.addTabViewItem(Self.item("Icons", content: IconsView(preferences: preferences, icons: icons)))
        contentController.addTabViewItem(Self.item("Permissions", content: PermissionsView(inputMode: inputMode)))
        contentController.addTabViewItem(Self.item("About", content: AboutView(preferences: preferences)))
        setShowsDisplays(showsDisplays)

        contentController.onSelectionChanged = { [weak self] in self?.synchronizeTabBar() }
        tabBar.onSelect = { [weak self] index in
            self?.contentController.selectedTabViewItemIndex = index
        }
        synchronizeTabBar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override func loadView() {
        view = NSView()
        addChild(contentController)
        let content = contentController.view
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        view.addSubview(content)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.topInset),
            tabBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tabBar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Self.horizontalInset),
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Self.horizontalInset),
            tabBar.heightAnchor.constraint(equalToConstant: tabBar.intrinsicContentSize.height),
            content.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Insert/remove only the conditional pane. AppKit adjusts the selected index
    /// around it and keeps the other hosting controllers, including SwiftUI state.
    func setShowsDisplays(_ showsDisplays: Bool) {
        let isShown = contentController.tabViewItems.contains { $0 === displaysItem }
        guard showsDisplays != isShown else { return }

        if showsDisplays {
            contentController.insertTabViewItem(displaysItem, at: 2)
        } else {
            contentController.removeTabViewItem(displaysItem)
        }
        synchronizeTabBar()
    }

    private func synchronizeTabBar() {
        tabBar.setTabs(contentController.tabViewItems.map(\.label),
                       selectedIndex: contentController.selectedTabViewItemIndex)
    }

    private static func item<Content: View>(_ title: String, content: Content) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: PaneController(content: content))
        item.label = title
        return item
    }

    private final class ContentController: NSTabViewController {
        var onSelectionChanged: (() -> Void)?

        override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
            super.tabView(tabView, didSelect: tabViewItem)
            onSelectionChanged?()
        }
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
            let hosting = NSHostingController(rootView: content.scrollContentBackground(.hidden))
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
