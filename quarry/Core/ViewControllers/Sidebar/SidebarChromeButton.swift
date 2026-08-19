import AppKit

/// Icon-only button used across the AppKit sidebar. Provides a centered,
/// fixed-size hover background that re-resolves its color for the current
/// appearance so dark mode is actually visible.
@MainActor
final class SidebarChromeButton: NSButton {
    private static let hoverSize: CGFloat = 26

    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private let hoverBackground = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        hoverBackground.cornerRadius = 6
        hoverBackground.opacity = 0
        layer?.insertSublayer(hoverBackground, at: 0)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        applyAppearanceColors()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.hoverSize, height: Self.hoverSize)
    }

    override func layout() {
        super.layout()
        let size = Self.hoverSize
        hoverBackground.frame = NSRect(
            x: (bounds.width - size) / 2,
            y: (bounds.height - size) / 2,
            width: size,
            height: size
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hoverBackground.backgroundColor = NSColor.separatorColor.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        refreshHoverState()
    }

    private func refreshHoverState() {
        guard let window,
              let mouse = window.mouseLocationOutsideOfEventStream as NSPoint? else {
            setHovering(false)
            return
        }
        let point = convert(mouse, from: nil)
        setHovering(bounds.contains(point))
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverBackground.opacity = isHovering ? 1 : 0
        CATransaction.commit()
    }
}
