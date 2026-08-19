import AppKit

final class ChartTablePickerController: NSViewController {

    private let viewModel: ChartBlockViewModel

    private var splitView: NSSplitView!
    private var tableListView: NSOutlineView!
    private var previewTableView: NSTableView!
    private var previewScrollView: NSScrollView!
    private var previewDataSource: PreviewTableDataSource?
    private var schemaPopUp: NSPopUpButton?
    private var useTableButton: NSButton!
    private var cancelButton: NSButton!
    private var headerLabel: NSTextField!
    private var previewHeaderLabel: NSTextField!
    private var previewSpinner: NSProgressIndicator?
    private var emptyPreviewLabel: NSTextField?

    private var selectedTableName: String?

    init(viewModel: ChartBlockViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 560))
        root.wantsLayer = true
        self.view = root
        self.preferredContentSize = NSSize(width: 860, height: 560)

        setupHeader()
        setupSplitView()
        setupFooter()
        observeCollections()
        observePreview()
    }

    // MARK: - Header

    private func setupHeader() {
        headerLabel = NSTextField(labelWithString: "Select table")
        headerLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
        ])

        if !viewModel.availableSchemas.isEmpty {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.font = .systemFont(ofSize: 12)
            popup.removeAllItems()
            for schema in viewModel.availableSchemas {
                popup.addItem(withTitle: schema.name)
            }
            if let selected = viewModel.selectedPickerSchema {
                popup.selectItem(withTitle: selected)
            }
            popup.target = self
            popup.action = #selector(schemaChanged(_:))
            view.addSubview(popup)
            schemaPopUp = popup

            NSLayoutConstraint.activate([
                popup.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
                popup.leadingAnchor.constraint(equalTo: headerLabel.trailingAnchor, constant: 12),
            ])
        }
    }

    @objc private func schemaChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        Task {
            await viewModel.loadCollections(schema: title)
        }
    }

    // MARK: - Split View

    private func setupSplitView() {
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor, constant: 48),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -52),
        ])

        setupTableList()
        setupPreviewPanel()
    }

    // MARK: - Table List (Left Panel)

    private func setupTableList() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TableName"))
        column.title = "Tables"

        tableListView = NSOutlineView()
        tableListView.addTableColumn(column)
        tableListView.outlineTableColumn = column
        tableListView.headerView = nil
        tableListView.rowHeight = 28
        tableListView.delegate = self
        tableListView.dataSource = self
        tableListView.style = .sourceList

        let scrollView = NSScrollView()
        scrollView.documentView = tableListView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        splitView.addSubview(container)
        container.frame = NSRect(x: 0, y: 0, width: 220, height: 400)
    }

    // MARK: - Preview Panel (Right Panel)

    private func setupPreviewPanel() {
        let container = NSView()
        container.wantsLayer = true

        previewHeaderLabel = NSTextField(labelWithString: "Select a table to preview data")
        previewHeaderLabel.font = .systemFont(ofSize: 13, weight: .medium)
        previewHeaderLabel.textColor = .secondaryLabelColor
        previewHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(previewHeaderLabel)

        previewDataSource = PreviewTableDataSource()

        previewTableView = NSTableView()
        previewTableView.usesAlternatingRowBackgroundColors = true
        previewTableView.style = .inset
        previewTableView.rowHeight = 22
        previewTableView.delegate = previewDataSource
        previewTableView.dataSource = previewDataSource

        previewScrollView = NSScrollView()
        previewScrollView.documentView = previewTableView
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = true
        previewScrollView.autohidesScrollers = true
        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(previewScrollView)

        let emptyLabel = NSTextField(labelWithString: "Select a table to preview its data")
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emptyLabel)
        emptyPreviewLabel = emptyLabel

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)
        previewSpinner = spinner

        NSLayoutConstraint.activate([
            previewHeaderLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            previewHeaderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            previewScrollView.topAnchor.constraint(equalTo: previewHeaderLabel.bottomAnchor, constant: 8),
            previewScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            previewScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            previewScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        splitView.addSubview(container)
        container.frame = NSRect(x: 220, y: 0, width: 640, height: 400)

        previewScrollView.isHidden = true
    }

    // MARK: - Footer

    private func setupFooter() {
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        useTableButton = NSButton(title: "Use this table", target: self, action: #selector(useTableTapped))
        useTableButton.bezelStyle = .rounded
        useTableButton.keyEquivalent = "\r"
        useTableButton.isEnabled = false
        useTableButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(useTableButton)

        NSLayoutConstraint.activate([
            useTableButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            useTableButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            cancelButton.trailingAnchor.constraint(equalTo: useTableButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    @objc private func cancelTapped() {
        viewModel.isShowingTablePicker = false
        dismiss(nil)
    }

    @objc private func useTableTapped() {
        guard let tableName = selectedTableName else { return }
        viewModel.confirmTableSelection(tableName: tableName)
        dismiss(nil)
    }

    // MARK: - Observation

    private func observeCollections() {
        withObservationTracking {
            _ = self.viewModel.availableCollections.count
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tableListView.reloadData()
                self.observeCollections()
            }
        }
    }

    private func observePreview() {
        withObservationTracking {
            _ = self.viewModel.previewResult
            _ = self.viewModel.isLoadingPreview
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updatePreview()
                self.observePreview()
            }
        }
    }

    private func updatePreview() {
        if viewModel.isLoadingPreview {
            previewSpinner?.startAnimation(nil)
            emptyPreviewLabel?.isHidden = true
            previewScrollView.isHidden = true
            return
        }

        previewSpinner?.stopAnimation(nil)

        guard let result = viewModel.previewResult else {
            emptyPreviewLabel?.isHidden = false
            previewScrollView.isHidden = true
            return
        }

        emptyPreviewLabel?.isHidden = true
        previewScrollView.isHidden = false

        // Rebuild columns
        while previewTableView.numberOfColumns > 0 {
            previewTableView.removeTableColumn(previewTableView.tableColumns[0])
        }
        for col in result.columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.name))
            tableColumn.title = col.name
            tableColumn.width = 120
            tableColumn.minWidth = 60
            previewTableView.addTableColumn(tableColumn)
        }

        previewDataSource?.result = result
        previewTableView.reloadData()

        previewHeaderLabel.stringValue = "\(selectedTableName ?? "Table") — \(result.totalCount) rows"
    }
}

// MARK: - NSOutlineViewDataSource & Delegate (Table List)

extension ChartTablePickerController: NSOutlineViewDataSource, NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard item == nil else { return 0 }
        return viewModel.availableCollections.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        viewModel.availableCollections[index].name
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let name = item as? String else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("TableCell")
        let cellView: NSTableCellView

        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cellView = reused
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier

            let imageView = NSImageView()
            imageView.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
            imageView.contentTintColor = .secondaryLabelColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(imageView)
            cellView.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: 12)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(textField)
            cellView.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        cellView.textField?.stringValue = name
        return cellView
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = tableListView.selectedRow
        guard row >= 0, let name = tableListView.item(atRow: row) as? String else {
            selectedTableName = nil
            useTableButton.isEnabled = false
            return
        }
        selectedTableName = name
        useTableButton.isEnabled = true
        Task {
            await viewModel.loadPreview(tableName: name)
        }
    }
}

// MARK: - Preview Table Data Source (separate object to avoid delegate collision)

private final class PreviewTableDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var result: QueryResult?

    func numberOfRows(in tableView: NSTableView) -> Int {
        min(result?.rows.count ?? 0, 100)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let result else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("PreviewCell")
        let cellView: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cellView = reused
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: 11)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(textField)
            cellView.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        let colName = tableColumn.identifier.rawValue
        let info = result.rows[row][colName]
        cellView.textField?.stringValue = info?.value.map { "\($0)" } ?? "NULL"
        cellView.textField?.textColor = info?.value == nil ? .tertiaryLabelColor : .labelColor

        return cellView
    }
}
