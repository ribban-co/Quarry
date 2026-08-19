import AppKit

final class AgentHeaderView: NSView {

    var onNewChat: () -> Void = {}
    var onCompose: () -> Void = {}
    var onClose: () -> Void = {}

    /// When set, the mode-switch dropdown becomes interactive and presents this
    /// menu anchored to the dropdown button. Used by the table view's right dock
    /// to switch between Row Detail and Chat. Hidden entirely in the notebook.
    var modeMenuProvider: (() -> NSMenu)?

    private let newChatButton: AgentHeaderTextButton
    private let modeButton: AgentHeaderDropdownIconButton
    private let composeButton: AgentHeaderIconButton
    private let closeButton: AgentHeaderIconButton
    private let rightStack: NSStackView
    private var heightConstraint: NSLayoutConstraint!
    private var rightStackTrailingConstraint: NSLayoutConstraint!

    private var topPadding: CGFloat {
        if #available(macOS 26, *) { 14 } else { 12 }
    }

    private var defaultHeight: CGFloat { topPadding + 26 + 10 }

    private var leadingPadding: CGFloat {
        if #available(macOS 26, *) { 0 } else { 4 }
    }

    override init(frame: NSRect) {
        newChatButton = AgentHeaderTextButton(label: "New AI Chat")
        modeButton = AgentHeaderDropdownIconButton(symbolName: "sidebar.right", pointSize: 13, weight: .medium)
        composeButton = AgentHeaderIconButton(symbolName: "square.and.pencil", pointSize: 13, weight: .medium, yOffset: -1)
        closeButton = AgentHeaderIconButton(symbolName: "xmark", pointSize: 13, weight: .medium)
        rightStack = NSStackView(views: [composeButton, modeButton, closeButton])

        super.init(frame: frame)

        modeButton.isHidden = true
        newChatButton.action = { [weak self] in self?.onNewChat() }
        modeButton.action = { [weak self] in self?.presentModeMenu() }
        composeButton.action = { [weak self] in self?.onCompose() }
        closeButton.action = { [weak self] in self?.onClose() }

        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var dropdownButtonBounds: NSRect {
        newChatButton.frame
    }

    func updateTitle(_ text: String) {
        newChatButton.updateLabel(text)
    }

    func setNewChatEnabled(_ isEnabled: Bool) {
        composeButton.isEnabled = isEnabled
    }

    func setModeSwitcherVisible(_ visible: Bool) {
        modeButton.isHidden = !visible
    }

    /// Swaps the mode-switch dropdown's icon so it can reflect the current
    /// mode instead of the default sidebar glyph.
    func setModeIcon(_ symbolName: String) {
        modeButton.updateSymbol(symbolName)
    }

    func setComposeVisible(_ visible: Bool) {
        composeButton.isHidden = !visible
    }

    /// Tightens the header to a compact height. Used by the table view's right
    /// dock where the header sits flush against the top, unlike the notebook
    /// which needs the taller default padding.
    func setCompactHeight(_ compact: Bool) {
        heightConstraint.constant = compact ? 36 : defaultHeight
    }

    /// Distance from the close button cluster to the header's trailing edge.
    /// Defaults to 10 (notebook); the table dock uses a tighter value.
    func setTrailingInset(_ inset: CGFloat) {
        rightStackTrailingConstraint.constant = -inset
    }

    /// Enlarges the close and mode-switch buttons. Defaults to 26 (notebook);
    /// the table dock uses a larger hit target.
    func setControlSize(_ size: CGFloat) {
        closeButton.setSize(size)
        composeButton.setSize(size)
        modeButton.setHeight(size)
    }

    private func presentModeMenu() {
        guard let menu = modeMenuProvider?() else { return }
        // Non-flipped coordinates: the menu's top-left lands at the given point
        // and extends downward, so anchor just below the button's bottom edge.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: modeButton)
    }

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false

        rightStack.orientation = .horizontal
        rightStack.spacing = 4
        rightStack.setContentHuggingPriority(.required, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        newChatButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        newChatButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        newChatButton.translatesAutoresizingMaskIntoConstraints = false
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(newChatButton)
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            newChatButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingPadding),
            newChatButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newChatButton.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),

            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        rightStackTrailingConstraint = rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        rightStackTrailingConstraint.isActive = true

        heightConstraint = heightAnchor.constraint(equalToConstant: defaultHeight)
        heightConstraint.isActive = true
    }
}

/// Corner radius as a fraction of the control's box size, so a 24pt notebook
/// button and a 30pt table-dock button read as the same shape instead of the
/// smaller one turning into a pill.
private let agentHeaderCornerRadiusRatio: CGFloat = 1.0 / 3.0

private final class AgentHeaderIconButton: NSView {

    var action: () -> Void = {}
    var isEnabled = true {
        didSet {
            if !isEnabled {
                isHovering = false
            }
            updateVisualState()
        }
    }

    private let iconView: NSImageView
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!

    init(symbolName: String, pointSize: CGFloat, weight: NSFont.Weight, yOffset: CGFloat = 0) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)

        iconView = NSImageView(image: image ?? NSImage())
        iconView.contentTintColor = .secondaryLabelColor

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 24 * agentHeaderCornerRadiusRatio

        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        widthConstraint = widthAnchor.constraint(equalToConstant: 24)
        heightConstraint = heightAnchor.constraint(equalToConstant: 24)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: yOffset),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setSize(_ size: CGFloat) {
        widthConstraint.constant = size
        heightConstraint.constant = size
        layer?.cornerRadius = size * agentHeaderCornerRadiusRatio
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

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = true
        applyIconHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = false
        applyIconHover(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        action()
    }

    private func refreshHoverState() {
        guard isEnabled, let window else {
            isHovering = false
            applyIconHover(false)
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        applyIconHover(isHovering)
    }

    private func applyIconHover(_ on: Bool) {
        guard let layer else { return }
        if on {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.08).cgColor
                : NSColor.black.withAlphaComponent(0.06).cgColor
        } else {
            layer.backgroundColor = nil
        }
    }

    @objc private func handleAppearanceChange() {
        updateVisualState()
    }

    private func updateVisualState() {
        alphaValue = isEnabled ? 1 : 0.45
        applyIconHover(isEnabled && isHovering)
    }
}

private final class AgentHeaderDropdownIconButton: NSView {

    var action: () -> Void = {}

    private let panelIcon: NSImageView
    private let chevron: NSImageView
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var heightConstraint: NSLayoutConstraint!

    init(symbolName: String, pointSize: CGFloat, weight: NSFont.Weight) {
        let panelConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let panelImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(panelConfig)
        panelIcon = NSImageView(image: panelImage ?? NSImage())
        panelIcon.contentTintColor = .secondaryLabelColor

        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
        let chevronImage = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(chevronConfig)
        chevron = NSImageView(image: chevronImage ?? NSImage())
        chevron.contentTintColor = .secondaryLabelColor

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 26 * agentHeaderCornerRadiusRatio

        let stack = NSStackView(views: [panelIcon, chevron])
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        heightConstraint = heightAnchor.constraint(equalToConstant: 26)

        NSLayoutConstraint.activate([
            heightConstraint,
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    func updateSymbol(_ symbolName: String, pointSize: CGFloat = 13, weight: NSFont.Weight = .medium) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        panelIcon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setHeight(_ height: CGFloat) {
        heightConstraint.constant = height
        layer?.cornerRadius = height * agentHeaderCornerRadiusRatio
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

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyModeHoverBackground(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyModeHoverBackground(false)
    }

    override func mouseDown(with event: NSEvent) {
        action()
        // The menu's tracking session swallows mouseExited; re-derive the hover
        // state once it returns so the highlight doesn't stick.
        refreshHoverState()
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            applyModeHoverBackground(false)
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        applyModeHoverBackground(isHovering)
    }

    private func applyModeHoverBackground(_ on: Bool) {
        guard let layer else { return }
        if on {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.08).cgColor
                : NSColor.black.withAlphaComponent(0.06).cgColor
        } else {
            layer.backgroundColor = nil
        }
    }

    @objc private func handleAppearanceChange() {
        applyModeHoverBackground(isHovering)
    }
}

private final class AgentHeaderTextButton: NSView {

    var action: () -> Void = {}

    private let label: NSTextField
    private let chevron: NSImageView
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(label text: String) {
        label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.preferredMaxLayoutWidth = 180
        label.cell?.wraps = false
        label.cell?.isScrollable = false
        label.cell?.truncatesLastVisibleLine = true

        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        chevron = NSImageView(image: image ?? NSImage())
        chevron.contentTintColor = .secondaryLabelColor

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 10

        let stack = NSStackView(views: [label, chevron])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyHoverBackground(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(false)
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            applyHoverBackground(false)
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        applyHoverBackground(isHovering)
    }

    @objc private func handleAppearanceChange() {
        applyHoverBackground(isHovering)
    }

    func updateLabel(_ text: String) {
        label.stringValue = text
    }
}
