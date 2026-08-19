import AppKit

private class NotebookItemWrapperView: NSView {
    var onTrackingAreasUpdated: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        onTrackingAreasUpdated?()
    }
}

class NotebookBaseItem: NSCollectionViewItem {

    var onResize: ((NotebookBlock, CGFloat) -> Void)?
    var onDragBegan: ((NSEvent) -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: ((NSEvent) -> Void)?
    var onDragCancelled: (() -> Void)?
    var onRun: (() -> Void)?
    var onMenuTapped: ((NSButton) -> Void)?
    var onConfigTapped: ((NSView) -> Void)?
    var onTitleChanged: ((String) -> Void)?
    var onToggleDashboardVisibility: (() -> Void)?

    private(set) var dragHandle: DashboardDragHandle!
    private(set) var titleLabel: NSTextField!
    private(set) var blockContainer: NSView!
    private(set) var resizeHandle: BlockResizeHandle!
    private var resizeHandleHeightConstraint: NSLayoutConstraint!

    private var actionBar: BlockActionBar!

    weak var currentBlock: NotebookBlock?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    func setRunLoading(_ loading: Bool) {
        actionBar.setRunLoading(loading)
        forceActionBarVisible = loading
    }
    var isMenuForceHovered = false
    var isConfigForceHovered = false
    var forceActionBarVisible = false {
        didSet {
            updateActionBarVisibility()
            actionBar.setMenuButtonForceHover(isMenuForceHovered)
            actionBar.setConfigButtonForceHover(isConfigForceHovered)
        }
    }

    var minimumContentHeight: CGFloat { 80 }

    override func loadView() {
        let wrapper = NotebookItemWrapperView()
        wrapper.wantsLayer = true
        wrapper.layer?.masksToBounds = false
        wrapper.onTrackingAreasUpdated = { [weak self] in
            self?.refreshHoverState()
        }
        self.view = wrapper

        setupDragHandle()
        setupTitleLabel()
        setupActionBar()
        setupBlockContainer()
        setupContent()
        setupResizeHandle()
        setupBaseConstraints()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setupContent() {
        // Subclasses override to add their content to blockContainer
    }

    func configureBase(block: NotebookBlock) {
        currentBlock = block

        titleLabel.stringValue = block.title.isEmpty ? "Untitled \(block.blockType.displayName)" : block.title
        let isSingleValue = block.blockType == .singleValue
        let isText = block.blockType == .text
        actionBar.setRunButtonHidden(isText)
        actionBar.setConfigButtonHidden(!isSingleValue)
        actionBar.setDashboardHidden(block.isHiddenInDashboard)
        resizeHandle.isHidden = isSingleValue
        resizeHandleHeightConstraint.constant = isSingleValue ? 0 : 12

        blockContainer.layer?.borderColor = borderColorForAppearance()
    }

    // MARK: - Setup

    private func setupDragHandle() {
        dragHandle = DashboardDragHandle()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        dragHandle.alphaValue = 0
        dragHandle.setContentHuggingPriority(.required, for: .horizontal)
        dragHandle.onDragBegan = { [weak self] event in self?.onDragBegan?(event) }
        dragHandle.onDragMoved = { [weak self] event in self?.onDragMoved?(event) }
        dragHandle.onDragEnded = { [weak self] event in self?.onDragEnded?(event) }
        dragHandle.onDragCancelled = { [weak self] in self?.onDragCancelled?() }
        view.addSubview(dragHandle)
    }

    private func setupTitleLabel() {
        titleLabel = NSTextField(string: "")
        titleLabel.placeholderString = "Untitled"
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.backgroundColor = .clear
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.focusRingType = .none
        titleLabel.isEditable = true
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.target = self
        titleLabel.action = #selector(titleFieldDidChange)
        view.addSubview(titleLabel)
    }

    @objc private func titleFieldDidChange() {
        onTitleChanged?(titleLabel.stringValue)
    }

    private func setupActionBar() {
        actionBar = BlockActionBar(
            onRun: { [weak self] in self?.onRun?() },
            onToggleDashboard: { [weak self] in self?.onToggleDashboardVisibility?() },
            onConfig: { [weak self] sender in self?.onConfigTapped?(sender) },
            onMenu: { [weak self] sender in self?.onMenuTapped?(sender) }
        )
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBar.alphaValue = 0
        view.addSubview(actionBar)
    }

    private func setupBlockContainer() {
        blockContainer = NSView()
        blockContainer.wantsLayer = true
        blockContainer.layer?.cornerRadius = 10
        blockContainer.layer?.borderWidth = 1
        blockContainer.layer?.borderColor = borderColorForAppearance()
        blockContainer.layer?.masksToBounds = true
        blockContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blockContainer)
    }

    private func setupResizeHandle() {
        resizeHandle = BlockResizeHandle(onDrag: { [weak self] delta in
            guard let self, let block = self.currentBlock else { return }
            let newHeight = max(self.minimumContentHeight, block.blockHeight + Double(delta))
            self.onResize?(block, newHeight)
        })
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.alphaValue = 0
        view.addSubview(resizeHandle)
    }

    private func setupBaseConstraints() {
        resizeHandleHeightConstraint = resizeHandle.heightAnchor.constraint(equalToConstant: 12)

        NSLayoutConstraint.activate([
            dragHandle.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            dragHandle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            dragHandle.widthAnchor.constraint(equalToConstant: 14),
            dragHandle.heightAnchor.constraint(equalToConstant: 14),

            actionBar.topAnchor.constraint(equalTo: view.topAnchor),
            actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),

            titleLabel.bottomAnchor.constraint(equalTo: actionBar.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: dragHandle.trailingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: -8),

            blockContainer.topAnchor.constraint(equalTo: actionBar.bottomAnchor, constant: 3),
            blockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blockContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            resizeHandle.topAnchor.constraint(equalTo: blockContainer.bottomAnchor),
            resizeHandle.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            resizeHandleHeightConstraint,
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Hover Tracking

    override func viewDidLayout() {
        super.viewDidLayout()
        refreshTrackingArea()
        refreshHoverState()
    }

    private var expandedHoverRect: NSRect {
        let overflow = max(0, -actionBar.frame.minY)
        return view.bounds.offsetBy(dx: 0, dy: -overflow).union(view.bounds)
    }

    private func refreshTrackingArea() {
        if let existing = trackingArea { view.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: expandedHoverRect,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    private func refreshHoverState() {
        guard let window = view.window else { return }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = view.convert(mouseInWindow, from: nil)
        let inside = expandedHoverRect.contains(mouseInView)
        setHovered(inside)
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        updateActionBarVisibility()
    }

    private func updateActionBarVisibility() {
        let visible = isHovered || forceActionBarVisible
        let isSingleValue = currentBlock?.blockType == .singleValue
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            let alpha: CGFloat = visible ? 1 : 0
            dragHandle.animator().alphaValue = isHovered ? 1 : 0
            actionBar.animator().alphaValue = alpha
            if !isSingleValue {
                resizeHandle.animator().alphaValue = isHovered ? 1 : 0
            }
        }
    }

    // MARK: - Appearance

    private func borderColorForAppearance() -> CGColor {
        var color: CGColor = NSColor.clear.cgColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            color = isDark
                ? NSColor.white.withAlphaComponent(0.1).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
        }
        return color
    }

    @objc private func handleAppearanceChange() {
        blockContainer.layer?.borderColor = borderColorForAppearance()
    }
}

// MARK: - Block Action Bar

final class BlockActionBar: NSView {

    private let onRun: () -> Void
    private let onToggleDashboard: () -> Void
    private let onMenu: ((NSButton) -> Void)?
    private let onConfig: ((NSView) -> Void)?

    private let chrome = BlockActionBarChrome()
    private let buttonStack = NSStackView()
    private var runButton: BlockActionButton!
    private var dashboardButton: BlockActionButton!
    private var configButton: BlockActionButton!
    private var menuButton: BlockActionMenuButton?

    init(
        onRun: @escaping () -> Void,
        onToggleDashboard: @escaping () -> Void,
        onConfig: ((NSView) -> Void)? = nil,
        onMenu: ((NSButton) -> Void)? = nil
    ) {
        self.onRun = onRun
        self.onToggleDashboard = onToggleDashboard
        self.onConfig = onConfig
        self.onMenu = onMenu
        super.init(frame: .zero)

        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setRunButtonHidden(_ hidden: Bool) {
        runButton.isHidden = hidden
    }

    func setConfigButtonHidden(_ hidden: Bool) {
        configButton.isHidden = hidden
    }

    func setMenuButtonForceHover(_ force: Bool) {
        menuButton?.forceHover = force
    }

    func setConfigButtonForceHover(_ force: Bool) {
        configButton.forceHover = force
    }

    func setRunLoading(_ loading: Bool) {
        runButton.isLoading = loading
    }

    func setDashboardHidden(_ hidden: Bool) {
        let iconName = hidden ? "square.grid.2x2" : "square.grid.2x2.fill"
        dashboardButton.updateIcon(iconName, size: 10)
        dashboardButton.installCustomTooltip(
            hidden ? "Show in Dashboard" : "Hide from Dashboard",
            position: .top,
            delay: 0
        )
    }

    private func setupViews() {
        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome)

        runButton = BlockActionButton(
            iconName: "play.fill",
            size: 10,
            action: { [weak self] _ in self?.onRun() }
        )
        runButton.installCustomTooltip("Run", position: .top, delay: 0)

        dashboardButton = BlockActionButton(
            iconName: "square.grid.2x2",
            size: 10,
            action: { [weak self] _ in self?.onToggleDashboard() }
        )

        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 0
        buttonStack.distribution = .fill
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        buttonStack.addArrangedSubview(dashboardButton)

        configButton = BlockActionButton(
            iconName: "gearshape",
            size: 10,
            action: { [weak self] sender in self?.onConfig?(sender) }
        )
        configButton.installCustomTooltip("Configure", position: .top, delay: 0)
        configButton.isHidden = true
        buttonStack.addArrangedSubview(configButton)

        buttonStack.addArrangedSubview(runButton)

        if onMenu != nil {
            let menu = BlockActionMenuButton(
                action: { [weak self] sender in self?.onMenu?(sender) }
            )
            buttonStack.addArrangedSubview(menu)
            self.menuButton = menu
        }

        chrome.addSubview(buttonStack)

        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        var constraints = [
            heightAnchor.constraint(equalToConstant: 26),

            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),

            buttonStack.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 3),
            buttonStack.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 4),
            buttonStack.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -4),
            buttonStack.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -3),

            runButton.widthAnchor.constraint(equalToConstant: 26),
            runButton.heightAnchor.constraint(equalToConstant: 20),

            dashboardButton.widthAnchor.constraint(equalToConstant: 26),
            dashboardButton.heightAnchor.constraint(equalToConstant: 20),

            configButton.widthAnchor.constraint(equalToConstant: 26),
            configButton.heightAnchor.constraint(equalToConstant: 20),
        ]

        if let menuButton {
            constraints.append(menuButton.widthAnchor.constraint(equalToConstant: 26))
            constraints.append(menuButton.heightAnchor.constraint(equalToConstant: 20))
        }

        NSLayoutConstraint.activate(constraints)
    }
}

// MARK: - Chrome Background

final class BlockActionBarChrome: NSView {

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }

    private func updateAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = isDark ? 1 : 0.5

            if isDark {
                layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            } else {
                layer?.backgroundColor = NSColor.white.cgColor
            }
        }
    }
}

// MARK: - Action Button

final class BlockActionButton: NSView {

    private let action: (BlockActionButton) -> Void
    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false
    var forceHover = false {
        didSet { updateAppearance() }
    }

    func updateIcon(_ iconName: String, size: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    var isLoading = false {
        didSet {
            guard isLoading != oldValue else { return }
            iconView.isHidden = isLoading
            spinner.isHidden = !isLoading
            if isLoading {
                spinner.startAnimation(nil)
            } else {
                spinner.stopAnimation(nil)
            }
        }
    }

    init(iconName: String, size: CGFloat, action: @escaping (BlockActionButton) -> Void) {
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5

        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )

        updateAppearance()
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point), !isHidden, alphaValue > 0 else { return nil }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        let mousePoint = convert(event.locationInWindow, from: nil)
        let isInside = bounds.contains(mousePoint)
        let nextPressed = isInside
        let nextHovering = isInside

        guard nextPressed != isPressed || nextHovering != isHovering else { return }
        isPressed = nextPressed
        isHovering = nextHovering
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let mousePoint = convert(event.locationInWindow, from: nil)
        let isInside = bounds.contains(mousePoint)

        isPressed = false
        isHovering = isInside
        updateAppearance()

        if isInside {
            action(self)
        }
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }

    private func refreshHoverState() {
        guard let window else {
            if isHovering {
                isHovering = false
                updateAppearance()
            }
            return
        }

        let mousePoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let isInside = bounds.contains(mousePoint)
        guard isInside != isHovering else { return }
        isHovering = isInside
        updateAppearance()
    }

    private func updateAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            let isHighlighted = isHovering || isPressed || forceHover

            if isHighlighted {
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.1).cgColor
                    : NSColor.black.withAlphaComponent(0.07).cgColor
                iconView.contentTintColor = .labelColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                iconView.contentTintColor = .secondaryLabelColor
            }

            let scale: CGFloat = isPressed ? 0.85 : 1
            let tx = bounds.width * (1 - scale) / 2
            let ty = bounds.height * (1 - scale) / 2
            var transform = CATransform3DMakeTranslation(tx, ty, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            layer?.transform = isPressed ? transform : CATransform3DIdentity
        }
    }
}

// MARK: - Menu Button (NSButton wrapper for popover attachment)

final class BlockActionMenuButton: NSView {

    private let action: (NSButton) -> Void
    private let button: NSButton
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    var forceHover = false {
        didSet { updateAppearance() }
    }

    init(action: @escaping (NSButton) -> Void) {
        self.action = action

        button = NSButton(frame: .zero)
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        button.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        button.bezelStyle = .accessoryBar
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5

        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(handleTap)
        addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleTap(_ sender: NSButton) {
        action(sender)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point), !isHidden, alphaValue > 0 else { return nil }
        return button
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
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }

    private func updateAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode

            if isHovering || forceHover {
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.1).cgColor
                    : NSColor.black.withAlphaComponent(0.07).cgColor
                button.contentTintColor = .labelColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                button.contentTintColor = .secondaryLabelColor
            }
        }
    }
}
