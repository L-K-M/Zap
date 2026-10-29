import AppKit

/// A custom NSButton that renders as a folder-shaped settings tab with rounded
/// top corners and square bottom corners.  Selected buttons draw an outline along
/// the top and sides (no bottom edge) so the tab visually joins its content pane.
final class SettingsTabButton: NSButton {

    private static let buttonHeight: CGFloat = 36
    private static let fontSize: CGFloat = 13
    private static let horizontalPadding: CGFloat = 14
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false

    /// Called with the directional delta when the left or right arrow key is
    /// pressed while the button has keyboard focus.
    var onMoveSelection: ((Int) -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        setButtonType(.radio)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        bezelStyle = .regularSquare
        isBordered = false
        focusRingType = .exterior
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    override func accessibilityLabel() -> String? { title }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    // MARK: - NSButton overrides

    override var intrinsicContentSize: CGSize {
        let font = NSFont.systemFont(ofSize: Self.fontSize, weight: .semibold)
        let width = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        return CGSize(width: width + 2 * Self.horizontalPadding, height: Self.buttonHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: CGRect) {
        let path = tabPath(in: bounds)
        drawFill(path: path)
        drawOutline()
        drawTitle(in: bounds)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case UInt16(KeyCode.arrowLeft):
            onMoveSelection?(-1)
        case UInt16(KeyCode.arrowRight):
            onMoveSelection?(1)
        default:
            super.keyDown(with: event)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Drawing

    private func tabPath(in rect: CGRect, closesBottom: Bool = true) -> NSBezierPath {
        let r = min(8, min(rect.width / 2, rect.height))
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.line(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.curve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                   controlPoint1: CGPoint(x: rect.minX, y: rect.maxY),
                   controlPoint2: CGPoint(x: rect.minX, y: rect.maxY))
        path.line(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.curve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                   controlPoint1: CGPoint(x: rect.maxX, y: rect.maxY),
                   controlPoint2: CGPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        if closesBottom { path.close() }
        return path
    }

    private func drawFill(path: NSBezierPath) {
        let fill: NSColor
        if state == .on {
            fill = NSColor.windowBackgroundColor
        } else {
            fill = NSColor.controlBackgroundColor.withAlphaComponent(isHovering ? 0.8 : 0.35)
        }
        fill.set()
        path.fill()
        if cell?.isHighlighted == true {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
        }
    }

    private func drawOutline() {
        let outlineColor: NSColor
        if state == .on {
            outlineColor = NSColor.separatorColor
        } else if isHovering {
            outlineColor = NSColor.separatorColor.withAlphaComponent(0.5)
        } else {
            outlineColor = NSColor.separatorColor
        }

        outlineColor.set()
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outline = tabPath(in: rect, closesBottom: state != .on)
        outline.lineWidth = 1
        outline.stroke()
    }

    private func drawTitle(in rect: CGRect) {
        let textColor: NSColor
        if state == .on {
            textColor = NSColor.labelColor
        } else {
            textColor = NSColor.secondaryLabelColor
        }

        let font: NSFont
        if state == .on {
            font = NSFont.systemFont(ofSize: Self.fontSize, weight: .semibold)
        } else {
            font = NSFont.systemFont(ofSize: Self.fontSize, weight: .regular)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: font
        ]

        let titleStr = title as NSString
        let size = titleStr.size(withAttributes: attributes)
        let originX = (rect.width - size.width) / 2
        let originY = (rect.height - size.height) / 2 + 1
        let textRect = CGRect(x: originX, y: originY, width: size.width, height: size.height)

        titleStr.draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - Focus Ring

    override func drawFocusRingMask() {
        let path = tabPath(in: bounds.insetBy(dx: 2, dy: 2))
        path.fill()
    }

}
