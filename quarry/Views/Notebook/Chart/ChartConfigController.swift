import AppKit
import SwiftUI

final class ChartConfigController: NSViewController {

    private let viewModel: ChartBlockViewModel
    private let connections: [Connection]
    private weak var dataController: NotebookDataController?
    private static let leftPanelWidth: CGFloat = 250
    private static let centerPanelWidth: CGFloat = 250

    private var splitView: CollapsibleSplitView!
    private var innerSplitView: NSSplitView!
    private var fieldsStackView: NSStackView!
    private var chartHostingView: NSHostingView<AnyView>?
    private var chartHostingContainer: NSView?
    private var snapshotImageView: NSImageView?
    private var cachedSnapshot: NSImage?
    private var freezeDepth = 0
    private var hostingViewConstraints: [NSLayoutConstraint] = []

    private var connectionDropdown: SourceDropdownButton!
    private var connectionSpinner: NSProgressIndicator!
    private var environmentDropdown: StyledDropdown!
    private var environmentLabel: NSTextField!
    private var tableDropdown: StyledDropdown!
    private var tableLabel_: NSTextField!
    private var schemaDropdown: StyledDropdown!
    private var schemaLabel: NSTextField!
    private var tableLabelTopToSchemaConstraint: NSLayoutConstraint?
    private var tableLabelTopToEnvironmentConstraint: NSLayoutConstraint?
    private var tableLabelTopToConnectionConstraint: NSLayoutConstraint?
    private var schemaLabelTopToEnvironmentConstraint: NSLayoutConstraint?
    private var schemaLabelTopToConnectionConstraint: NSLayoutConstraint?
    private var fieldsLabelTopToTableConstraint: NSLayoutConstraint?
    private var fieldsLabelTopToConnectionConstraint: NSLayoutConstraint?
    private var collapseButton: HoverIconButton!
    private var expandButton: HoverIconButton!
    private var columnPanelContainer: NSView!
    private var headerConnectionDropdown: SourceDropdownButton!
    private var headerSpinner: NSProgressIndicator!
    private var headerBar: NSView!
    private var headerHeightConstraint: NSLayoutConstraint!

    private var chartTypeButton: ChartTypePickerButton!
    private var resetButton: HoverIconButton!
    private var axisFieldsStack: NSStackView!

    private var filterContainer: NSStackView!
    private var filterPopover: NSPopover?
    private var connectionPickerView: NSView?
    private var pickerDropdownRef: ConnectionPickerDropdown?

    private var filterLeadingToBarConstraint: NSLayoutConstraint!
    private var filterLeadingToConnectionConstraint: NSLayoutConstraint!
    private var filterLeadingToSpinnerConstraint: NSLayoutConstraint!

    init(viewModel: ChartBlockViewModel, connections: [Connection], dataController: NotebookDataController?) {
        self.viewModel = viewModel
        self.connections = connections
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        setupSplitView()

        if viewModel.config == nil {
            splitView.isHidden = true
            setupConnectionPicker()
        } else {
            if viewModel.schemaResult == nil
                || (viewModel.config?.sourceQueryBlockId == nil && viewModel.availableCollections.isEmpty) {
                viewModel.reloadConfig()
            }
            updateConnectionState()
            refreshConfigUI()
        }

        observeConfig()
        observeSchema()
        observeChartData()
        observeConnecting()
        observeCollections()
        observeSchemas()
        observeEnvironments()
        observeFilters()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChartFreeze),
            name: .notebookChartFreeze,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChartUnfreeze),
            name: .notebookChartUnfreeze,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyInitialDividerPositionsIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyInitialDividerPositionsIfNeeded()
    }

    private var didSetInitialDividerPositions = false

    // MARK: - Connection Picker

    private func setupConnectionPicker() {
        let picker = NSView()
        picker.wantsLayer = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.topAnchor),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let artwork = NotebookArtworkView()
        artwork.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Start by selecting a data source")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center

        let pickerDropdown = ConnectionPickerDropdown(
            connections: connections,
            queryDataSourcesProvider: { [weak self] in
                self?.dataController?.availableQueryDataSources ?? []
            },
            onSelect: { [weak self] connection in
                guard let self else { return }
                Task { await self.viewModel.connectToSource(connection) }
            },
            onSelectQuerySource: { [weak self] source in
                self?.viewModel.connectToQuerySource(blockId: source.blockId, outputName: source.outputName)
            }
        )
        pickerDropdown.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [artwork, title, pickerDropdown])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        picker.addSubview(stack)

        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 80),
            artwork.heightAnchor.constraint(equalToConstant: 80),

            pickerDropdown.widthAnchor.constraint(equalToConstant: 260),

            stack.centerXAnchor.constraint(equalTo: picker.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: picker.centerYAnchor, constant: -20),
        ])

        connectionPickerView = picker
        pickerDropdownRef = pickerDropdown
    }

    private func dismissConnectionPicker() {
        guard let picker = connectionPickerView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            picker.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                picker.removeFromSuperview()
                self?.connectionPickerView = nil
                self?.splitView.isHidden = false
                self?.view.layoutSubtreeIfNeeded()
                self?.applyInitialDividerPositionsIfNeeded()
            }
        }
    }

    private func applyInitialDividerPositionsIfNeeded() {
        guard !didSetInitialDividerPositions else { return }
        guard splitView != nil, innerSplitView != nil else { return }
        guard !splitView.isHidden else { return }
        guard splitView.bounds.width > Self.leftPanelWidth else { return }
        guard innerSplitView.bounds.width > Self.centerPanelWidth else { return }

        splitView.setPosition(Self.leftPanelWidth, ofDividerAt: 0)
        innerSplitView.setPosition(Self.centerPanelWidth, ofDividerAt: 0)
        didSetInitialDividerPositions = true
    }

    private func observeConfig() {
        withObservationTracking {
            _ = self.viewModel.config
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.viewModel.config != nil, self.connectionPickerView != nil {
                    self.dismissConnectionPicker()
                }
                self.updateConnectionState()
                self.refreshConfigUI()
                self.observeConfig()
            }
        }
    }

    private func refreshConfigUI() {
        chartTypeButton?.updateSelection(viewModel.config?.chartType ?? .groupedColumn)
        rebuildTableDropdown()
        updateSchemaVisibility()
        updateEnvironmentVisibility()
        rebuildFieldsList()
        rebuildAxisFields()
        rebuildFilterPills()
    }

    // MARK: - Split View

    private func setupSplitView() {
        splitView = CollapsibleSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.hideDivider = false
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupColumnPanel()
        setupRightSide()
    }

    private func setupRightSide() {
        let rightContainer = NSView()
        rightContainer.wantsLayer = true

        headerBar = NSView()
        headerBar.wantsLayer = true
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(headerBar)

        expandButton = HoverIconButton(symbolName: "rectangle.leftthird.inset.filled", target: self, action: #selector(toggleColumnPanel))
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.isHidden = true
        headerBar.addSubview(expandButton)

        headerConnectionDropdown = SourceDropdownButton(
            connections: connections,
            queryDataSourcesProvider: { [weak self] in
                self?.dataController?.availableQueryDataSources ?? []
            },
            onSelect: { [weak self] connection in
                guard let self else { return }
                Task { await self.viewModel.connectToSource(connection) }
            },
            onSelectQuerySource: { [weak self] source in
                self?.viewModel.connectToQuerySource(blockId: source.blockId, outputName: source.outputName)
            }
        )
        headerConnectionDropdown.translatesAutoresizingMaskIntoConstraints = false
        headerConnectionDropdown.isHidden = true
        headerConnectionDropdown.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        headerConnectionDropdown.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        headerBar.addSubview(headerConnectionDropdown)

        headerSpinner = NSProgressIndicator()
        headerSpinner.style = .spinning
        headerSpinner.controlSize = .mini
        headerSpinner.isHidden = true
        headerSpinner.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerSpinner)

        if let cfg = viewModel.config, !cfg.connectionName.isEmpty {
            if cfg.sourceQueryBlockId != nil {
                headerConnectionDropdown.updateLabel(cfg.connectionName, systemSymbol: "tablecells")
            } else {
                let iconName = DatabaseType(rawValue: cfg.databaseType)?.icon
                headerConnectionDropdown.updateLabel(cfg.connectionName, iconName: iconName)
            }
        }

        setupFilterBar()

        let headerDivider = NSBox()
        headerDivider.boxType = .separator
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerDivider)

        headerHeightConstraint = headerBar.heightAnchor.constraint(equalToConstant: 38)
        headerHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            headerDivider.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            headerDivider.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
        ])

        innerSplitView = NSSplitView()
        innerSplitView.isVertical = true
        innerSplitView.dividerStyle = .thin
        innerSplitView.delegate = self
        innerSplitView.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(innerSplitView)

        filterLeadingToBarConstraint = filterContainer.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 8)
        filterLeadingToConnectionConstraint = filterContainer.leadingAnchor.constraint(equalTo: headerConnectionDropdown.trailingAnchor)
        filterLeadingToSpinnerConstraint = filterContainer.leadingAnchor.constraint(equalTo: headerSpinner.trailingAnchor)
        filterLeadingToBarConstraint.isActive = true
        filterLeadingToConnectionConstraint.isActive = false
        filterLeadingToSpinnerConstraint.isActive = false

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),

            expandButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            expandButton.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 6),
            expandButton.widthAnchor.constraint(equalToConstant: 24),
            expandButton.heightAnchor.constraint(equalToConstant: 24),

            headerConnectionDropdown.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            headerConnectionDropdown.leadingAnchor.constraint(equalTo: expandButton.trailingAnchor, constant: 4),
            headerConnectionDropdown.heightAnchor.constraint(equalToConstant: 24),

            headerSpinner.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            headerSpinner.leadingAnchor.constraint(equalTo: headerConnectionDropdown.trailingAnchor, constant: 6),

            filterContainer.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            filterContainer.trailingAnchor.constraint(lessThanOrEqualTo: headerBar.trailingAnchor, constant: -8),

            innerSplitView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            innerSplitView.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            innerSplitView.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
            innerSplitView.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor),
        ])

        setupAxisConfigPanel()
        setupChartPanel()

        innerSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        innerSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        splitView.addSubview(rightContainer)
        rightContainer.frame = NSRect(x: Self.leftPanelWidth, y: 0, width: 600, height: 380)
    }

    // MARK: - Column Panel (Left)

    private func setupColumnPanel() {
        let container = NSView()
        container.wantsLayer = true

        let hPad: CGFloat = 14

        connectionDropdown = SourceDropdownButton(
            connections: connections,
            queryDataSourcesProvider: { [weak self] in
                self?.dataController?.availableQueryDataSources ?? []
            },
            onSelect: { [weak self] connection in
                guard let self else { return }
                Task { await self.viewModel.connectToSource(connection) }
            },
            onSelectQuerySource: { [weak self] source in
                self?.viewModel.connectToQuerySource(blockId: source.blockId, outputName: source.outputName)
            }
        )
        connectionDropdown.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(connectionDropdown)

        if let cfg = viewModel.config, !cfg.connectionName.isEmpty {
            if cfg.sourceQueryBlockId != nil {
                connectionDropdown.updateLabel(cfg.connectionName, systemSymbol: "tablecells")
            } else {
                let iconName = DatabaseType(rawValue: cfg.databaseType)?.icon
                connectionDropdown.updateLabel(cfg.connectionName, iconName: iconName)
            }
        }

        connectionSpinner = NSProgressIndicator()
        connectionSpinner.style = .spinning
        connectionSpinner.controlSize = .mini
        connectionSpinner.isHidden = true
        connectionSpinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(connectionSpinner)

        collapseButton = HoverIconButton(symbolName: "rectangle.leftthird.inset.filled", target: self, action: #selector(toggleColumnPanel))
        collapseButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(collapseButton)

        // Environment dropdown (Convex deployments)
        environmentLabel = NSTextField(labelWithString: "Environment")
        environmentLabel.font = .systemFont(ofSize: 11, weight: .medium)
        environmentLabel.textColor = .tertiaryLabelColor
        environmentLabel.translatesAutoresizingMaskIntoConstraints = false
        environmentLabel.isHidden = true
        container.addSubview(environmentLabel)

        environmentDropdown = StyledDropdown(placeholder: "Select environment") { [weak self] title in
            Task { await self?.viewModel.switchEnvironment(title) }
        }
        environmentDropdown.translatesAutoresizingMaskIntoConstraints = false
        environmentDropdown.isHidden = true
        container.addSubview(environmentDropdown)
        rebuildEnvironmentDropdown()

        let tableLabel = NSTextField(labelWithString: "Table")
        tableLabel.font = .systemFont(ofSize: 11, weight: .medium)
        tableLabel.textColor = .tertiaryLabelColor
        tableLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tableLabel)
        tableLabel_ = tableLabel

        tableDropdown = StyledDropdown(placeholder: "Select a table") { [weak self] title in
            self?.viewModel.confirmTableSelection(tableName: title)
        }
        tableDropdown.translatesAutoresizingMaskIntoConstraints = false
        tableDropdown.isEnabled = false
        container.addSubview(tableDropdown)
        rebuildTableDropdown()

        schemaLabel = NSTextField(labelWithString: "Schema")
        schemaLabel.font = .systemFont(ofSize: 11, weight: .medium)
        schemaLabel.textColor = .tertiaryLabelColor
        schemaLabel.translatesAutoresizingMaskIntoConstraints = false
        schemaLabel.isHidden = true
        container.addSubview(schemaLabel)

        schemaDropdown = StyledDropdown(placeholder: "Select schema") { [weak self] title in
            Task { await self?.viewModel.loadCollections(schema: title) }
        }
        schemaDropdown.translatesAutoresizingMaskIntoConstraints = false
        schemaDropdown.isHidden = true
        container.addSubview(schemaDropdown)

        let fieldsLabel = NSTextField(labelWithString: "Fields")
        fieldsLabel.font = .systemFont(ofSize: 11, weight: .medium)
        fieldsLabel.textColor = .tertiaryLabelColor
        fieldsLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(fieldsLabel)

        fieldsStackView = NSStackView()
        fieldsStackView.orientation = .vertical
        fieldsStackView.alignment = .leading
        fieldsStackView.spacing = 0
        fieldsStackView.translatesAutoresizingMaskIntoConstraints = false

        let fieldsDocumentView = FlippedContentView()
        fieldsDocumentView.translatesAutoresizingMaskIntoConstraints = false
        fieldsDocumentView.addSubview(fieldsStackView)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.documentView = fieldsDocumentView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -10)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            fieldsStackView.topAnchor.constraint(equalTo: fieldsDocumentView.topAnchor),
            fieldsStackView.leadingAnchor.constraint(equalTo: fieldsDocumentView.leadingAnchor),
            fieldsStackView.trailingAnchor.constraint(equalTo: fieldsDocumentView.trailingAnchor),
            fieldsStackView.bottomAnchor.constraint(equalTo: fieldsDocumentView.bottomAnchor),
            fieldsDocumentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        // Table label constraint: top anchored to schema dropdown, environment dropdown, or connection dropdown
        let tableTopToSchema = tableLabel.topAnchor.constraint(equalTo: schemaDropdown.bottomAnchor, constant: 14)
        tableTopToSchema.isActive = false
        tableLabelTopToSchemaConstraint = tableTopToSchema

        let tableTopToEnvironment = tableLabel.topAnchor.constraint(equalTo: environmentDropdown.bottomAnchor, constant: 14)
        tableTopToEnvironment.isActive = false
        tableLabelTopToEnvironmentConstraint = tableTopToEnvironment

        let tableTopToConnection = tableLabel.topAnchor.constraint(equalTo: connectionDropdown.bottomAnchor, constant: 14)
        tableTopToConnection.isActive = true
        tableLabelTopToConnectionConstraint = tableTopToConnection

        // Schema label constraint: top anchored to environment dropdown or connection dropdown
        let schemaTopToEnvironment = schemaLabel.topAnchor.constraint(equalTo: environmentDropdown.bottomAnchor, constant: 14)
        schemaTopToEnvironment.isActive = false
        schemaLabelTopToEnvironmentConstraint = schemaTopToEnvironment

        let schemaTopToConnection = schemaLabel.topAnchor.constraint(equalTo: connectionDropdown.bottomAnchor, constant: 14)
        schemaTopToConnection.isActive = true
        schemaLabelTopToConnectionConstraint = schemaTopToConnection

        let collapseSafeTrailingPriority = NSLayoutConstraint.Priority(rawValue: 999)
        let envDropdownTrailing = environmentDropdown.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(hPad - 2))
        envDropdownTrailing.priority = collapseSafeTrailingPriority
        let schemaDropdownTrailing = schemaDropdown.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(hPad - 2))
        schemaDropdownTrailing.priority = collapseSafeTrailingPriority
        let tableDropdownTrailing = tableDropdown.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(hPad - 2))
        tableDropdownTrailing.priority = collapseSafeTrailingPriority

        NSLayoutConstraint.activate([
            collapseButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            collapseButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            collapseButton.widthAnchor.constraint(equalToConstant: 24),
            collapseButton.heightAnchor.constraint(equalToConstant: 24),

            connectionDropdown.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            connectionDropdown.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            connectionDropdown.heightAnchor.constraint(equalToConstant: 24),

            connectionSpinner.centerYAnchor.constraint(equalTo: connectionDropdown.centerYAnchor),
            connectionSpinner.leadingAnchor.constraint(equalTo: connectionDropdown.trailingAnchor, constant: 6),

            environmentLabel.topAnchor.constraint(equalTo: connectionDropdown.bottomAnchor, constant: 14),
            environmentLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),

            environmentDropdown.topAnchor.constraint(equalTo: environmentLabel.bottomAnchor, constant: 4),
            environmentDropdown.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad - 2),
            envDropdownTrailing,

            schemaLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),

            schemaDropdown.topAnchor.constraint(equalTo: schemaLabel.bottomAnchor, constant: 4),
            schemaDropdown.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad - 2),
            schemaDropdownTrailing,

            tableLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),

            tableDropdown.topAnchor.constraint(equalTo: tableLabel.bottomAnchor, constant: 4),
            tableDropdown.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad - 2),
            tableDropdownTrailing,

            fieldsLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),

            scrollView.topAnchor.constraint(equalTo: fieldsLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad - 2),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(hPad - 2)),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        let fieldsToTable = fieldsLabel.topAnchor.constraint(equalTo: tableDropdown.bottomAnchor, constant: 10)
        fieldsToTable.isActive = true
        fieldsLabelTopToTableConstraint = fieldsToTable

        let fieldsToConnection = fieldsLabel.topAnchor.constraint(equalTo: connectionDropdown.bottomAnchor, constant: 10)
        fieldsToConnection.isActive = false
        fieldsLabelTopToConnectionConstraint = fieldsToConnection

        rebuildFieldsList()

        splitView.addSubview(container)
        container.frame = NSRect(x: 0, y: 0, width: Self.leftPanelWidth, height: 380)
        columnPanelContainer = container
    }

    private var isColumnPanelCollapsed = false

    @objc private func toggleColumnPanel() {
        isColumnPanelCollapsed.toggle()
        splitView.hideDivider = isColumnPanelCollapsed
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            if self.isColumnPanelCollapsed {
                self.splitView.setPosition(0, ofDividerAt: 0)
            } else {
                self.splitView.setPosition(Self.leftPanelWidth, ofDividerAt: 0)
            }
        }
        splitView.needsDisplay = true
        expandButton.isHidden = !isColumnPanelCollapsed
        headerConnectionDropdown.isHidden = !isColumnPanelCollapsed
        updateConnectionState()
        updateFilterLeadingConstraint()
    }

    private func updateSchemaVisibility() {
        let schemas = viewModel.availableSchemas
        let hasSchemas = !schemas.isEmpty

        schemaLabel.isHidden = !hasSchemas
        schemaDropdown.isHidden = !hasSchemas

        if hasSchemas {
            let items = schemas.map(\.name)
            schemaDropdown.setItems(items)
            if let selected = viewModel.selectedPickerSchema {
                schemaDropdown.selectItem(selected)
            }
        }

        updateColumnPanelConstraints()
    }

    private func updateEnvironmentVisibility() {
        let environments = viewModel.availableEnvironments
        let hasEnvironments = !environments.isEmpty

        environmentLabel.isHidden = !hasEnvironments
        environmentDropdown.isHidden = !hasEnvironments

        if hasEnvironments {
            environmentDropdown.setItems(environments)
            if let selected = viewModel.selectedEnvironment {
                environmentDropdown.selectItem(selected)
            }
        }

        updateColumnPanelConstraints()
    }

    private func rebuildEnvironmentDropdown() {
        let environments = viewModel.availableEnvironments
        environmentDropdown.setItems(environments)
        if let selected = viewModel.selectedEnvironment {
            environmentDropdown.selectItem(selected)
        }
        let hasEnvironments = !environments.isEmpty
        environmentLabel.isHidden = !hasEnvironments
        environmentDropdown.isHidden = !hasEnvironments
    }

    private func updateColumnPanelConstraints() {
        let hasEnvironments = !viewModel.availableEnvironments.isEmpty
        let hasSchemas = !viewModel.availableSchemas.isEmpty

        // Deactivate all dynamic constraints
        tableLabelTopToConnectionConstraint?.isActive = false
        tableLabelTopToEnvironmentConstraint?.isActive = false
        tableLabelTopToSchemaConstraint?.isActive = false
        schemaLabelTopToConnectionConstraint?.isActive = false
        schemaLabelTopToEnvironmentConstraint?.isActive = false

        if hasSchemas {
            // Table sits below schema
            tableLabelTopToSchemaConstraint?.isActive = true
            // Schema sits below environment (if present) or connection
            if hasEnvironments {
                schemaLabelTopToEnvironmentConstraint?.isActive = true
            } else {
                schemaLabelTopToConnectionConstraint?.isActive = true
            }
        } else if hasEnvironments {
            // No schema, table sits below environment
            tableLabelTopToEnvironmentConstraint?.isActive = true
        } else {
            // No schema, no environment, table sits below connection
            tableLabelTopToConnectionConstraint?.isActive = true
        }
    }

    // MARK: - Axis Config Panel (Center)

    private func setupAxisConfigPanel() {
        let container = NSView()
        container.wantsLayer = true

        let hPad: CGFloat = 14
        let collapseSafeTrailingPriority = NSLayoutConstraint.Priority(rawValue: 999)

        chartTypeButton = ChartTypePickerButton(
            initialType: viewModel.config?.chartType ?? .groupedColumn
        ) { [weak self] type in
            self?.viewModel.setChartType(type)
            self?.rebuildAxisFields()
        }
        chartTypeButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chartTypeButton)

        resetButton = HoverIconButton(symbolName: "arrow.counterclockwise", target: self, action: #selector(clearFields))
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.toolTip = "Clear fields"
        container.addSubview(resetButton)

        axisFieldsStack = NSStackView()
        axisFieldsStack.orientation = .vertical
        axisFieldsStack.alignment = .leading
        axisFieldsStack.spacing = 14
        axisFieldsStack.translatesAutoresizingMaskIntoConstraints = false

        let axisDocumentView = FlippedContentView()
        axisDocumentView.translatesAutoresizingMaskIntoConstraints = false
        axisDocumentView.addSubview(axisFieldsStack)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.documentView = axisDocumentView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -10)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        let resetTrailing = resetButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(hPad - 2))
        resetTrailing.priority = collapseSafeTrailingPriority

        NSLayoutConstraint.activate([
            chartTypeButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            chartTypeButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad - 2),

            resetButton.centerYAnchor.constraint(equalTo: chartTypeButton.centerYAnchor),
            resetTrailing,
            resetButton.widthAnchor.constraint(equalToConstant: 24),
            resetButton.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: chartTypeButton.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad - 2),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(hPad - 2)),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            axisFieldsStack.topAnchor.constraint(equalTo: axisDocumentView.topAnchor),
            axisFieldsStack.leadingAnchor.constraint(equalTo: axisDocumentView.leadingAnchor),
            axisFieldsStack.trailingAnchor.constraint(equalTo: axisDocumentView.trailingAnchor),
            axisFieldsStack.bottomAnchor.constraint(equalTo: axisDocumentView.bottomAnchor),
            axisDocumentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        rebuildAxisFields()

        innerSplitView.addSubview(container)
        container.frame = NSRect(x: 0, y: 0, width: Self.centerPanelWidth, height: 380)
    }

    @objc private func clearFields() {
        viewModel.resetFields()
        rebuildAxisFields()
    }

    private func rebuildTableDropdown() {
        let collections = viewModel.availableCollections
        tableDropdown.setItems(collections.map(\.name))
        tableDropdown.isEnabled = !collections.isEmpty
        if let cfg = viewModel.config, !cfg.tableName.isEmpty {
            tableDropdown.selectItem(cfg.tableName)
        }
    }

    // MARK: - Chart Panel (Right)

    private func setupChartPanel() {
        let container = NSView()
        container.wantsLayer = true

        let chartView = ChartPreviewView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: AnyView(chartView))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        chartHostingView = hosting
        chartHostingContainer = container

        let constraints = [
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        hostingViewConstraints = constraints

        innerSplitView.addSubview(container)
        container.frame = NSRect(x: Self.centerPanelWidth, y: 0, width: 400, height: 380)

        setupSnapshotOverlay()
    }

    // MARK: - Chart Snapshot

    private func setupSnapshotOverlay() {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.isHidden = true
        imageView.wantsLayer = true
        snapshotImageView = imageView

        guard let hosting = chartHostingView, let container = hosting.superview else { return }
        container.addSubview(imageView, positioned: .above, relativeTo: hosting)
        imageView.frame = hosting.frame
        imageView.autoresizingMask = [.width, .height]
    }

    private func cacheChartSnapshot() {
        guard let hosting = chartHostingView,
              hosting.bounds.width > 0,
              hosting.bounds.height > 0 else { return }
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        hosting.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        cachedSnapshot = image
    }

    private func freezeChart() {
        freezeDepth += 1
        guard freezeDepth == 1,
              !viewModel.chartData.isEmpty,
              !viewModel.isLoadingChart,
              viewModel.chartError == nil,
              let imageView = snapshotImageView,
              let snapshot = cachedSnapshot else { return }
        imageView.image = snapshot
        imageView.frame = chartHostingView?.frame ?? imageView.frame
        imageView.isHidden = false
        NSLayoutConstraint.deactivate(hostingViewConstraints)
        chartHostingView?.removeFromSuperview()
    }

    private func unfreezeChart() {
        freezeDepth = max(0, freezeDepth - 1)
        guard freezeDepth == 0 else { return }
        if let hosting = chartHostingView, let container = chartHostingContainer, hosting.superview == nil {
            container.addSubview(hosting, positioned: .below, relativeTo: snapshotImageView)
            NSLayoutConstraint.activate(hostingViewConstraints)
        }
        snapshotImageView?.isHidden = true
        snapshotImageView?.image = nil
    }

    @objc private func handleChartFreeze(_ notification: Notification) {
        guard notification.object as? NSWindow == view.window else { return }
        freezeChart()
    }

    @objc private func handleChartUnfreeze(_ notification: Notification) {
        guard notification.object as? NSWindow == view.window else { return }
        unfreezeChart()
    }

    // MARK: - Filter Bar

    private func setupFilterBar() {
        filterContainer = NSStackView()
        filterContainer.orientation = .horizontal
        filterContainer.alignment = .centerY
        filterContainer.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(filterContainer)

        rebuildFilterPills()
    }

    private func rebuildFilterPills() {
        guard filterContainer != nil else { return }

        for view in filterContainer.arrangedSubviews {
            filterContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let isQuerySource = viewModel.config?.sourceQueryBlockId != nil
        let hasConnection = viewModel.config.map { !$0.connectionKeychainId.isEmpty } ?? false
        filterContainer.isHidden = isQuerySource || !hasConnection

        guard !filterContainer.isHidden else { return }

        let filters = viewModel.config?.filters ?? []

        let addButton = FilterChipView(
            icon: "line.3.horizontal.decrease",
            title: filters.isEmpty ? "Add filter" : "\(filters.count)",
            style: filters.isEmpty ? .plain : .active
        ) { [weak self] in
            guard let self, let button = self.filterContainer.arrangedSubviews.first else { return }
            self.showFilterPopover(relativeTo: button, editing: nil)
        }
        addButton.translatesAutoresizingMaskIntoConstraints = false
        filterContainer.addArrangedSubview(addButton)

        for filter in filters {
            let isValid = viewModel.isFilterFieldValid(filter)
            let pill = FilterPillView(filter: filter, isValid: isValid, onEdit: { [weak self] pillView in
                self?.showFilterPopover(relativeTo: pillView, editing: filter)
            }, onRemove: { [weak self] in
                self?.viewModel.removeFilter(id: filter.id)
            })
            pill.translatesAutoresizingMaskIntoConstraints = false
            filterContainer.addArrangedSubview(pill)
        }

        if !filters.isEmpty {
            let plusButton = FilterChipView(icon: "plus", title: nil, style: .plain) { [weak self] in
                guard let self, let button = self.filterContainer.arrangedSubviews.last else { return }
                self.showFilterPopover(relativeTo: button, editing: nil)
            }
            plusButton.translatesAutoresizingMaskIntoConstraints = false
            filterContainer.addArrangedSubview(plusButton)
        }
    }

    private func showFilterPopover(relativeTo anchorView: NSView, editing existingFilter: ChartFilterCondition?) {
        filterPopover?.performClose(nil)
        filterPopover = nil

        let columns = viewModel.schemaResult?.columns ?? []
        guard !columns.isEmpty else { return }

        let popoverVC = ChartFilterPopoverController(
            columns: columns,
            existingFilter: existingFilter
        ) { [weak self] filter in
            self?.filterPopover?.performClose(nil)
            self?.filterPopover = nil
            if existingFilter != nil {
                self?.viewModel.updateFilter(filter)
            } else {
                self?.viewModel.addFilter(filter)
            }
        }

        let pop = NSPopover()
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        filterPopover = pop
    }

    // MARK: - Observation

    private func observeFilters() {
        withObservationTracking {
            _ = self.viewModel.config?.filters.count
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildFilterPills()
                self.observeFilters()
            }
        }
    }

    private func observeSchema() {
        withObservationTracking {
            _ = self.viewModel.schemaResult
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildFieldsList()
                self.rebuildAxisFields()
                self.rebuildFilterPills()
                self.observeSchema()
            }
        }
    }

    private func observeConnecting() {
        withObservationTracking {
            _ = self.viewModel.isConnecting
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateConnectionState()
                self.observeConnecting()
            }
        }
    }

    private func updateConnectionState() {
        let connecting = viewModel.isConnecting
        let isQuerySource = viewModel.config?.sourceQueryBlockId != nil
        connectionDropdown.isEnabled = !connecting

        connectionSpinner.isHidden = !connecting || isColumnPanelCollapsed
        headerSpinner.isHidden = !connecting || !isColumnPanelCollapsed

        for spinner in [connectionSpinner!, headerSpinner!] {
            if !spinner.isHidden {
                spinner.startAnimation(nil)
            } else {
                spinner.stopAnimation(nil)
            }
        }

        if let cfg = viewModel.config, !cfg.connectionName.isEmpty {
            if isQuerySource {
                connectionDropdown.updateLabel(cfg.connectionName, systemSymbol: "tablecells")
                headerConnectionDropdown.updateLabel(cfg.connectionName, systemSymbol: "tablecells")
            } else {
                let iconName = DatabaseType(rawValue: cfg.databaseType)?.icon
                connectionDropdown.updateLabel(cfg.connectionName, iconName: iconName)
                headerConnectionDropdown.updateLabel(cfg.connectionName, iconName: iconName)
            }
            let iconName = isQuerySource ? nil : DatabaseType(rawValue: cfg.databaseType)?.icon
            pickerDropdownRef?.setConnecting(connecting, name: cfg.connectionName, iconName: iconName)
        } else {
            pickerDropdownRef?.setConnecting(connecting)
        }

        tableDropdown.isHidden = isQuerySource
        tableLabel_?.isHidden = isQuerySource
        fieldsLabelTopToTableConstraint?.isActive = !isQuerySource
        fieldsLabelTopToConnectionConstraint?.isActive = isQuerySource
        if isQuerySource {
            schemaDropdown.isHidden = true
            schemaLabel.isHidden = true
            environmentDropdown.isHidden = true
            environmentLabel.isHidden = true
        }

        updateFilterLeadingConstraint()
    }

    private func updateFilterLeadingConstraint() {
        if isColumnPanelCollapsed {
            filterLeadingToBarConstraint.isActive = false
            filterLeadingToConnectionConstraint.isActive = !viewModel.isConnecting
            filterLeadingToSpinnerConstraint.isActive = viewModel.isConnecting
            return
        }

        filterLeadingToConnectionConstraint.isActive = false
        filterLeadingToSpinnerConstraint.isActive = false
        filterLeadingToBarConstraint.isActive = true
    }

    private func observeCollections() {
        withObservationTracking {
            _ = self.viewModel.availableCollections.map(\.name)
            _ = self.viewModel.config?.tableName
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildTableDropdown()
                self.observeCollections()
            }
        }
    }

    private func observeSchemas() {
        withObservationTracking {
            _ = self.viewModel.availableSchemas.map(\.name)
            _ = self.viewModel.selectedPickerSchema
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateSchemaVisibility()
                self.observeSchemas()
            }
        }
    }

    private func observeEnvironments() {
        withObservationTracking {
            _ = self.viewModel.availableEnvironments
            _ = self.viewModel.selectedEnvironment
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateEnvironmentVisibility()
                self.observeEnvironments()
            }
        }
    }

    private func observeChartData() {
        withObservationTracking {
            _ = self.viewModel.chartData.count
            _ = self.viewModel.isLoadingChart
            _ = self.viewModel.chartError
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.viewModel.isLoadingChart,
                   self.viewModel.chartError == nil,
                   !self.viewModel.chartData.isEmpty {
                    self.scheduleSnapshotCache()
                } else {
                    self.cachedSnapshot = nil
                }
                self.observeChartData()
            }
        }
    }

    private func scheduleSnapshotCache() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.cacheChartSnapshot()
        }
    }

    private func rebuildAxisFields() {
        guard axisFieldsStack != nil else { return }

        for subview in axisFieldsStack.arrangedSubviews {
            axisFieldsStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let chartType = viewModel.config?.chartType ?? .groupedColumn
        let definitions = chartType.fieldDefinitions
        let sorted = definitions.sorted { lhs, rhs in
            (lhs.cardinality == .single ? 0 : 1) < (rhs.cardinality == .single ? 0 : 1)
        }

        for definition in sorted {
            let group = NSStackView()
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = 4
            group.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: definition.label)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .tertiaryLabelColor
            group.addArrangedSubview(label)

            let selectedColumns = viewModel.config?.fields[definition.key] ?? []
            let available = columnsForFilter(definition.columnFilter)
            let showAgg = definition.isMeasureField

            switch definition.cardinality {
            case .single:
                let dropdown = makeColumnDropdown(placeholder: "Select column", items: available) { [weak self] title in
                    self?.viewModel.setFieldColumn(key: definition.key, column: title)
                    self?.rebuildAxisFields()
                }
                if let selected = selectedColumns.first {
                    dropdown.selectItem(selected)
                }
                if showAgg, let selected = selectedColumns.first {
                    let aggDropdown = makeAggregationDropdown(forField: definition.key, column: selected)
                    addRowWithAggregation(mainView: dropdown, aggDropdown: aggDropdown, to: group)
                } else {
                    addFullWidthView(dropdown, to: group)
                }

            case .multiple:
                for column in selectedColumns {
                    let chip = FieldColumnChipView(
                        title: column,
                        availableItems: available,
                        onChange: { [weak self] newColumn in
                            self?.viewModel.removeFieldColumn(key: definition.key, column: column)
                            self?.viewModel.addFieldColumn(key: definition.key, column: newColumn)
                            self?.rebuildAxisFields()
                        }
                    )
                    chip.translatesAutoresizingMaskIntoConstraints = false
                    if showAgg {
                        let aggDropdown = makeAggregationDropdown(forField: definition.key, column: column)
                        addRowWithAggregation(mainView: chip, aggDropdown: aggDropdown, to: group)
                    } else {
                        addFullWidthView(chip, to: group)
                    }
                }

                let remaining = available.filter { !selectedColumns.contains($0) }
                if !remaining.isEmpty {
                    let addDropdown = makeColumnDropdown(placeholder: "Add column", items: remaining) { [weak self] title in
                        self?.viewModel.addFieldColumn(key: definition.key, column: title)
                        self?.rebuildAxisFields()
                    }
                    addFullWidthView(addDropdown, to: group)
                }
            }

            axisFieldsStack.addArrangedSubview(group)
            pinEdges(of: group, to: axisFieldsStack)
        }
    }

    private func makeColumnDropdown(placeholder: String, items: [String], onSelect: @escaping (String) -> Void) -> StyledDropdown {
        let dropdown = StyledDropdown(placeholder: placeholder, onSelect: onSelect)
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.setItems(items)
        return dropdown
    }

    private func addFullWidthView(_ child: NSView, to parent: NSStackView) {
        parent.addArrangedSubview(child)
        pinEdges(of: child, to: parent)
    }

    private func addRowWithAggregation(mainView: NSView, aggDropdown: StyledDropdown, to parent: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(mainView)
        row.addArrangedSubview(aggDropdown)
        parent.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            aggDropdown.widthAnchor.constraint(equalToConstant: 90),
        ])
    }

    private func pinEdges(of child: NSView, to parent: NSStackView) {
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }

    private func makeAggregationDropdown(forField fieldKey: String, column: String) -> StyledDropdown {
        let dataType = viewModel.schemaResult?.columns.first(where: { $0.columnName == column })?.dataType ?? ""
        let chartType = viewModel.config?.chartType
        let options = AggregationFunction.availableAggregations(for: dataType, chartType: chartType)
        let current = viewModel.resolvedAggregation(forField: fieldKey, column: column)

        let dropdown = StyledDropdown(placeholder: "Aggregation") { [weak self] title in
            guard let agg = options.first(where: { $0.displayName == title }) else { return }
            self?.viewModel.setAggregation(agg, forField: fieldKey, column: column)
            self?.rebuildAxisFields()
        }
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.setItems(options.map(\.displayName))
        dropdown.selectItem(current.displayName)
        return dropdown
    }

    private func columnsForFilter(_ filter: ChartFieldDefinition.ColumnFilter) -> [String] {
        guard let schema = viewModel.schemaResult else { return [] }
        switch filter {
        case .all:
            return schema.columns.map(\.columnName)
        case .numeric:
            return viewModel.measureColumns.map(\.columnName)
        }
    }

    private var displayedColumns: [DatabaseSchemaInfo] {
        viewModel.schemaResult?.columns ?? []
    }

    private func iconName(for column: DatabaseSchemaInfo) -> String {
        if viewModel.isNumericColumn(column) {
            return "numbers.rectangle"
        }
        let type = column.dataType.lowercased()
        if type.contains("date") || type.contains("time") || type.contains("timestamp") {
            return "calendar"
        }
        if type.contains("bool") {
            return "checkmark.circle"
        }
        return "textformat"
    }

    private func rebuildFieldsList() {
        guard fieldsStackView != nil else { return }

        for subview in fieldsStackView.arrangedSubviews {
            fieldsStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for info in displayedColumns {
            let row = FieldRowCell()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.configure(name: info.columnName, iconName: iconName(for: info), dataType: info.dataType)
            fieldsStackView.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: fieldsStackView.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: fieldsStackView.trailingAnchor),
                row.heightAnchor.constraint(equalToConstant: 30),
            ])
        }
    }
}

// MARK: - NSSplitViewDelegate

extension ChartConfigController: NSSplitViewDelegate {
    func splitView(_ sv: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if sv === splitView {
            return isColumnPanelCollapsed ? 0 : Self.leftPanelWidth
        }
        if sv === innerSplitView {
            return Self.centerPanelWidth
        }
        return proposedMinimumPosition
    }

    func splitView(_ sv: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        sv === splitView && subview === columnPanelContainer
    }
}

// MARK: - FieldColumnChipView

final class FieldColumnChipView: NSView {

    private let currentTitle: String
    private let availableItems: [String]
    private let onChange: (String) -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(title: String, availableItems: [String], onChange: @escaping (String) -> Void) {
        self.currentTitle = title
        self.availableItems = availableItems
        self.onChange = onChange
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: .appAppearanceDidChange, object: nil)
        updateColors()

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),

            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -4),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appearanceChanged() {
        updateColors()
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
        guard let window else { return }
        let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = bounds.contains(loc)
        if isHovering != inside {
            isHovering = inside
            applyHoverBackground(isHovering)
        }
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
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.minimumWidth = max(bounds.width, 130)
        for item in availableItems {
            let menuItem = NSMenuItem(
                title: item,
                action: #selector(menuItemSelected(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item
            if item == currentTitle {
                menuItem.state = .on
            }
            menu.addItem(menuItem)
        }
        let point = NSPoint(x: 0, y: bounds.maxY + 4)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String, title != currentTitle else { return }
        onChange(title)
    }

    private func updateColors() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            layer?.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.1).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
