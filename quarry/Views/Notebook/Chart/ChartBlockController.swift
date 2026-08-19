import AppKit
import SwiftUI

final class ChartBlockController: NSViewController, NSTextFieldDelegate {

    let viewModel: ChartBlockViewModel
    private let dataController: NotebookDataController
    private let showChrome: Bool

    private(set) var titleLabel: NSTextField!
    private var blockContainer: NSView!
    private var runButton: NSButton!
    private var menuButton: NSButton!
    private var resizeHandle: NSView!
    private var blockHeightConstraint: NSLayoutConstraint!
    private var configController: ChartConfigController?

    init(block: NotebookBlock, dataController: NotebookDataController, showChrome: Bool = true) {
        self.dataController = dataController
        self.viewModel = dataController.chartViewModel(for: block)
        self.showChrome = showChrome
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        if showChrome {
            let wrapper = BlockHoverTrackingView { [weak self] isHovered in
                guard let self,
                      let blockIndex = self.dataController.blocks.firstIndex(where: { $0.id == self.viewModel.block.id }) else { return }
                let showButtons = isHovered || self.popover?.isShown == true
                self.runButton.isHidden = !showButtons
                self.menuButton.isHidden = !showButtons
                NotificationCenter.default.post(
                    name: .notebookBlockHoverChanged,
                    object: nil,
                    userInfo: ["blockIndex": blockIndex, "isHovered": isHovered]
                )
            }
            wrapper.wantsLayer = true
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            self.view = wrapper

            setupTitleLabel()
            setupBlockContainer()
            setupRunButton()
            setupMenuButton()
            setupResizeHandle()
            setupWrapperConstraints()
            setupConfigView()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppearanceChange),
                name: .appAppearanceDidChange,
                object: nil
            )
        } else {
            let wrapper = NSView()
            wrapper.wantsLayer = true
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            self.view = wrapper

            setupBlockContainer()
            blockContainer.layer?.borderWidth = 0

            NSLayoutConstraint.activate([
                blockContainer.topAnchor.constraint(equalTo: view.topAnchor),
                blockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                blockContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                blockContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            setupConfigView()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func setupTitleLabel() {
        let text = viewModel.block.title.isEmpty ? "Untitled Chart" : viewModel.block.title
        titleLabel = NSTextField(string: text)
        titleLabel.placeholderString = "Untitled Chart"
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.backgroundColor = .clear
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.focusRingType = .none
        titleLabel.isEditable = true
        titleLabel.delegate = self
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
    }

    private func setupBlockContainer() {
        blockContainer = NSView()
        blockContainer.wantsLayer = true
        blockContainer.layer?.cornerRadius = 10
        blockContainer.layer?.borderWidth = 1
        blockContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blockContainer)
        updateBorderColor()
    }

    private func setupRunButton() {
        runButton = NSButton(frame: .zero)
        runButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run")
        runButton.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        runButton.bezelStyle = .accessoryBar
        runButton.isBordered = false
        runButton.imagePosition = .imageOnly
        runButton.contentTintColor = .white
        runButton.wantsLayer = true
        runButton.layer?.cornerRadius = 4
        runButton.layer?.backgroundColor = NSColor.primaryButton.cgColor
        runButton.isHidden = true
        runButton.translatesAutoresizingMaskIntoConstraints = false
        runButton.target = self
        runButton.action = #selector(handleRunTapped)
        view.addSubview(runButton)
    }

    @objc private func handleRunTapped() {
        Task { await viewModel.runChart() }
    }

    private func setupMenuButton() {
        menuButton = NSButton(frame: .zero)
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Block menu")
        menuButton.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        menuButton.bezelStyle = .accessoryBar
        menuButton.isBordered = false
        menuButton.imagePosition = .imageOnly
        menuButton.contentTintColor = .tertiaryLabelColor
        menuButton.isHidden = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.target = self
        menuButton.action = #selector(showBlockMenu(_:))
        view.addSubview(menuButton)
    }

    private func setupResizeHandle() {
        resizeHandle = BlockResizeHandle(onDrag: { [weak self] delta in
            self?.handleResize(delta: delta)
        })
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resizeHandle)
    }

    private func handleResize(delta: CGFloat) {
        let newHeight = max(280, blockHeightConstraint.constant + delta)
        blockHeightConstraint.constant = newHeight
        viewModel.block.blockHeight = newHeight
        dataController.updateBlock(viewModel.block)
    }

    private func setupWrapperConstraints() {
        let savedHeight = max(280, viewModel.block.blockHeight)
        blockHeightConstraint = blockContainer.heightAnchor.constraint(equalToConstant: savedHeight)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            runButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            runButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 18),
            runButton.heightAnchor.constraint(equalToConstant: 12),

            menuButton.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 2),
            menuButton.centerXAnchor.constraint(equalTo: runButton.centerXAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 24),
            menuButton.heightAnchor.constraint(equalToConstant: 24),

            blockContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            blockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blockContainer.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -4),
            blockHeightConstraint,

            resizeHandle.topAnchor.constraint(equalTo: blockContainer.bottomAnchor),
            resizeHandle.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: 12),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === titleLabel else { return }
        viewModel.block.title = field.stringValue
        dataController.updateBlock(viewModel.block)
    }

    // MARK: - Block Menu

    @objc private func showBlockMenu(_ sender: NSButton) {
        let block = viewModel.block
        let dc = dataController
        let dismiss = { [weak self] in self?.popover?.performClose(nil) }

        let blockIndex = dc.blocks.firstIndex(where: { $0.id == block.id }) ?? 0
        let isFirst = blockIndex == 0
        let isLast = blockIndex == dc.blocks.count - 1

        let popoverVC = BlockMenuPopoverController(
            canMoveUp: !isFirst,
            canMoveDown: !isLast,
            onAddAbove: { dismiss(); dc.insertChartBlock(at: blockIndex) },
            onAddBelow: { dismiss(); dc.insertChartBlock(at: blockIndex + 1) },
            onMoveUp: { dismiss(); dc.moveBlockUp(block) },
            onMoveDown: { dismiss(); dc.moveBlockDown(block) },
            onDuplicate: { dismiss(); dc.duplicateBlock(block) },
            onCopy: { [weak self] in dismiss(); self?.copyBlockConfig() },
            isHiddenInDashboard: block.isHiddenInDashboard,
            onToggleDashboardVisibility: { dismiss(); dc.toggleBlockDashboardVisibility(block) },
            onDelete: { dismiss(); dc.deleteBlock(block) }
        )

        let pop = NSPopover()
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        self.popover = pop
    }

    private var popover: NSPopover?

    private func copyBlockConfig() {
        let json = viewModel.block.configJSON
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    // MARK: - Block Styling

    private func updateBorderColor() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            blockContainer.layer?.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.1).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateBorderColor()
    }

    // MARK: - Content

    private func setupConfigView() {
        let configVC = ChartConfigController(viewModel: viewModel, connections: dataController.connections, dataController: dataController)
        addChild(configVC)
        configVC.view.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(configVC.view)
        configController = configVC

        NSLayoutConstraint.activate([
            configVC.view.topAnchor.constraint(equalTo: blockContainer.topAnchor),
            configVC.view.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            configVC.view.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            configVC.view.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),
        ])
    }

    // MARK: - Cleanup

    func cleanupSession() {
        Task { await viewModel.cleanup() }
    }
}

// MARK: - Source dropdown button

final class SourceDropdownButton: NSView, NSPopoverDelegate {

    private let connections: [Connection]
    private let queryDataSourcesProvider: (() -> [NotebookDataController.QueryDataSource])?
    private let onSelect: (Connection) -> Void
    private let onSelectQuerySource: ((NotebookDataController.QueryDataSource) -> Void)?
    private let iconView: NSImageView
    private let label: NSTextField
    private let chevron: NSImageView
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var labelLeadingWithIcon: NSLayoutConstraint!
    private var labelLeadingWithoutIcon: NSLayoutConstraint!
    var isEnabled = true

    init(
        connections: [Connection],
        queryDataSourcesProvider: (() -> [NotebookDataController.QueryDataSource])? = nil,
        onSelect: @escaping (Connection) -> Void,
        onSelectQuerySource: ((NotebookDataController.QueryDataSource) -> Void)? = nil
    ) {
        self.connections = connections
        self.queryDataSourcesProvider = queryDataSourcesProvider
        self.onSelect = onSelect
        self.onSelectQuerySource = onSelectQuerySource
        self.iconView = NSImageView()
        self.label = NSTextField(labelWithString: "Select connection")
        self.chevron = NSImageView()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconView.isHidden = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let chevronImage = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.image = chevronImage
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        labelLeadingWithIcon = label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4)
        labelLeadingWithoutIcon = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        labelLeadingWithoutIcon.isActive = true

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            chevron.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        let iconSectionWidth: CGFloat = iconView.isHidden ? 0 : 20
        let labelWidth = ceil(label.intrinsicContentSize.width)
        let chevronSectionWidth: CGFloat = 16
        let horizontalInsets: CGFloat = 12
        let width = iconSectionWidth + labelWidth + chevronSectionWidth + horizontalInsets
        return NSSize(width: width, height: 24)
    }

    func updateLabel(_ text: String, iconName: String? = nil, systemSymbol: String? = nil) {
        label.stringValue = text
        label.textColor = .secondaryLabelColor
        if let iconName {
            let img = NSImage(named: iconName)
            img?.size = NSSize(width: 14, height: 14)
            iconView.image = img
            iconView.isHidden = false
        } else if let systemSymbol {
            iconView.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: nil)
            iconView.symbolConfiguration = .init(pointSize: 11, weight: .medium)
            iconView.contentTintColor = .secondaryLabelColor
            iconView.isHidden = false
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }

        let showIcon = !iconView.isHidden
        labelLeadingWithIcon.isActive = showIcon
        labelLeadingWithoutIcon.isActive = !showIcon
        invalidateIntrinsicContentSize()
    }

    // MARK: - Tracking

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
        applyHoverBackground(isHovering)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(isHovering)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if popover != nil {
            popover?.performClose(nil)
            popover = nil
            return
        }
        showConnectionsPopover()
    }

    private var popover: NSPopover?

    private func refreshHoverState() {
        guard let window else {
            if isHovering { isHovering = false; applyHoverBackground(false) }
            return
        }
        let mouseInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let shouldHover = isEnabled && bounds.contains(mouseInView)
        if shouldHover != isHovering {
            isHovering = shouldHover
            applyHoverBackground(isHovering)
        }
    }

    // MARK: - Popover

    private func showConnectionsPopover() {
        let popoverVC = SourceConnectionsPopoverController(
            connections: connections,
            queryDataSources: queryDataSourcesProvider?() ?? [],
            onSelect: { [weak self] connection in
                self?.popover?.performClose(nil)
                self?.popover = nil
                self?.onSelect(connection)
            },
            onSelectQuerySource: { [weak self] source in
                self?.popover?.performClose(nil)
                self?.popover = nil
                self?.onSelectQuerySource?(source)
            }
        )

        let pop = NSPopover()
        pop.delegate = self
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        self.popover = pop
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}

// MARK: - Styled dropdown

final class StyledDropdown: NSView {

    private let placeholder: String
    private let onSelect: (String) -> Void
    private let menuVerticalOffset: CGFloat = 6
    private let label: NSTextField
    private let chevron: NSImageView
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private(set) var items: [String] = []
    private(set) var selectedTitle: String?
    var isEnabled = true {
        didSet { alphaValue = isEnabled ? 1.0 : 0.5 }
    }

    init(placeholder: String, onSelect: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.onSelect = onSelect
        self.label = NSTextField(labelWithString: placeholder)
        self.chevron = NSImageView()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        updateBorderColor()

        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: .appAppearanceDidChange, object: nil)

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        let collapseSafePriority = NSLayoutConstraint.Priority(rawValue: 999)
        let labelLeading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        labelLeading.priority = collapseSafePriority
        let labelToChevron = label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -4)
        labelToChevron.priority = collapseSafePriority
        let chevronTrailing = chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        chevronTrailing.priority = collapseSafePriority
        let chevronWidth = chevron.widthAnchor.constraint(equalToConstant: 12)
        chevronWidth.priority = collapseSafePriority

        NSLayoutConstraint.activate([
            labelLeading,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelToChevron,

            chevronTrailing,
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronWidth,
            chevron.heightAnchor.constraint(equalToConstant: 12),

            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appearanceChanged() {
        updateBorderColor()
    }

    private func updateBorderColor() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            layer?.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.1).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
        }
    }

    func setItems(_ newItems: [String]) {
        items = newItems
        if let sel = selectedTitle, !newItems.contains(sel) {
            selectedTitle = nil
            label.stringValue = placeholder
            label.textColor = .tertiaryLabelColor
        }
    }

    func selectItem(_ title: String) {
        selectedTitle = title
        label.stringValue = title
        label.textColor = .secondaryLabelColor
    }

    func clearSelection() {
        selectedTitle = nil
        label.stringValue = placeholder
        label.textColor = .tertiaryLabelColor
    }

    // MARK: - Tracking

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
        applyHoverBackground(isHovering)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(isHovering)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !items.isEmpty else { return }
        showMenu()
    }

    private func refreshHoverState() {
        guard let window else {
            if isHovering { isHovering = false; applyHoverBackground(false) }
            return
        }
        let mouseInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let shouldHover = isEnabled && bounds.contains(mouseInView)
        if shouldHover != isHovering {
            isHovering = shouldHover
            applyHoverBackground(isHovering)
        }
    }

    // MARK: - Menu

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String else { return }
        selectItem(title)
        onSelect(title)
    }

    private func truncatedMenuTitle(_ title: String, maxWidth: CGFloat) -> String {
        let font = NSFont.menuFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if title.size(withAttributes: attributes).width <= maxWidth {
            return title
        }

        let ellipsis = "…"
        var lowerBound = 0
        var upperBound = title.count
        var bestFit = ellipsis

        while lowerBound <= upperBound {
            let mid = (lowerBound + upperBound) / 2
            let prefix = String(title.prefix(mid))
            let candidate = prefix + ellipsis
            if candidate.size(withAttributes: attributes).width <= maxWidth {
                bestFit = candidate
                lowerBound = mid + 1
            } else {
                upperBound = mid - 1
            }
        }

        return bestFit
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.minimumWidth = max(bounds.width, 130)
        let maxTitleWidth = max(80, menu.minimumWidth - 34)
        for item in items {
            let menuItem = NSMenuItem(
                title: truncatedMenuTitle(item, maxWidth: maxTitleWidth),
                action: #selector(menuItemSelected(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item
            menuItem.toolTip = item
            if item == selectedTitle {
                menuItem.state = .on
            }
            menu.addItem(menuItem)
        }
        let baseY = bounds.maxY + 4
        let adjustedY = isFlipped ? baseY + menuVerticalOffset : baseY - menuVerticalOffset
        let point = NSPoint(x: 0, y: adjustedY)
        menu.popUp(positioning: nil, at: point, in: self)
    }
}

// MARK: - Source connections popover

final class SourceConnectionsPopoverController: NSViewController {

    private let connections: [Connection]
    private let queryDataSources: [NotebookDataController.QueryDataSource]
    private let onSelect: (Connection) -> Void
    private let onSelectQuerySource: ((NotebookDataController.QueryDataSource) -> Void)?

    init(
        connections: [Connection],
        queryDataSources: [NotebookDataController.QueryDataSource] = [],
        onSelect: @escaping (Connection) -> Void,
        onSelectQuerySource: ((NotebookDataController.QueryDataSource) -> Void)? = nil
    ) {
        self.connections = connections
        self.queryDataSources = queryDataSources
        self.onSelect = onSelect
        self.onSelectQuerySource = onSelectQuerySource
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        if !queryDataSources.isEmpty {
            let header = makeSectionHeader("QUERY OUTPUTS")
            stack.addArrangedSubview(header)
            NSLayoutConstraint.activate([
                header.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 3),
                header.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
            ])

            for source in queryDataSources {
                let item = QuerySourceMenuItem(outputName: source.outputName) { [weak self] in
                    self?.onSelectQuerySource?(source)
                }
                item.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(item)
                NSLayoutConstraint.activate([
                    item.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6),
                    item.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
                ])
            }

        }

        if !connections.isEmpty {
            if !queryDataSources.isEmpty {
                let header = makeSectionHeader("CONNECTIONS")
                stack.addArrangedSubview(header)
                NSLayoutConstraint.activate([
                    header.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 3),
                    header.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
                ])
            }

            for connection in connections {
                let item = ConnectionMenuItem(connection: connection) { [weak self] in
                    self?.onSelect(connection)
                }
                item.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(item)
                NSLayoutConstraint.activate([
                    item.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6),
                    item.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
                ])
            }
        }

        stack.widthAnchor.constraint(equalToConstant: 220).isActive = true
        self.view = stack
    }

    private func makeSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -2),
        ])
        return wrapper
    }
}

// MARK: - Connection menu item with icon

final class ConnectionMenuItem: NSView {

    private let action: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(connection: Connection, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        let iconView = NSImageView()
        let icon = NSImage(named: connection.databaseType.icon)
        icon?.size = NSSize(width: 16, height: 16)
        iconView.image = icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let label = NSTextField(labelWithString: connection.name)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        applyHoverBackground(isHovering)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(isHovering)
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }
}

// MARK: - Query source menu item

final class QuerySourceMenuItem: NSView {

    private let action: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(outputName: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        let iconView = NSImageView()
        let icon = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
        iconView.image = icon
        iconView.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let label = NSTextField(labelWithString: outputName)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        applyHoverBackground(isHovering)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(isHovering)
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }
}

// MARK: - Block menu popover

final class BlockMenuPopoverController: NSViewController {

    private let canMoveUp: Bool
    private let canMoveDown: Bool
    private let onAddAbove: () -> Void
    private let onAddBelow: () -> Void
    private let onMoveUp: () -> Void
    private let onMoveDown: () -> Void
    private let onDuplicate: () -> Void
    private let onCopy: (() -> Void)?
    private let isHiddenInDashboard: Bool
    private let onToggleDashboardVisibility: (() -> Void)?
    private let onDelete: () -> Void

    init(
        canMoveUp: Bool,
        canMoveDown: Bool,
        onAddAbove: @escaping () -> Void,
        onAddBelow: @escaping () -> Void,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onCopy: (() -> Void)? = nil,
        isHiddenInDashboard: Bool = false,
        onToggleDashboardVisibility: (() -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) {
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onAddAbove = onAddAbove
        self.onAddBelow = onAddBelow
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onDuplicate = onDuplicate
        self.onCopy = onCopy
        self.isHiddenInDashboard = isHiddenInDashboard
        self.onToggleDashboardVisibility = onToggleDashboardVisibility
        self.onDelete = onDelete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        addItem(to: stack, title: "Add Above", action: onAddAbove)
        addItem(to: stack, title: "Add Below", action: onAddBelow)
        addItem(to: stack, title: "Move Up", action: onMoveUp, enabled: canMoveUp)
        addItem(to: stack, title: "Move Down", action: onMoveDown, enabled: canMoveDown)
        addDivider(to: stack)
        addItem(to: stack, title: "Duplicate", action: onDuplicate)
        if let onCopy {
            addItem(to: stack, title: "Copy Cell", action: onCopy)
        }
        if let onToggleDashboardVisibility {
            let title = isHiddenInDashboard ? "Show in Dashboard" : "Hide from Dashboard"
            addItem(to: stack, title: title, action: onToggleDashboardVisibility)
        }
        addDivider(to: stack)
        addItem(to: stack, title: "Delete Block", action: onDelete, tint: .systemRed)

        stack.widthAnchor.constraint(equalToConstant: 180).isActive = true
        self.view = stack
    }

    private func addItem(to stack: NSStackView, title: String, action: @escaping () -> Void, enabled: Bool = true, tint: NSColor? = nil) {
        let item = HoverableMenuItem(title: title, tintColor: tint, isEnabled: enabled, action: action)
        item.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(item)
        NSLayoutConstraint.activate([
            item.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6),
            item.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
        ])
    }

    private func addDivider(to stack: NSStackView) {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(divider)

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            divider.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
            divider.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            wrapper.heightAnchor.constraint(equalToConstant: 9),
        ])

        stack.addArrangedSubview(wrapper)
        NSLayoutConstraint.activate([
            wrapper.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6),
            wrapper.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
        ])
    }
}

// MARK: - Hoverable menu item

final class HoverableMenuItem: NSView {

    private let action: () -> Void
    private let isItemEnabled: Bool
    private let label: NSTextField
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    init(title: String, tintColor: NSColor?, isEnabled: Bool, action: @escaping () -> Void) {
        self.action = action
        self.isItemEnabled = isEnabled
        self.label = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        label.font = .systemFont(ofSize: 13)
        label.textColor = tintColor ?? .labelColor
        label.alphaValue = isEnabled ? 1.0 : 0.3
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        applyHoverBackground(isHovering)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(isHovering)
    }

    override func mouseDown(with event: NSEvent) {
        guard isItemEnabled else { return }
        action()
    }
}

// MARK: - Block resize handle

final class BlockResizeHandle: NSView {

    private let onDrag: (CGFloat) -> Void
    private var lastY: CGFloat = 0
    private var isDragging = false
    private let indicator = NSView()
    var onDragStateChanged: ((Bool) -> Void)?

    init(onDrag: @escaping (CGFloat) -> Void) {
        self.onDrag = onDrag
        super.init(frame: .zero)

        wantsLayer = true

        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 1.5
        indicator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        indicator.alphaValue = 0
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 32),
            indicator.heightAnchor.constraint(equalToConstant: 3),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            indicator.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            indicator.animator().alphaValue = 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        lastY = event.locationInWindow.y
        isDragging = true
        onDragStateChanged?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentY = event.locationInWindow.y
        let delta = lastY - currentY
        lastY = currentY
        onDrag(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        onDragStateChanged?(false)
        if !bounds.contains(convert(event.locationInWindow, from: nil)) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                indicator.animator().alphaValue = 0
            }
        }
    }
}

// MARK: - Block width resize handle

final class BlockWidthResizeHandle: NSView {

    private let onDrag: (CGFloat) -> Void
    private var lastX: CGFloat = 0
    private var isDragging = false
    private let indicator = NSView()
    var onDragStateChanged: ((Bool) -> Void)?

    init(onDrag: @escaping (CGFloat) -> Void) {
        self.onDrag = onDrag
        super.init(frame: .zero)

        wantsLayer = true

        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 1.5
        indicator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        indicator.alphaValue = 0
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 3),
            indicator.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        fadeIndicator(to: 1)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        fadeIndicator(to: 0)
    }

    override func mouseDown(with event: NSEvent) {
        lastX = event.locationInWindow.x
        isDragging = true
        onDragStateChanged?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = event.locationInWindow.x - lastX
        lastX = event.locationInWindow.x
        onDrag(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        onDragStateChanged?(false)
        if !bounds.contains(convert(event.locationInWindow, from: nil)) {
            fadeIndicator(to: 0)
        }
    }

    private func fadeIndicator(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            indicator.animator().alphaValue = alpha
        }
    }
}

// MARK: - Block hover tracking view

final class BlockHoverTrackingView: NSView {

    private let onHoverChanged: (Bool) -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    nonisolated(unsafe) private var scrollBoundsObserver: NSObjectProtocol?

    init(onHoverChanged: @escaping (Bool) -> Void) {
        self.onHoverChanged = onHoverChanged
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let observer = scrollBoundsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupScrollBoundsObserver()
        refreshHoverState()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        setupScrollBoundsObserver()
        refreshHoverState()
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
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    private func setupScrollBoundsObserver() {
        if let observer = scrollBoundsObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollBoundsObserver = nil
        }

        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshHoverState()
            }
        }
    }

    private func refreshHoverState() {
        guard let window else {
            setHovered(false)
            return
        }

        let mouseLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(mouseLocation))
    }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        onHoverChanged(hovered)
    }
}
