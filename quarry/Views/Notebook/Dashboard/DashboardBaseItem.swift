import AppKit

private class DashboardItemWrapperView: NSView {
    var onTrackingAreasUpdated: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        onTrackingAreasUpdated?()
    }
}

class DashboardBaseItem: NSCollectionViewItem {

    var onResize: ((NotebookBlock, CGFloat) -> Void)?
    var onWidthResize: ((NotebookBlock, CGFloat) -> Void)?
    var onDragBegan: ((NSEvent) -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: ((NSEvent) -> Void)?
    var onDragCancelled: (() -> Void)?
    var onRun: (() -> Void)?
    var onToggleDashboardVisibility: (() -> Void)?

    private(set) var dragHandle: DashboardDragHandle!
    private(set) var titleLabel: NSTextField!
    private(set) var actionBar: BlockActionBar!
    private(set) var blockContainer: NSView!
    private(set) var resizeHandle: BlockResizeHandle!
    private(set) var widthResizeHandle: BlockWidthResizeHandle!
    private(set) var handleWidthConstraint: NSLayoutConstraint!
    private var blockContainerTopToActionBar: NSLayoutConstraint!
    private var blockContainerTopToView: NSLayoutConstraint!
    private var resizeHandleHeightConstraint: NSLayoutConstraint!

    weak var currentBlock: NotebookBlock?
    private(set) var isPublished = false
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isResizing = false
    private var lastTrackedBounds: NSRect = .zero

    var minimumContentHeight: CGFloat { 80 }

    override func loadView() {
        let wrapper = DashboardItemWrapperView()
        wrapper.wantsLayer = true
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
        setupWidthResizeHandle()
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

    func configureBase(block: NotebookBlock, isPublished: Bool) {
        currentBlock = block
        self.isPublished = isPublished
        isHovered = false

        titleLabel.stringValue = block.title.isEmpty ? "Untitled \(block.blockType.displayName)" : block.title
        let isText = block.blockType == .text
        let showsHeightResizeHandle = !isPublished
        let showsWidthResizeHandle = !isPublished
        titleLabel.isHidden = false
        dragHandle.isHidden = isPublished
        actionBar.isHidden = isPublished
        actionBar.setRunButtonHidden(isText)
        actionBar.setDashboardHidden(block.isHiddenInDashboard)
        resizeHandle.isHidden = !showsHeightResizeHandle
        widthResizeHandle.isHidden = !showsWidthResizeHandle
        handleWidthConstraint.constant = showsWidthResizeHandle ? 12 : 0
        resizeHandleHeightConstraint.constant = showsHeightResizeHandle ? 12 : 0

        blockContainerTopToActionBar.isActive = true
        blockContainerTopToView.isActive = false

        updateChrome(animated: false)
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
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
    }

    private func setupActionBar() {
        actionBar = BlockActionBar(
            onRun: { [weak self] in self?.onRun?() },
            onToggleDashboard: { [weak self] in self?.onToggleDashboardVisibility?() }
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
        blockContainer.layer?.borderColor = NSColor.clear.cgColor
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
        resizeHandle.onDragStateChanged = { [weak self] isDragging in
            self?.setResizing(isDragging)
        }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.alphaValue = 0
        view.addSubview(resizeHandle)
    }

    private func setupWidthResizeHandle() {
        widthResizeHandle = BlockWidthResizeHandle(onDrag: { [weak self] delta in
            guard let self, let block = self.currentBlock else { return }
            self.onWidthResize?(block, delta)
        })
        widthResizeHandle.onDragStateChanged = { [weak self] isDragging in
            self?.setResizing(isDragging)
        }
        widthResizeHandle.translatesAutoresizingMaskIntoConstraints = false
        widthResizeHandle.alphaValue = 0
        view.addSubview(widthResizeHandle)
    }

    private func setupBaseConstraints() {
        handleWidthConstraint = widthResizeHandle.widthAnchor.constraint(equalToConstant: 12)
        blockContainerTopToActionBar = blockContainer.topAnchor.constraint(equalTo: actionBar.bottomAnchor, constant: 4)
        blockContainerTopToView = blockContainer.topAnchor.constraint(equalTo: view.topAnchor)
        resizeHandleHeightConstraint = resizeHandle.heightAnchor.constraint(equalToConstant: 12)

        blockContainerTopToActionBar.isActive = true

        NSLayoutConstraint.activate([
            dragHandle.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            dragHandle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            dragHandle.widthAnchor.constraint(equalToConstant: 14),
            dragHandle.heightAnchor.constraint(equalToConstant: 14),

            actionBar.topAnchor.constraint(equalTo: view.topAnchor),
            actionBar.trailingAnchor.constraint(equalTo: widthResizeHandle.leadingAnchor),

            titleLabel.bottomAnchor.constraint(equalTo: actionBar.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: dragHandle.trailingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: -8),

            blockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blockContainer.trailingAnchor.constraint(equalTo: widthResizeHandle.leadingAnchor),

            widthResizeHandle.topAnchor.constraint(equalTo: blockContainer.topAnchor),
            widthResizeHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            handleWidthConstraint,
            widthResizeHandle.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),

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
        if view.bounds != lastTrackedBounds {
            lastTrackedBounds = view.bounds
            refreshTrackingArea()
            refreshHoverState()
        }
    }

    private func refreshTrackingArea() {
        if let existing = trackingArea { view.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    private func refreshHoverState() {
        guard let window = view.window else { return }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = view.convert(mouseInWindow, from: nil)
        let inside = view.bounds.contains(mouseInView)
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
        updateChrome(animated: true)
    }

    private func setResizing(_ resizing: Bool) {
        guard resizing != isResizing else { return }
        isResizing = resizing
        updateChrome(animated: true)
    }

    private func updateChrome(animated: Bool) {
        let alwaysShowsBorder = currentBlock?.blockType == .singleValue || currentBlock?.blockType == .query
        if isPublished {
            let showBorder = isHovered || currentBlock?.blockType == .singleValue || currentBlock?.blockType == .query
            blockContainer.layer?.borderColor = showBorder ? borderColorForAppearance() : NSColor.clear.cgColor
            return
        }
        let isActive = isHovered || isResizing
        blockContainer.layer?.borderColor = (isActive || alwaysShowsBorder) ? borderColorForAppearance() : NSColor.clear.cgColor

        let updates = {
            let alpha: CGFloat = isActive ? 1 : 0
            self.dragHandle.animator().alphaValue = alpha
            self.actionBar.animator().alphaValue = alpha
            self.resizeHandle.animator().alphaValue = alpha
            self.widthResizeHandle.animator().alphaValue = alpha
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                updates()
            }
        } else {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            updates()
            NSAnimationContext.endGrouping()
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
        let alwaysShowsBorder = currentBlock?.blockType == .singleValue || currentBlock?.blockType == .query
        if isHovered || isResizing || (alwaysShowsBorder && !isPublished) {
            blockContainer.layer?.borderColor = borderColorForAppearance()
        }
    }
}
