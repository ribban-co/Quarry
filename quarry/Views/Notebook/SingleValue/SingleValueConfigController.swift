import AppKit

final class SingleValueConfigController: NSViewController {

    private let viewModel: SingleValueBlockViewModel
    private let connections: [Connection]
    private weak var dataController: NotebookDataController?

    private var connectionPickerView: NSView?
    private var pickerDropdownRef: ConnectionPickerDropdown?
    private var singleValueDisplayView: SingleValueDisplayView?

    init(viewModel: SingleValueBlockViewModel, connections: [Connection], dataController: NotebookDataController?) {
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

        if viewModel.config != nil {
            setupSingleValueDisplay()
        }

        observeConfig()
    }

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
            Task { @MainActor [weak self] in
                guard let self, let picker = self.connectionPickerView else { return }
                picker.removeFromSuperview()
                self.connectionPickerView = nil
                self.setupSingleValueDisplay()
            }
        }
    }

    // MARK: - Single Value Display

    private func setupSingleValueDisplay() {
        guard singleValueDisplayView == nil else { return }

        let displayView = SingleValueDisplayView(viewModel: viewModel)
        displayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(displayView)
        singleValueDisplayView = displayView

        NSLayoutConstraint.activate([
            displayView.topAnchor.constraint(equalTo: view.topAnchor),
            displayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            displayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            displayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Observation

    private func observeConfig() {
        withObservationTracking {
            _ = self.viewModel.config
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.viewModel.config != nil, self.connectionPickerView != nil {
                    self.dismissConnectionPicker()
                }
                self.observeConfig()
            }
        }
    }
}

// MARK: - Config Popover Controller

final class SingleValueConfigPopoverController: NSViewController {

    private let viewModel: SingleValueBlockViewModel
    private let connections: [Connection]
    private weak var dataController: NotebookDataController?
    private var stack: NSStackView!
    private var rebuildScheduled = false

    init(viewModel: SingleValueBlockViewModel, connections: [Connection], dataController: NotebookDataController?) {
        self.viewModel = viewModel
        self.connections = connections
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false

        stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 260),
        ])

        rebuildRows()
        observeViewModel()

        self.view = container
    }

    private func rebuildRows() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        addConnectionRow(to: stack)

        if !viewModel.availableEnvironments.isEmpty {
            addEnvironmentRow(to: stack)
        }

        if !viewModel.availableSchemas.isEmpty {
            addSchemaRow(to: stack)
        }

        addTableRow(to: stack)
        addColumnRow(to: stack)
        addAggregationRow(to: stack)
    }

    private func observeViewModel() {
        withObservationTracking {
            _ = self.viewModel.config
            _ = self.viewModel.availableCollections
            _ = self.viewModel.availableSchemas
            _ = self.viewModel.availableEnvironments
            _ = self.viewModel.selectedPickerSchema
            _ = self.viewModel.selectedEnvironment
            _ = self.viewModel.schemaResult
            _ = self.viewModel.isConnecting
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scheduleRebuild()
                self.observeViewModel()
            }
        }
    }

    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.rebuildScheduled = false
            self.rebuildRows()
        }
    }

    // MARK: - Rows

    private func addConnectionRow(to stack: NSStackView) {
        let label = sectionLabel("Data Source")
        let dropdown = SourceDropdownButton(
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
        dropdown.translatesAutoresizingMaskIntoConstraints = false

        if let cfg = viewModel.config, !cfg.connectionName.isEmpty {
            if let sourceBlockId = cfg.sourceQueryBlockId, !sourceBlockId.isEmpty {
                dropdown.updateLabel(cfg.connectionName, systemSymbol: "doc.text")
            } else {
                let iconName = DatabaseType(rawValue: cfg.databaseType)?.icon
                dropdown.updateLabel(cfg.connectionName, iconName: iconName)
            }
        } else {
            dropdown.updateLabel("Select data source")
        }

        let controlRow = NSStackView()
        controlRow.orientation = .horizontal
        controlRow.alignment = .centerY
        controlRow.spacing = 6
        controlRow.translatesAutoresizingMaskIntoConstraints = false
        controlRow.addArrangedSubview(dropdown)

        if viewModel.isConnecting {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .mini
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.startAnimation(nil)
            controlRow.addArrangedSubview(spinner)
        }

        if viewModel.config != nil {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            controlRow.addArrangedSubview(spacer)

            let resetButton = BlockActionButton(
                iconName: "arrow.counterclockwise",
                size: 10,
                action: { [weak self] _ in self?.viewModel.resetConfig() }
            )
            resetButton.translatesAutoresizingMaskIntoConstraints = false
            resetButton.installCustomTooltip("Reset", position: .top, delay: 0)
            controlRow.addArrangedSubview(resetButton)
            NSLayoutConstraint.activate([
                resetButton.widthAnchor.constraint(equalToConstant: 24),
                resetButton.heightAnchor.constraint(equalToConstant: 24),
            ])
        }

        let row = makeRow(label: label, control: controlRow, fillWidth: true)
        stack.addArrangedSubview(row)
        pinWidth(row, to: stack)
    }


    private func addSchemaRow(to stack: NSStackView) {
        let label = sectionLabel("Schema")
        let dropdown = StyledDropdown(placeholder: "Select schema") { [weak self] schema in
            guard let self else { return }
            Task { await self.viewModel.loadCollections(schema: schema) }
        }
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.setItems(viewModel.availableSchemas.map(\.name))
        if let selected = viewModel.selectedPickerSchema {
            dropdown.selectItem(selected)
        }

        let row = makeRow(label: label, control: dropdown)
        stack.addArrangedSubview(row)
        pinWidth(row, to: stack)
    }

    private func addEnvironmentRow(to stack: NSStackView) {
        let label = sectionLabel("Environment")
        let dropdown = StyledDropdown(placeholder: "Select environment") { [weak self] env in
            guard let self else { return }
            Task { await self.viewModel.switchEnvironment(env) }
        }
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.setItems(viewModel.availableEnvironments)
        if let selected = viewModel.selectedEnvironment {
            dropdown.selectItem(selected)
        }

        let row = makeRow(label: label, control: dropdown)
        stack.addArrangedSubview(row)
        pinWidth(row, to: stack)
    }

    private func addTableRow(to stack: NSStackView) {
        let label = sectionLabel("Table")
        let dropdown = StyledDropdown(placeholder: "Select table") { [weak self] table in
            self?.viewModel.confirmTableSelection(tableName: table)
        }
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.setItems(viewModel.availableCollections.map(\.name))
        if let tableName = viewModel.config?.tableName, !tableName.isEmpty {
            dropdown.selectItem(tableName)
        }

        let row = makeRow(label: label, control: dropdown)
        stack.addArrangedSubview(row)
        pinWidth(row, to: stack)
    }

    private func addColumnRow(to stack: NSStackView) {
        let label = sectionLabel("Column")
        let columns = viewModel.schemaResult?.columns.map(\.columnName) ?? []
        let dropdown = StyledDropdown(placeholder: "Select column") { [weak self] column in
            self?.viewModel.setColumn(column)
        }
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.setItems(columns)
        if let column = viewModel.config?.column {
            dropdown.selectItem(column)
        }

        let row = makeRow(label: label, control: dropdown)
        stack.addArrangedSubview(row)
        pinWidth(row, to: stack)
    }

    private func addAggregationRow(to stack: NSStackView) {
        let label = sectionLabel("Aggregation")
        let allAggs = AggregationFunction.allCases

        let selectedColumn = viewModel.config?.column
        let dataType = viewModel.schemaResult?.columns.first(where: { $0.columnName == selectedColumn })?.dataType

        let availableAggs: [AggregationFunction]
        if let dataType {
            availableAggs = AggregationFunction.availableAggregations(for: dataType)
        } else {
            availableAggs = allAggs
        }

        let dropdown = StyledDropdown(placeholder: "Select aggregation") { [weak self] aggName in
            guard let agg = AggregationFunction.allCases.first(where: { $0.displayName == aggName }) else { return }
            self?.viewModel.setAggregation(agg)
        }
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.setItems(availableAggs.map(\.displayName))

        if let currentAgg = viewModel.config?.aggregation {
            dropdown.selectItem(currentAgg.displayName)
        }

        let row = makeRow(label: label, control: dropdown)
        stack.addArrangedSubview(row)
        pinWidth(row, to: stack)
    }

    // MARK: - Helpers

    private func makeRow(label: NSView, control: NSView, fillWidth: Bool = true) -> NSStackView {
        let row = NSStackView(views: [label, control])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        row.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 0)
        control.translatesAutoresizingMaskIntoConstraints = false
        if fillWidth {
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
                control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            ])
        }
        return row
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func pinWidth(_ subview: NSView, to stack: NSStackView) {
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 12),
            subview.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12),
        ])
    }
}

// MARK: - Single Value Display View (AppKit)

final class SingleValueDisplayView: NSView, NSTextFieldDelegate {

    private let viewModel: SingleValueBlockViewModel
    private let isLabelEditable: Bool
    private var fallbackLabel: String?

    private let stackView = NSStackView()
    private let spinner = NSProgressIndicator()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let labelField = NSTextField(string: "")
    private var observationGeneration = 0

    init(viewModel: SingleValueBlockViewModel, fallbackLabel: String? = nil, isLabelEditable: Bool = true) {
        self.viewModel = viewModel
        self.fallbackLabel = fallbackLabel
        self.isLabelEditable = isLabelEditable
        super.init(frame: .zero)
        setupView()
        startObservingViewModel()
        updateContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupView() {
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(spinner)

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.alignment = .center
        errorLabel.maximumNumberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(errorLabel)

        valueLabel.font = Self.roundedSystemFont(size: 48, weight: .bold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(valueLabel)

        labelField.placeholderString = "Add label"
        labelField.font = .systemFont(ofSize: 13)
        labelField.textColor = .secondaryLabelColor
        labelField.alignment = .center
        labelField.isBezeled = false
        labelField.isBordered = false
        labelField.drawsBackground = false
        labelField.focusRingType = .none
        labelField.isEditable = isLabelEditable
        labelField.isSelectable = isLabelEditable
        labelField.delegate = self
        labelField.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(labelField)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            labelField.widthAnchor.constraint(equalToConstant: 200),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observationGeneration += 1
        if window != nil {
            startObservingViewModel()
            updateContent()
        }
    }

    private func startObservingViewModel() {
        observationGeneration += 1
        observeViewModel(generation: observationGeneration)
    }

    private func observeViewModel(generation: Int) {
        withObservationTracking {
            _ = viewModel.isLoadingSingleValue
            _ = viewModel.singleValueError
            _ = viewModel.singleValueResult
            _ = viewModel.config?.label
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation else { return }
                self.updateContent()
                self.observeViewModel(generation: generation)
            }
        }
    }

    private func updateContent() {
        if viewModel.isLoadingSingleValue {
            spinner.isHidden = false
            spinner.startAnimation(nil)
            errorLabel.isHidden = true
            valueLabel.isHidden = true
            labelField.isHidden = true
            return
        }

        spinner.stopAnimation(nil)
        spinner.isHidden = true

        if let error = viewModel.singleValueError {
            errorLabel.stringValue = error
            errorLabel.isHidden = false
            valueLabel.isHidden = true
            labelField.isHidden = true
            return
        }

        errorLabel.isHidden = true

        if let value = viewModel.singleValueResult {
            valueLabel.stringValue = value.abbreviatedString
            valueLabel.isHidden = false

            labelField.isHidden = false
            syncLabelFromConfigOrFallback()
            return
        }

        valueLabel.isHidden = true
        labelField.isHidden = true
    }

    func updateFallbackLabel(_ label: String?) {
        fallbackLabel = label
        syncLabelFromConfigOrFallback()
    }

    private func syncLabelFromConfigOrFallback() {
        let incoming = (viewModel.config?.label).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackLabel ?? ""
        if incoming != labelField.stringValue {
            labelField.stringValue = incoming
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === labelField else { return }
        viewModel.setLabel(field.stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === labelField else { return }
        viewModel.setLabel(field.stringValue)
    }


    private static func roundedSystemFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return rounded
    }
}
