import AppKit

@MainActor class TableCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, TableModificationUndoDelegate, RowUndoDelegate, NSMenuDelegate, CustomTableViewEditingDelegate, TableCellEditorOwner {
    var rows: [[String: Any?]]
    var schema: DatabaseSchemaResult?
    var totalCount: Int
    var queryResult: QueryResult?

    private var paddingRowCount: Int { showPaddingRows ? 3 : 0 }
    private static let schemaLessReadOnlyColumns: Set<String> = ["_id", "_creationTime"]
    private let showPaddingRows: Bool
    private let isReadOnly: Bool

    func isPaddingRow(_ row: Int) -> Bool {
        return row >= totalCount
    }
    
    private let containerView = NSView()
    private let scrollView = NSScrollView()
    let tableView = CustomTableView()

    // Static caches so user customizations survive coordinator recreation (tab switches)
    nonisolated(unsafe) private static var persistedColumnWidths: [String: CGFloat] = [:]  // Key: "autosaveKey.columnId"
    nonisolated(unsafe) private static var persistedColumnOrder: [String: [String]] = [:]  // Key: autosaveKey → [columnId...]

    private var columnWidthCache: [String: CGFloat] = [:]
    private var knownColumns: Set<String> = []
    private var queryColumnsByName: [String: QueryColumnInfo] = [:]
    private var schemaColumnsByName: [String: DatabaseSchemaInfo] = [:]
    private var displayPreviewCache: [String: String] = [:]
    private lazy var cellEditor: TableCellEditor = {
        let editor = TableCellEditor()
        editor.owner = self
        return editor
    }()

    private var autosaveKey: String {
        "\(cacheNamespace.isEmpty ? "global" : cacheNamespace)_\(tableName)"
    }

    private func persistedKey(for columnId: String) -> String {
        "\(autosaveKey).\(columnId)"
    }
    public var needsToSelectLastRow = false

    private var sortColumn: String?
    private var sortAscending = true
    
    var onSort: ((String, Bool) -> Void)?
    var onDeleteNewRow: ((Int) -> Void)?
    var onRefresh: (() -> Void)?
    var onForeignKeyNavigation: ((String, String, String) -> Void)?
    var onRowSelected: (([String: QueryRowInfo]?) -> Void)?
    var onUndoRowInsert: ((Int) -> Void)?

    public var tableName: String = ""
    private let cacheNamespace: String
    
    private enum CellIdentifier {
        static let checkbox = NSUserInterfaceItemIdentifier("CheckboxCell")
        static let displayCell = NSUserInterfaceItemIdentifier("DisplayCell")
        static let rowView = NSUserInterfaceItemIdentifier("CustomRowView")
        static let forignKeyCell = NSUserInterfaceItemIdentifier("ForeignKeyCell")
        static let enumCell = NSUserInterfaceItemIdentifier("EnumCell")
    }
    
    weak var modificationTracker: TableModificationTracker?
    weak var currentTab: DatabaseTab?

    private weak var editMenuItem: NSMenuItem?
    private weak var deleteMenuItem: NSMenuItem?
    private weak var addRowMenuItem: NSMenuItem?
    private weak var refreshMenuItem: NSMenuItem?
    private weak var quickLookMenuItem: NSMenuItem?
    private weak var copyMenuItem: NSMenuItem?
    private weak var copyRowsAsMenuItem: NSMenuItem?
    
    var highlightedFields: Set<String> = []
    var highlightedRows: Set<Int> = []
    private var isSidebarAnimating = false
    
    init(
        schema: DatabaseSchemaResult? = nil,
        queryResult: QueryResult?,
        tableName: String = "",
        onSort: ((String, Bool) -> Void)? = nil,
        modificationTracker: TableModificationTracker? = nil,
        onDeleteNewRow: ((Int) -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        onForeignKeyNavigation: ((String, String, String) -> Void)? = nil,
        highlightedFields: Set<String> = [],
        highlightedRows: Set<Int> = [],
        cacheNamespace: String = "",
        onRowSelected: (([String: QueryRowInfo]?) -> Void)? = nil,
        onUndoRowInsert: ((Int) -> Void)? = nil,
        showPaddingRows: Bool = true,
        isReadOnly: Bool = false
    ) {
        self.schema = schema
        self.queryResult = queryResult
        self.tableName = tableName
        self.onSort = onSort
        self.modificationTracker = modificationTracker
        self.onDeleteNewRow = onDeleteNewRow
        self.onRefresh = onRefresh
        self.onForeignKeyNavigation = onForeignKeyNavigation
        self.highlightedFields = highlightedFields
        self.highlightedRows = highlightedRows
        self.cacheNamespace = cacheNamespace
        self.onRowSelected = onRowSelected
        self.onUndoRowInsert = onUndoRowInsert
        self.showPaddingRows = showPaddingRows
        self.isReadOnly = isReadOnly

        if let queryResult = queryResult {
            self.rows = queryResult.rawRows
            self.totalCount = queryResult.totalCount
        } else {
            self.rows = []
            self.totalCount = 0
        }

        super.init()

        rebuildLookupCaches()

        self.modificationTracker?.undoDelegate = self
        self.modificationTracker?.rowUndoDelegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(columnDidResize(_:)), name: NSTableView.columnDidResizeNotification, object: tableView)
        NotificationCenter.default.addObserver(self, selector: #selector(columnDidMove(_:)), name: NSTableView.columnDidMoveNotification, object: tableView)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeleteKey(notification:)), name: .didRequestDelete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleForeignKeyNavigation(notification:)), name: .foreignKeyNavigationRequested, object: tableView)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTableReloadData(notification:)), name: .tableReloadData, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleQuickLookRequest(notification:)), name: .cellQuickLookRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCopyKey(notification:)), name: .didRequestCopy, object: nil)

        // Sidebar animation observers for performance optimization
        NotificationCenter.default.addObserver(self, selector: #selector(sidebarAnimationWillStart(_:)), name: .sidebarAnimationWillStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sidebarAnimationDidEnd(_:)), name: .sidebarAnimationDidEnd, object: nil)
    }
    
    @objc private func handleTableReloadData(notification: Notification) {
        if let userInfo = notification.userInfo {
            // Tab-scoped posts must only reload the coordinator for that tab;
            // same-named tables in other tabs/connections would otherwise
            // cross-fire. Posts without a tabID stay broadcast (e.g. table
            // appearance changes).
            if let targetTabID = userInfo["tabID"] as? String,
               !targetTabID.isEmpty,
               targetTabID != currentTab?.id.uuidString {
                return
            }
            if let targetTableName = userInfo["tableName"] as? String,
               !targetTableName.isEmpty,
               targetTableName != self.tableName {
                return
            }
        }
        guard !isSidebarAnimating else { return }
        Task { @MainActor [weak self] in
            self?.tableView.reloadData()
        }
    }

    @objc private func sidebarAnimationWillStart(_ notification: Notification) {
        isSidebarAnimating = true
    }

    @objc private func sidebarAnimationDidEnd(_ notification: Notification) {
        isSidebarAnimating = false
    }

    @objc private func handleCopyKey(notification: Notification) {
        guard notification.userInfo?["tableView"] as? CustomTableView === tableView else { return }
        copyRowsAsPlainText()
    }

    @objc private func handleDeleteKey(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rows = userInfo["rows"] as? IndexSet,
              let notificationTableView = userInfo["tableView"] as? CustomTableView,
              notificationTableView === self.tableView else {
            return
        }
        
        for row in rows {
            if let rowModification = modificationTracker?.getRowModification(for: row),
               rowModification.type == .insert {
                onDeleteNewRow?(rowModification.rowIndex)
            } else {
                modificationTracker?.markAsDeleted(rowIndex: row)
            }
        }
        
        tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }
    
    @objc private func handleForeignKeyNavigation(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let constraintInfo = userInfo["constraintInfo"] as? ConstraintInfo,
              let currentValue = userInfo["currentValue"] as? String,
              let referencedTable = userInfo["referencedTable"] as? String else {
            debugLog("❌ Invalid foreign key navigation notification data")
            return
        }

        debugLog("🔗 Handling foreign key navigation to table: \(referencedTable) with value: \(currentValue)")

        guard let referencedColumn = constraintInfo.referencedColumns?.first else {
            return
        }

        Task { @MainActor [weak self] in
            self?.onForeignKeyNavigation?(referencedTable, referencedColumn, currentValue)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - TableModificationUndoDelegate
    func willUndoModification(rowIndex: Int, columnName: String, fromValue: String, toValue: String) {
        debugLog("🔄 Will undo modification: Row \(rowIndex), Column \(columnName), \(fromValue) → \(toValue)")
    }
    
    func didUndoModification(rowIndex: Int, columnName: String, newValue: String) {
        debugLog("✅ Did undo modification: Row \(rowIndex), Column \(columnName) → \(newValue)")

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.invalidateDisplayPreview(row: rowIndex, column: columnName)

            if rowIndex < self.tableView.numberOfRows {
                let rowIndexSet = IndexSet(integer: rowIndex)
                self.tableView.reloadData(forRowIndexes: rowIndexSet, columnIndexes: IndexSet(integersIn: 0..<self.tableView.numberOfColumns))
            }
        }
    }

    // MARK: - RowUndoDelegate
    func didUndoRowInsert(rowIndex: Int) {
        debugLog("✅ Did undo row insert at index \(rowIndex)")
        onUndoRowInsert?(rowIndex)
    }

    func didUndoRowDelete(rowIndex: Int, rowData: [String: Any]?) {
        debugLog("✅ Did undo row delete at index \(rowIndex)")
    }
    
    @objc private func handleUndo() -> Bool {
        guard let modificationTracker else { return false }
        return modificationTracker.undo()
    }

    func setupTableView() -> NSView {
        setupUI()
        setupTable()
        return containerView
    }
    
    // MARK: - Real-time Change Highlighting
    
    func updateHighlighting(fields: Set<String>, rows: Set<Int>) {
        let fieldsChanged = highlightedFields != fields
        let rowsChanged = highlightedRows != rows
        guard fieldsChanged || rowsChanged else { return }

        highlightedFields = fields
        highlightedRows = rows

        Task { @MainActor in
            if !rows.isEmpty {
                self.tableView.reloadData(forRowIndexes: IndexSet(rows), columnIndexes: IndexSet(0..<self.tableView.numberOfColumns))
            } else if fieldsChanged {
                self.tableView.reloadData()
            }
        }
    }
    
    func updateRows(_ newQueryResult: QueryResult?, newSchema: DatabaseSchemaResult? = nil) {
        let previousSelectedRow = self.tableView.getCurrentSelectedCell()?.row

        let oldColumnNames = Set(self.tableView.tableColumns.map(\.identifier.rawValue))

        self.queryResult = newQueryResult
        self.schema = newSchema
        rebuildLookupCaches()

        if let newQueryResult = newQueryResult {
            self.rows = newQueryResult.rawRows
            self.totalCount = newQueryResult.totalCount
        } else {
            self.rows = []
            self.totalCount = 0
        }

        let newColumns: [(name: String, dataType: String?)]
        if let newQueryResult = newQueryResult, !newQueryResult.columns.isEmpty {
            newColumns = newQueryResult.columns.map { ($0.name, $0.dataType) }
        } else if let newSchema = newSchema {
            newColumns = newSchema.columns.map { ($0.columnName, $0.dataType) }
        } else {
            newColumns = []
        }
        let newColumnNames = Set(newColumns.map(\.name))

        if let previousSelectedRow, previousSelectedRow >= totalCount {
            debugLog("🔄 Previously selected row \(previousSelectedRow) is out of bounds (new count: \(totalCount)). Clearing selection.")
            tableView.clearAllSelection()
        }

        if newColumnNames != oldColumnNames {
            if oldColumnNames.isEmpty {
                rebuildTableStructure()
            } else {
                let addedColumns = newColumns.filter { !oldColumnNames.contains($0.name) }
                let removedColumns = oldColumnNames.subtracting(newColumnNames)

                if removedColumns.isEmpty && !addedColumns.isEmpty {
                    for col in addedColumns {
                        createColumn(identifier: col.name, title: col.name, dataType: col.dataType, icon: nil)
                    }
                    refreshColumnHeadersFromSchema()
                    tableView.reloadData()
                } else {
                    rebuildTableStructure()
                }
            }
        } else {
            // Columns unchanged — but schema may have just arrived, so refresh
            // header FK badges/tooltips. Cells re-render via reloadData below.
            refreshColumnHeadersFromSchema()
            tableView.reloadData()
        }

        if needsToSelectLastRow {
            scrollToBottomAndSelectFirstCell()
        }

        if let queryResult {
            recalculateColumnWidthsIfNeeded(queryResult: queryResult)
        }
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        // Get the first (primary) sort descriptor
        guard let sortDescriptor = tableView.sortDescriptors.first else { return }
        
        // Find the column whose sortDescriptorPrototype matches
        for column in tableView.tableColumns {
            if let prototype = column.sortDescriptorPrototype,
               prototype.key == sortDescriptor.key {
                let columnTitle = column.title
                debugLog("✅ Received sort notification for column: \(columnTitle)")
                sortTableData(by: columnTitle)
                break
            }
        }
    }
    
    
    private func sortTableData(by columnTitle: String) {
        if sortColumn == columnTitle {
            if sortAscending {
                sortAscending = false
            } else {
                sortColumn = nil
                sortAscending = true
            }
        } else {
            sortColumn = columnTitle
            sortAscending = true
        }

        updateTableHeaders()
        onSort?(sortColumn ?? "", sortAscending)
    }
    
    private func updateTableHeaders() {
        // Don't update headers if table view is being deallocated
        guard tableView.window != nil else { return }

        for tableColumn in tableView.tableColumns {
            let columnId = tableColumn.identifier.rawValue
            if let headerCell = tableColumn.headerCell as? CustomTableHeaderCell {
                let isCurrentSortColumn = (sortColumn == columnId)
                headerCell.updateSortIndicator(isActive: isCurrentSortColumn, ascending: sortAscending)
            }
        }
    }
    
    // Public method to set sorting state from parent view
    func setSortState(column: String?, ascending: Bool) {
        sortColumn = column
        sortAscending = ascending
        updateTableHeaders()
    }

    private func rebuildLookupCaches() {
        queryColumnsByName = Dictionary(
            (queryResult?.columns ?? []).map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        schemaColumnsByName = Dictionary(
            (schema?.columns ?? []).map { ($0.columnName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        displayPreviewCache.removeAll(keepingCapacity: true)
    }

    private func displayCacheKey(row: Int, column: String) -> String {
        "\(row)\u{1F}\(column)"
    }

    private func invalidateDisplayPreview(row: Int, column: String) {
        displayPreviewCache.removeValue(forKey: displayCacheKey(row: row, column: column))
    }

    private func previewString(for value: DatabaseValue?) -> String {
        guard let value else { return "" }

        switch value {
        case .null:
            return ""
        case .string(let string), .decimalString(let string), .objectID(let string):
            return truncatedPreview(string)
        case .uuid(let uuid):
            return uuid.uuidString
        case .bool(let bool):
            return bool.description
        case .int(let int):
            return int.description
        case .int64(let int64):
            return int64.description
        case .double(let double):
            return double.description
        case .date(let date):
            return date.description
        case .data(let data):
            return truncatedPreview(data.base64EncodedString())
        case .array:
            return "[...]"
        case .object:
            return "{...}"
        }
    }

    private func fullString(for value: DatabaseValue?) -> String {
        guard let value else { return "" }
        return value.description
    }

    private func truncatedPreview(_ string: String) -> String {
        let nsString = string as NSString
        guard nsString.length > 300 else { return string }
        return nsString.substring(to: 300) + "\u{2026}"
    }

    private func currentFullValue(row: Int, columnName: String) -> String {
        if let cellModification = modificationTracker?.getCellModification(rowIndex: row, columnName: columnName) {
            return cellModification.newValue
        }

        return fullString(for: queryResult?.value(row: row, column: columnName)?.value)
    }

    private func currentPreviewValue(row: Int, columnName: String) -> String {
        if let cellModification = modificationTracker?.getCellModification(rowIndex: row, columnName: columnName) {
            return truncatedPreview(cellModification.newValue)
        }

        let key = displayCacheKey(row: row, column: columnName)
        if let cached = displayPreviewCache[key] {
            return cached
        }

        let preview = previewString(for: queryResult?.value(row: row, column: columnName)?.value)
        displayPreviewCache[key] = preview
        return preview
    }

    private var usesSchemaLessSystemColumns: Bool {
        guard schema == nil, let queryResult else { return false }
        let columnNames = Set(queryResult.columns.map(\.name))
        return columnNames.contains("_id") && columnNames.contains("_creationTime")
    }

    private func isColumnReadOnly(_ columnName: String) -> Bool {
        if isReadOnly {
            return true
        }

        if let schemaColumn = schemaColumnsByName[columnName] {
            return schemaColumn.isReadOnly
        }

        return usesSchemaLessSystemColumns && Self.schemaLessReadOnlyColumns.contains(columnName)
    }

    private func firstEditableColumnIndex() -> Int {
        guard let editableIndex = tableView.tableColumns.firstIndex(where: { !isColumnReadOnly($0.identifier.rawValue) }) else {
            return 0
        }

        return editableIndex
    }
    
    func scrollToBottomAndSelectFirstCell() {
        Task { @MainActor in
            self.needsToSelectLastRow = false
            guard self.totalCount > 0 else { return }

            let lastDataRowIndex = self.totalCount - 1
            let targetColumnIndex = self.firstEditableColumnIndex()
            self.tableView.scrollRowToVisible(self.tableView.numberOfRows - 1)

            if self.tableView.numberOfColumns > 0 {
                self.tableView.window?.makeFirstResponder(self.tableView)
                self.tableView.editColumn(targetColumnIndex, row: lastDataRowIndex, with: nil, select: true)
                self.tableView.selectCell(row: lastDataRowIndex, column: targetColumnIndex)
            }
        }
    }
    
    private func resolveHeaderInfo(identifier: String, dataType: String?) -> (tooltip: String?, isForeignKey: Bool) {
        guard let schema, let columnInfo = schema.column(named: identifier) else {
            return (dataType, false)
        }
        var isForeignKey = false
        var relationText: String?
        if let fkConstraint = columnInfo.constraints.first(where: { $0.type == .foreignKey }) {
            isForeignKey = true
            let refSchema = fkConstraint.referencedSchema
            let refTable = fkConstraint.referencedTable
            let refColumn = fkConstraint.referencedColumns?.first
            var target = ""
            if let refTable {
                if let refSchema, !refSchema.isEmpty {
                    target = "\(refSchema).\(refTable)"
                } else {
                    target = refTable
                }
                if let refColumn, !refColumn.isEmpty {
                    target += ".\(refColumn)"
                }
            }
            if !target.isEmpty {
                relationText = "Foreign key relation: \(identifier) → \(target)"
            }
        }
        let tooltip: String?
        if let relationText {
            tooltip = relationText
        } else if let dataType, !dataType.isEmpty {
            tooltip = dataType
        } else {
            tooltip = nil
        }
        return (tooltip, isForeignKey)
    }

    private func refreshColumnHeadersFromSchema() {
        for column in tableView.tableColumns {
            guard let headerCell = column.headerCell as? CustomTableHeaderCell else { continue }
            let identifier = column.identifier.rawValue
            let dataType = queryColumnsByName[identifier]?.dataType
                ?? schemaColumnsByName[identifier]?.dataType
            let (tooltip, isForeignKey) = resolveHeaderInfo(identifier: identifier, dataType: dataType)
            headerCell.configure(title: column.title, fieldType: dataType, tooltip: tooltip, isForeignKey: isForeignKey)
        }
        tableView.headerView?.needsDisplay = true
    }

    private func createColumn(identifier: String, title: String, dataType: String?, icon: NSImage?) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title

        // Use persisted width (survives tab switches), then instance cache, then default
        let width = Self.persistedColumnWidths[persistedKey(for: identifier)] ?? columnWidthCache[identifier]
        if let width {
            column.width = width
            column.minWidth = 10
            column.maxWidth = CGFloat.greatestFiniteMagnitude
            columnWidthCache[identifier] = width
        }

        // Add custom header
        let customHeaderCell = CustomTableHeaderCell(textCell: identifier)
        let (tooltip, isForeignKey) = resolveHeaderInfo(identifier: identifier, dataType: dataType)
        customHeaderCell.configure(title: title, fieldType: dataType, tooltip: tooltip, isForeignKey: isForeignKey)
        column.headerCell = customHeaderCell
        
        let sortDescriptor = NSSortDescriptor(key: column.title, ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        column.sortDescriptorPrototype = sortDescriptor
        
        let preAddWidth = column.width
        tableView.addTableColumn(column)
        let postAddWidth = column.width
        if preAddWidth != postAddWidth {
            columnWidthCache[identifier] = postAddWidth
        }

        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClick(_:))
    }
    
    @objc private func columnDidResize(_ notification: Notification) {
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        let id = column.identifier.rawValue
        columnWidthCache[id] = column.width
        Self.persistedColumnWidths[persistedKey(for: id)] = column.width
    }

    @objc private func columnDidMove(_ notification: Notification) {
        Self.persistedColumnOrder[autosaveKey] = tableView.tableColumns.map(\.identifier.rawValue)
    }

    @objc func tableViewDoubleClick(_ sender: AnyObject) {
        if let cellLocation = tableView.getCurrentSelectedCell() {
            tableView.enterEditModeForCell(row: cellLocation.row, column: cellLocation.column)
        }
    }
    
    private func setupUI() {
        containerView.wantsLayer = true

        tableView.style = .plain
        tableView.rowSizeStyle = .custom
        tableView.backgroundColor = NSColor.clear
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 0)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = NSColor.clear
        scrollView.focusRingType = .none

        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    private func setupTable() {
        // Always set dataSource/delegate even if no columns yet —
        // columns may arrive later via updateRows
        if tableView.dataSource == nil {
            tableView.allowsColumnResizing = true
            tableView.allowsColumnReordering = true
            tableView.columnAutoresizingStyle = .noColumnAutoresizing

            tableView.autosaveName = autosaveKey
            tableView.autosaveTableColumns = true

            tableView.allowsColumnSelection = true
            tableView.allowsMultipleSelection = true
            tableView.allowsEmptySelection = true

            tableView.dataSource = self
            tableView.delegate = self
            tableView.editingDelegate = self
        }

        let columnsToUse: [(name: String, dataType: String?)]

        if let queryResult = queryResult, !queryResult.columns.isEmpty {
            columnsToUse = queryResult.columns.map { ($0.name, $0.dataType) }
        } else if let schema = schema {
            columnsToUse = schema.columns.map { ($0.columnName, $0.dataType) }
        } else {
            return
        }

        if let queryResult = queryResult {
            preCalculateOptimalColumnWidths(for: columnsToUse, queryResult: queryResult)
        }

        // Reorder columns to match user's persisted arrangement if available
        let orderedColumns: [(name: String, dataType: String?)]
        if let savedOrder = Self.persistedColumnOrder[autosaveKey] {
            let columnsByName = Dictionary(columnsToUse.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            let reordered = savedOrder.compactMap { columnsByName[$0] }
            let remaining = columnsToUse.filter { col in !savedOrder.contains(col.name) }
            orderedColumns = reordered + remaining
        } else {
            orderedColumns = columnsToUse
        }

        for columnInfo in orderedColumns {
            createColumn(
                identifier: columnInfo.name,
                title: columnInfo.name,
                dataType: columnInfo.dataType,
                icon: nil
            )
        }

        tableView.undoHandler = { [weak self] in
            self?.handleUndo() ?? false
        }

        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshCurrentTable), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = [.command]
        refreshItem.target = self
        menu.addItem(refreshItem)
        self.refreshMenuItem = refreshItem

        menu.addItem(.separator())

        let addRowItem = NSMenuItem(title: "Add Row", action: #selector(addRow), keyEquivalent: "i")
        addRowItem.keyEquivalentModifierMask = [.command]
        addRowItem.target = self
        menu.addItem(addRowItem)
        self.addRowMenuItem = addRowItem

        let editItem = NSMenuItem(title: "Edit", action: #selector(editItem), keyEquivalent: "\r")
        editItem.target = self
        menu.addItem(editItem)
        self.editMenuItem = editItem

        let quickLookItem = NSMenuItem(title: "Quick Look", action: #selector(quickLookItem), keyEquivalent: "\r")
        quickLookItem.keyEquivalentModifierMask = [.command]
        quickLookItem.target = self
        menu.addItem(quickLookItem)
        self.quickLookMenuItem = quickLookItem

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteItem), keyEquivalent: "\u{8}")
        deleteItem.keyEquivalentModifierMask = []
        deleteItem.target = self
        menu.addItem(deleteItem)
        self.deleteMenuItem = deleteItem

        menu.addItem(.separator())

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyRowsAsPlainText), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.target = self
        menu.addItem(copyItem)
        self.copyMenuItem = copyItem

        // Copy Rows As submenu
        let copyRowsAsItem = NSMenuItem(title: "Copy Rows As", action: nil, keyEquivalent: "")
        let copyRowsSubmenu = NSMenu()

        let plainTextItem = NSMenuItem(title: "Plain Text", action: #selector(copyRowsAsPlainText), keyEquivalent: "")
        plainTextItem.target = self
        copyRowsSubmenu.addItem(plainTextItem)

        let jsonItem = NSMenuItem(title: "JSON", action: #selector(copyRowsAsJSON), keyEquivalent: "")
        jsonItem.target = self
        copyRowsSubmenu.addItem(jsonItem)

        let htmlItem = NSMenuItem(title: "HTML", action: #selector(copyRowsAsHTML), keyEquivalent: "")
        htmlItem.target = self
        copyRowsSubmenu.addItem(htmlItem)

        let markdownItem = NSMenuItem(title: "Markdown Table", action: #selector(copyRowsAsMarkdown), keyEquivalent: "")
        markdownItem.target = self
        copyRowsSubmenu.addItem(markdownItem)

        copyRowsSubmenu.addItem(.separator())

        let csvItem = NSMenuItem(title: "CSV", action: #selector(copyRowsAsCSV), keyEquivalent: "")
        csvItem.target = self
        copyRowsSubmenu.addItem(csvItem)

        let csvHeaderItem = NSMenuItem(title: "CSV with Header", action: #selector(copyRowsAsCSVWithHeader), keyEquivalent: "")
        csvHeaderItem.target = self
        copyRowsSubmenu.addItem(csvHeaderItem)

        copyRowsSubmenu.addItem(.separator())

        let insertItem = NSMenuItem(title: "INSERT Statement", action: #selector(copyRowsAsInsertStatement), keyEquivalent: "")
        insertItem.target = self
        copyRowsSubmenu.addItem(insertItem)

        copyRowsAsItem.submenu = copyRowsSubmenu
        menu.addItem(copyRowsAsItem)
        self.copyRowsAsMenuItem = copyRowsAsItem

        menu.delegate = self
        menu.autoenablesItems = false
        tableView.menu = menu

        if TableAppearanceSettings.alternatingRowColors {
            tableView.gridStyleMask = [.solidVerticalGridLineMask]
            tableView.gridColor = .separatorColor
        }

        let customHeaderView = CustomTableHeaderView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 32))

        let visualEffectView = NSVisualEffectView()
        visualEffectView.frame = customHeaderView.bounds
        visualEffectView.material = .contentBackground
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]

        visualEffectView.wantsLayer = true
        visualEffectView.layer?.zPosition = -1000

        customHeaderView.addSubview(visualEffectView)

        tableView.headerView = customHeaderView
    }
    
    
    private func rebuildTableStructure() {
        // Preserve user-resized widths before tearing down columns
        for col in tableView.tableColumns {
            let id = col.identifier.rawValue
            let currentWidth = col.width
            if currentWidth > 0 {
                columnWidthCache[id] = currentWidth
            }
        }
        knownColumns.removeAll()

        while !tableView.tableColumns.isEmpty {
            tableView.removeTableColumn(tableView.tableColumns[0])
        }

        setupTable()
        tableView.reloadData()
    }
    
    private func calculateDataHash(queryResult: QueryResult?, schema: DatabaseSchemaResult?) -> Int {
        var hasher = Hasher()
        
        // Hash basic properties
        hasher.combine(queryResult?.totalCount ?? 0)
        hasher.combine(queryResult?.columns.count ?? 0)
        hasher.combine(schema?.columns.count ?? 0)
        
        // Hash column names for structure changes
        if let columns = queryResult?.columns {
            for column in columns {
                hasher.combine(column.name)
                hasher.combine(column.dataType)
            }
        } else if let schemaColumns = schema?.columns {
            for column in schemaColumns {
                hasher.combine(column.columnName)
                hasher.combine(column.dataType)
            }
        }
        
        return hasher.finalize()
    }
    
    private func preCalculateOptimalColumnWidths(for columnsToUse: [(name: String, dataType: String?)], queryResult: QueryResult) {
        // Pre-computed font attributes for performance
        let headerFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let contentFont = NSFont.systemFont(ofSize: 12)
        let headerAttributes = [NSAttributedString.Key.font: headerFont]
        let contentAttributes = [NSAttributedString.Key.font: contentFont]

        // Calculate optimal width for each column
        for columnInfo in columnsToUse {
            let columnIdentifier = columnInfo.name

            // Skip if user has resized (persisted) or already calculated
            if Self.persistedColumnWidths[persistedKey(for: columnIdentifier)] != nil || columnWidthCache[columnIdentifier] != nil {
                continue
            }

            // Calculate header width
            let headerWidth = (columnInfo.name as NSString).size(withAttributes: headerAttributes).width + 45
            // Smart sampling for content width
            let sampleSize = determineSampleSize(totalRows: self.totalCount)
            let sampleIndices = generateSampleIndices(totalRows: self.totalCount, sampleSize: sampleSize)

            var maxContentWidth: CGFloat = 0

            // Efficiently calculate max content width
            for rowIndex in sampleIndices {
                if let value = queryResult.value(row: rowIndex, column: columnIdentifier) {
                    let contentString = formatValueForWidthCalculation(value.value)

                    // Quick estimation first
                    if contentString.count > 300 {
                        maxContentWidth = 400
                    } else {
                        // Accurate measurement for shorter strings
                        let contentWidth = (contentString as NSString).size(withAttributes: contentAttributes).width + 30
                        maxContentWidth = max(maxContentWidth, contentWidth)
                    }
                }
            }

            let optimalWidth = max(headerWidth, maxContentWidth)
            columnWidthCache[columnIdentifier] = optimalWidth
        }
    }
    
    private func recalculateColumnWidthsIfNeeded(queryResult: QueryResult) {
        let columnsToProcess: [(name: String, dataType: String?)]
        if !queryResult.columns.isEmpty {
            columnsToProcess = queryResult.columns.map { ($0.name, $0.dataType) }
        } else if let schema = schema {
            columnsToProcess = schema.columns.map { ($0.columnName, $0.dataType) }
        } else {
            return
        }

        let currentColumnNames = Set(columnsToProcess.map { $0.name })
        let newColumns = currentColumnNames.subtracting(knownColumns)

        let columnsNeedingCalculation = columnsToProcess.filter { columnInfo in
            newColumns.contains(columnInfo.name) && columnWidthCache[columnInfo.name] == nil
        }

        if !columnsNeedingCalculation.isEmpty {
            preCalculateOptimalColumnWidths(for: columnsNeedingCalculation, queryResult: queryResult)

            for tableColumn in tableView.tableColumns {
                let columnId = tableColumn.identifier.rawValue
                if columnsNeedingCalculation.contains(where: { $0.name == columnId }),
                   let newWidth = columnWidthCache[columnId] {
                    tableColumn.width = newWidth
                    tableColumn.minWidth = 10
                    tableColumn.maxWidth = CGFloat.greatestFiniteMagnitude
                }
            }
        }

        knownColumns = currentColumnNames
    }
    
    // MARK: - NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        return totalCount + paddingRowCount
    }
    
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        if let rowView = tableView.makeView(withIdentifier: CellIdentifier.rowView, owner: self) as? CustomTableRowView {
            return rowView
        }
        let rowView = CustomTableRowView()
        rowView.identifier = CellIdentifier.rowView
        return rowView
    }

    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        guard let tableColumn = tableView.tableColumns[safe: column] else {
            return 100 // Default width
        }

        let columnIdentifier = tableColumn.identifier.rawValue

        // Return cached width if available
        if let cachedWidth = columnWidthCache[columnIdentifier] {
            return cachedWidth
        }

        // Fallback: basic calculation
        let headerFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let headerAttributes = [NSAttributedString.Key.font: headerFont]
        let headerWidth = (tableColumn.title as NSString).size(withAttributes: headerAttributes).width + 50

        return max(100, headerWidth) // Minimum reasonable width
    }

    private func determineSampleSize(totalRows: Int) -> Int {
        switch totalRows {
        case 0...50:
            return totalRows // Sample all for small datasets
        case 51...500:
            return min(50, totalRows) // Sample up to 50 for medium datasets
        case 501...5000:
            return min(100, totalRows) // Sample up to 100 for large datasets
        default:
            return min(200, totalRows) // Sample up to 200 for very large datasets
        }
    }
    
    private func generateSampleIndices(totalRows: Int, sampleSize: Int) -> [Int] {
        guard totalRows > sampleSize else {
            return Array(0..<totalRows)
        }
        
        var indices: Set<Int> = []
        
        // Always include first few rows
        for i in 0..<min(5, sampleSize / 4, totalRows) {
            indices.insert(i)
        }
        
        // Always include last few rows
        for i in max(0, totalRows - min(5, sampleSize / 4))..<totalRows {
            indices.insert(i)
        }
        
        // Add random sampling for the middle
        let remainingSamples = sampleSize - indices.count
        let middleStart = min(5, sampleSize / 4)
        let middleEnd = max(0, totalRows - min(5, sampleSize / 4))
        
        for _ in 0..<remainingSamples {
            if middleStart < middleEnd {
                let randomIndex = Int.random(in: middleStart..<middleEnd)
                indices.insert(randomIndex)
            }
        }
        
        return Array(indices).sorted()
    }
    
    private func formatValueForWidthCalculation(_ value: Any?) -> String {
        guard let value = value else { return "(NULL)" }
        
        if let stringValue = value as? String {
            let nsString = stringValue as NSString
            return nsString.length > 50 ? nsString.substring(to: 50) + "..." : stringValue
        }
        
        return String(describing: value)
    }
    
    private func estimateWidth(_ text: String, font: NSFont) -> CGFloat {
        let avgCharWidth = font.maximumAdvancement.width * 0.6 // rough estimate
        return CGFloat(text.count) * avgCharWidth + 24
    }
    
    private func calculateMaxReasonableWidth() -> CGFloat {
        // Base max width on screen/table size
        let screenWidth = NSScreen.main?.frame.width ?? 1920
        let tableWidth = tableView.frame.width > 0 ? tableView.frame.width : screenWidth * 0.8
        
        // Don't let any single column take more than 1/3 of the table width
        return min(400, tableWidth / 3)
    }
    
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 28
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return !isPaddingRow(row)
    }

    // MARK: - NSTableViewDelegate
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        autoreleasepool {
            viewForCell(tableView, tableColumn: tableColumn, row: row)
        }
    }

    private func viewForCell(_ tableView: NSTableView, tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn = tableColumn else { return nil }

        // Return empty view for padding rows
        if isPaddingRow(row) {
            let emptyView = NSView()
            emptyView.wantsLayer = false
            return emptyView
        }

        guard let queryResult = queryResult else { return nil }

        let columnName = tableColumn.identifier.rawValue
        guard let queryRowInfo = queryResult.value(row: row, column: columnName) else {
            debugLog("⚠️ TableCoordinator: No data for row \(row), column \(columnName)")
            return nil
        }

        if highlightedRows.contains(row) && highlightedFields.contains(columnName) {
            debugLog("💡 TableCoordinator: Rendering highlighted cell [\(row), \(columnName)] = \(queryRowInfo.value?.description ?? "nil")")
        }

        guard let columnInfo = queryColumnsByName[columnName] else {
            return nil
        }

        let schemaColumn = schemaColumnsByName[columnName]
        let isReadOnly = isColumnReadOnly(columnName)
        let isNullable = schemaColumn?.isNullable.uppercased() == "YES"

        if let schemaColumn = schemaColumn,
           schemaColumn.isEnum,
           let enumValues = schemaColumn.enumValues {
            return configureEnumCell(
                tableView: tableView,
                value: queryRowInfo.value?.stringValue ?? "",
                enumValues: enumValues,
                row: row,
                columnName: columnName,
                dataType: columnInfo.dataType,
                isReadOnly: isReadOnly,
                isNullable: isNullable
            )
        }

        var cellView = tableView.makeView(withIdentifier: CellIdentifier.displayCell, owner: self) as? TableDisplayCellView

        if cellView == nil {
            cellView = TableDisplayCellView()
            cellView?.identifier = CellIdentifier.displayCell
        } else {
            cellView?.prepareForReuse()
        }

        let foreignKeyConstraint = schemaColumn?.constraints.first { $0.type == .foreignKey }

        let isHighlightedField = highlightedFields.contains(columnName)
        let isHighlightedRow = highlightedRows.contains(row)
        let shouldHighlight = isHighlightedField && isHighlightedRow

        let rowModification = modificationTracker?.getRowModification(for: row)
        let isInsertRow = rowModification?.type == .insert
        let cellModification = modificationTracker?.getCellModification(rowIndex: row, columnName: columnName)
        let isModified = isInsertRow || (cellModification?.hasChanged ?? false)
        let isMarkedForDeletion = rowModification?.type == .delete
        let displayText = currentPreviewValue(row: row, columnName: columnName)
        let placeholder: String
        if displayText.isEmpty, queryRowInfo.value != nil || cellModification != nil {
            placeholder = "(EMPTY)"
        } else if isReadOnly && queryRowInfo.value == nil {
            placeholder = "(Auto-generated)"
        } else {
            placeholder = "(NULL)"
        }

        cellView?.configure(
            displayText: displayText,
            placeholder: placeholder,
            hasValue: !displayText.isEmpty,
            rowIndex: row,
            columnName: columnName,
            tableName: tableName,
            constraintInfo: foreignKeyConstraint,
            isModified: isModified,
            isMarkedForDeletion: isMarkedForDeletion,
            shouldHighlight: shouldHighlight
        )

        return cellView
    }

    private func configureEnumCell(
        tableView: NSTableView,
        value: String,
        enumValues: [String],
        row: Int,
        columnName: String,
        dataType: String,
        isReadOnly: Bool,
        isNullable: Bool
    ) -> NSView? {
        var cellView = tableView.makeView(withIdentifier: CellIdentifier.enumCell, owner: self) as? EnumCellView

        if cellView == nil {
            cellView = EnumCellView()
            cellView?.identifier = CellIdentifier.enumCell
        } else {
            cellView?.prepareForReuse()
        }

        cellView?.configure(
            value: value,
            enumValues: enumValues,
            rowIndex: row,
            columnName: columnName,
            dataType: dataType,
            modificationTracker: modificationTracker,
            tableName: tableName,
            isReadOnly: isReadOnly,
            isNullable: isNullable
        )

        return cellView
    }

    // MARK: - CustomTableViewEditingDelegate

    func customTableView(_ tableView: CustomTableView, editCellAtRow row: Int, column: Int) {
        guard row >= 0,
              row < totalCount,
              column >= 0,
              column < tableView.numberOfColumns else {
            return
        }

        clearActiveDisplayCellEditingState()

        let columnName = tableView.tableColumns[column].identifier.rawValue
        guard !isColumnReadOnly(columnName),
              let columnInfo = queryColumnsByName[columnName] else {
            return
        }

        let currentValue = currentFullValue(row: row, columnName: columnName)
        let originalValue = modificationTracker?
            .getCellModification(rowIndex: row, columnName: columnName)?
            .originalValue ?? currentValue

        let context = TableCellEditor.Context(
            row: row,
            column: column,
            columnName: columnName,
            dataType: columnInfo.dataType,
            originalValue: originalValue,
            isReadOnly: false
        )

        tableView.selectCell(row: row, column: column)
        activeDisplayCell(row: row, column: column)?.setEditing(true)
        cellEditor.beginEditing(
            in: tableView,
            frame: tableView.frameOfCell(atColumn: column, row: row),
            context: context,
            value: currentValue
        )
    }

    func customTableView(_ tableView: CustomTableView, foreignKeyClickedAtRow row: Int, column: Int) {
        guard row >= 0,
              row < totalCount,
              column >= 0,
              column < tableView.numberOfColumns else {
            return
        }

        let columnName = tableView.tableColumns[column].identifier.rawValue
        guard let constraintInfo = schemaColumnsByName[columnName]?.constraints.first(where: { $0.type == .foreignKey }),
              constraintInfo.isForeignKey,
              let referencedTable = constraintInfo.referencedTable else {
            debugLog("❌ Invalid foreign key constraint info")
            return
        }

        NotificationCenter.default.post(
            name: .foreignKeyNavigationRequested,
            object: tableView,
            userInfo: [
                "constraintInfo": constraintInfo,
                "currentValue": currentFullValue(row: row, columnName: columnName),
                "sourceTable": tableName,
                "sourceColumn": columnName,
                "referencedTable": referencedTable
            ]
        )
    }

    // MARK: - TableCellEditorOwner

    func tableCellEditorDidCommit(_ editor: TableCellEditor, context: TableCellEditor.Context, value: String) {
        activeDisplayCell(row: context.row, column: context.column)?.setEditing(false)

        if value != context.originalValue {
            modificationTracker?.updateCell(
                rowIndex: context.row,
                columnName: context.columnName,
                newValue: value,
                originalValue: context.originalValue,
                dataType: context.dataType
            )
        } else {
            modificationTracker?.resetCell(rowIndex: context.row, columnName: context.columnName)
        }

        invalidateDisplayPreview(row: context.row, column: context.columnName)
        reloadCell(row: context.row, column: context.column)
    }

    func tableCellEditorDidCancel(_ editor: TableCellEditor, context: TableCellEditor.Context) {
        activeDisplayCell(row: context.row, column: context.column)?.setEditing(false)
        reloadCell(row: context.row, column: context.column)
    }

    func tableCellEditorDidRequestNavigation(_ editor: TableCellEditor, context: TableCellEditor.Context, direction: TableCellEditor.NavigationDirection) {
        let target: (row: Int, column: Int)?

        switch direction {
        case .next:
            target = context.column + 1 < tableView.numberOfColumns ? (context.row, context.column + 1) : nil
        case .previous:
            target = context.column - 1 >= 0 ? (context.row, context.column - 1) : nil
        case .down:
            target = context.row + 1 < totalCount ? (context.row + 1, context.column) : nil
        case .up:
            target = context.row - 1 >= 0 ? (context.row - 1, context.column) : nil
        }

        guard let target else { return }

        tableView.selectCell(row: target.row, column: target.column)
        tableView.enterEditModeForCell(row: target.row, column: target.column)
    }

    private func reloadCell(row: Int, column: Int) {
        guard row >= 0,
              row < tableView.numberOfRows,
              column >= 0,
              column < tableView.numberOfColumns else {
            return
        }

        tableView.reloadData(
            forRowIndexes: IndexSet(integer: row),
            columnIndexes: IndexSet(integer: column)
        )
    }

    private func activeDisplayCell(row: Int, column: Int) -> TableDisplayCellView? {
        tableView.view(atColumn: column, row: row, makeIfNecessary: false) as? TableDisplayCellView
    }

    private func clearActiveDisplayCellEditingState() {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.location != NSNotFound else { return }

        for row in visibleRows.location..<(visibleRows.location + visibleRows.length) {
            for column in 0..<tableView.numberOfColumns {
                activeDisplayCell(row: row, column: column)?.setEditing(false)
            }
        }
    }
    
    // MARK: - NSMenuDelegate
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        let rightClickLocation = tableView.getRightClickedCell()
        let hasValidRow = rightClickLocation.row >= 0
        let hasValidCell = hasValidRow && rightClickLocation.column >= 0
        let hasData = totalCount > 0
        let hasSelectedRows = !tableView.selectedRowIndexes.isEmpty
        let selectedColumnName = hasValidCell ? tableView.tableColumns[rightClickLocation.column].identifier.rawValue : nil
        let canEditCell = selectedColumnName.map { !isColumnReadOnly($0) } ?? false

        editMenuItem?.isEnabled = canEditCell
        deleteMenuItem?.isEnabled = hasValidRow && hasData && !isReadOnly
        addRowMenuItem?.isEnabled = !isReadOnly
        refreshMenuItem?.isEnabled = true
        quickLookMenuItem?.isEnabled = hasValidCell
        copyMenuItem?.isEnabled = hasSelectedRows && hasData
        copyRowsAsMenuItem?.isEnabled = hasSelectedRows && hasData
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        menuNeedsUpdate(menu)
    }

    // MARK: - Row Selection

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow

        Task { @MainActor [weak self] in
            guard let self else { return }

            if selectedRow >= 0, let queryResult = self.queryResult, selectedRow < queryResult.rows.count {
                let rowData = queryResult.rows[selectedRow]
                self.onRowSelected?(rowData)
                self.currentTab?.selectedRowIndex = selectedRow
                self.currentTab?.selectedColumnOrder = queryResult.columns.map { $0.name }
                if selectedRow < queryResult.rawRows.count {
                    self.currentTab?.selectedRawRowData = queryResult.rawRows[selectedRow]
                }
            } else {
                self.onRowSelected?(nil)
                self.currentTab?.selectedRowIndex = nil
                self.currentTab?.selectedColumnOrder = nil
                self.currentTab?.selectedRawRowData = nil
            }
        }
    }
}
