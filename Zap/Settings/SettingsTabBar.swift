import AppKit

/// A row of native, keyboard-accessible buttons with custom tab drawing.
final class SettingsTabBar: NSStackView {

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = -1
    private var buttons: [SettingsTabButton] = []
    private var cachedButtons: [String: SettingsTabButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .bottom
        distribution = .fill
        spacing = 4
        setHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Settings sections")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: NSSize {
        let width = buttons.reduce(CGFloat.zero) { $0 + $1.intrinsicContentSize.width }
            + spacing * CGFloat(max(0, buttons.count - 1))
        return NSSize(width: width, height: buttons.map { $0.intrinsicContentSize.height }.max() ?? 0)
    }

    func setTabs(_ titles: [String], selectedIndex: Int) {
        let focused = window?.firstResponder as? SettingsTabButton
        if titles != buttons.map(\.title) {
            let next = titles.map { title in
                if let button = cachedButtons[title] { return button }
                let button = SettingsTabButton(title: title)
                button.target = self
                button.action = #selector(selectTab(_:))
                button.setAccessibilitySubrole(.tabButtonSubrole)
                button.onMoveSelection = { [weak self, weak button] offset in
                    guard let self, let button,
                          let index = self.buttons.firstIndex(where: { $0 === button }) else { return }
                    self.moveSelection(from: index, offset: offset)
                }
                cachedButtons[title] = button
                return button
            }
            for button in buttons where !next.contains(where: { $0 === button }) {
                button.removeFromSuperview()
            }
            for (index, button) in next.enumerated() {
                insertArrangedSubview(button, at: index)
            }
            buttons = next
            invalidateIntrinsicContentSize()
        }

        self.selectedIndex = selectedIndex
        for (index, button) in buttons.enumerated() {
            button.tag = index
            button.state = index == selectedIndex ? .on : .off
            button.setAccessibilityValue(NSNumber(value: index == selectedIndex))
            button.needsDisplay = true
        }
        setAccessibilityChildren(buttons)
        setAccessibilitySelectedChildren(buttons.indices.contains(selectedIndex) ? [buttons[selectedIndex]] : [])

        // Hot-plugging a display must not drop keyboard focus from the tab row.
        if let focused {
            let replacement = buttons.first { $0 === focused }
                ?? (buttons.indices.contains(selectedIndex) ? buttons[selectedIndex] : nil)
            window?.makeFirstResponder(replacement)
        }
    }

    @objc private func selectTab(_ sender: SettingsTabButton) {
        onSelect?(sender.tag)
    }

    private func moveSelection(from index: Int, offset: Int) {
        guard !buttons.isEmpty else { return }
        let next = (index + offset + buttons.count) % buttons.count
        onSelect?(next)
        window?.makeFirstResponder(buttons[next])
    }
}
