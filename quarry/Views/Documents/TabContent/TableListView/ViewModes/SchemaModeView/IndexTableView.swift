//
//  IndexTableView.swift
//  Quarry
//
//  Created by Fauzaan on 10/20/25.
//

import SwiftUI
import Foundation
import AppKit

struct IndexTableView: View {
    let indexes: [DatabaseIndexInfo]?
    let tableName: String
    let searchText: String
    let databaseType: DatabaseType
    @Binding var modificationTracker: SchemaModificationTracker
    @Environment(\.colorScheme) var colorScheme

    // This computed property forces SwiftUI to observe tracker changes
    private var trackerVersion: Bool {
        modificationTracker.hasModifications
    }

    var body: some View {
        // Access trackerVersion to establish SwiftUI observation
        let _ = trackerVersion

        if let indexes = indexes, !indexes.isEmpty {
            IndexTableContentView(
                indexes: filteredIndexes(indexes),
                colorScheme: colorScheme,
                databaseType: databaseType,
                modificationTracker: $modificationTracker
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.5))

                Text("No indexes")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func filteredIndexes(_ indexes: [DatabaseIndexInfo]) -> [DatabaseIndexInfo] {
        if searchText.isEmpty {
            return indexes
        }
        return indexes.filter { index in
            index.name.localizedCaseInsensitiveContains(searchText) ||
            index.columnsDisplay.localizedCaseInsensitiveContains(searchText) ||
            index.indexType.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Index Table Content View
struct IndexTableContentView: NSViewRepresentable {
    let indexes: [DatabaseIndexInfo]
    let colorScheme: ColorScheme
    let databaseType: DatabaseType
    @Binding var modificationTracker: SchemaModificationTracker

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let tableView = CustomTableView()
        tableView.style = .fullWidth
        tableView.rowSizeStyle = .default
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        if TableAppearanceSettings.alternatingRowColors {
            tableView.gridStyleMask = [.solidVerticalGridLineMask]
            tableView.gridColor = .separatorColor
        } else {
            tableView.gridStyleMask = []
        }

        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true

        // Number column
        let numberColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("number"))
        numberColumn.title = "#"
        numberColumn.width = 40
        numberColumn.minWidth = 40
        numberColumn.maxWidth = 60
        numberColumn.headerCell = SchemaTableHeaderCellView(textCell: numberColumn.title)
        numberColumn.headerCell.alignment = .center
        tableView.addTableColumn(numberColumn)

        // Name column
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 150
        nameColumn.headerCell = SchemaTableHeaderCellView(textCell: nameColumn.title)
        tableView.addTableColumn(nameColumn)

        // Type column
        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = "Type"
        typeColumn.headerCell = SchemaTableHeaderCellView(textCell: typeColumn.title)
        tableView.addTableColumn(typeColumn)

        // Columns column
        let columnsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("columns"))
        columnsColumn.title = "Columns"
        columnsColumn.width = 150
        columnsColumn.headerCell = SchemaTableHeaderCellView(textCell: columnsColumn.title)
        tableView.addTableColumn(columnsColumn)

        // Unique column
        let uniqueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("unique"))
        uniqueColumn.title = "Unique"
        uniqueColumn.width = 60
        uniqueColumn.minWidth = 60
        uniqueColumn.headerCell = SchemaTableHeaderCellView(textCell: uniqueColumn.title)
        uniqueColumn.headerCell.alignment = .center
        tableView.addTableColumn(uniqueColumn)

        // Condition column
        let conditionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("condition"))
        conditionColumn.title = "Condition"
        conditionColumn.width = 150
        conditionColumn.headerCell = SchemaTableHeaderCellView(textCell: conditionColumn.title)
        tableView.addTableColumn(conditionColumn)

        // Include column
        let includeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("include"))
        includeColumn.title = "Include"
        includeColumn.width = 150
        includeColumn.headerCell = SchemaTableHeaderCellView(textCell: includeColumn.title)
        tableView.addTableColumn(includeColumn)

        // Comment column
        let commentColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("comment"))
        commentColumn.title = "Comment"
        commentColumn.width = 150
        commentColumn.headerCell = SchemaTableHeaderCellView(textCell: commentColumn.title)
        tableView.addTableColumn(commentColumn)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.setupTableView(tableView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.indexes = indexes
        context.coordinator.colorScheme = colorScheme
        context.coordinator.databaseType = databaseType
        context.coordinator.modificationTracker = modificationTracker

        if let tableView = scrollView.documentView as? NSTableView {
            tableView.reloadData()
        }
    }

    @MainActor
    func makeCoordinator() -> IndexTableCoordinator {
        IndexTableCoordinator(indexes: indexes, colorScheme: colorScheme, databaseType: databaseType, modificationTracker: modificationTracker)
    }
}

// MARK: - Index Table Coordinator
@MainActor
class IndexTableCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
    var indexes: [DatabaseIndexInfo]
    var colorScheme: ColorScheme
    var databaseType: DatabaseType
    weak var tableView: NSTableView?
    weak var modificationTracker: SchemaModificationTracker?

    // Menu item references
    private weak var refreshMenuItem: NSMenuItem?
    private weak var addIndexMenuItem: NSMenuItem?
    private weak var editMenuItem: NSMenuItem?
    private weak var deleteMenuItem: NSMenuItem?

    init(indexes: [DatabaseIndexInfo], colorScheme: ColorScheme, databaseType: DatabaseType, modificationTracker: SchemaModificationTracker? = nil) {
        self.indexes = indexes
        self.colorScheme = colorScheme
        self.databaseType = databaseType
        self.modificationTracker = modificationTracker
        super.init()

        // Add notification observer for delete key requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeleteKey(notification:)),
            name: .didRequestDelete,
            object: nil
        )

        // Add notification observer for table reload requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTableReloadData(notification:)),
            name: .tableReloadData,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setupTableView(_ tableView: NSTableView) {
        self.tableView = tableView
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClick(_:))
        setupMenu(for: tableView)
    }

    private func setupMenu(for tableView: NSTableView) {
        let menu = NSMenu()

        // Refresh
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshTable), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = [.command]
        refreshItem.target = self
        menu.addItem(refreshItem)
        self.refreshMenuItem = refreshItem

        menu.addItem(NSMenuItem.separator())

        // Add Index
        let addIndexItem = NSMenuItem(title: "Add Index", action: #selector(addIndex), keyEquivalent: "")
        addIndexItem.target = self
        menu.addItem(addIndexItem)
        self.addIndexMenuItem = addIndexItem

        // Edit
        let editItem = NSMenuItem(title: "Edit", action: #selector(editIndex), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)
        self.editMenuItem = editItem

        // Delete
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteIndex), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        self.deleteMenuItem = deleteItem

        menu.delegate = self
        menu.autoenablesItems = false
        tableView.menu = menu
    }

    @objc func tableViewDoubleClick(_ sender: AnyObject) {
        guard let tableView = tableView else { return }

        let clickedRow = tableView.clickedRow
        let clickedColumn = tableView.clickedColumn

        guard clickedRow >= 0 && clickedColumn >= 0,
              clickedColumn < tableView.tableColumns.count else { return }

        // Check if this is an editable column
        let identifier = tableView.tableColumns[clickedColumn].identifier

        // Only handle double-click for editable columns (all except number and unique)
        switch identifier.rawValue {
        case "name", "type", "columns", "condition", "include", "comment":
            if let cellView = tableView.view(atColumn: clickedColumn, row: clickedRow, makeIfNecessary: false) as? IndexEditableCellView {
                cellView.enterEditMode()
            }
        default:
            break
        }
    }

    @MainActor @objc private func handleDeleteKey(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rows = userInfo["rows"] as? IndexSet,
              let notificationTableView = userInfo["tableView"] as? NSTableView,
              notificationTableView === self.tableView else {
            return
        }

        for row in rows {
            guard row < indexes.count else { continue }
            let index = indexes[row]

            // Track deletion (handles both new and existing indexes)
            modificationTracker?.trackIndexDeletion(index)

            // Update all cells in this row to show red highlighting
            guard let tableView = tableView else { continue }
            for columnIndex in 0..<tableView.numberOfColumns {
                if let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? IndexDeletableCellView {
                    cellView.isMarkedForDeletion = true
                    cellView.needsDisplay = true
                } else if let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? IndexEditableCellView {
                    cellView.isMarkedForDeletion = true
                    cellView.needsDisplay = true
                } else if let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? IndexCheckboxCellView {
                    cellView.isMarkedForDeletion = true
                    cellView.needsDisplay = true
                } else if let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? IndexDropdownCellView {
                    cellView.isMarkedForDeletion = true
                    cellView.needsDisplay = true
                }
            }
        }

        // Reload data for the affected rows
        if let tableView = tableView {
            tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
        }
    }

    @objc private func handleTableReloadData(notification: Notification) {
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                self?.tableView?.reloadData()
            }
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let tableView = tableView as? CustomTableView else { return }
        let rightClickLocation = tableView.getRightClickedCell()
        let hasValidRow = rightClickLocation.row >= 0
        let hasValidCell = hasValidRow && rightClickLocation.column >= 0

        refreshMenuItem?.isEnabled = true
        addIndexMenuItem?.isEnabled = true
        editMenuItem?.isEnabled = hasValidCell
        deleteMenuItem?.isEnabled = hasValidRow
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuNeedsUpdate(menu)
    }

    // MARK: - Context Menu Actions

    @objc private func refreshTable() {
        NotificationCenter.default.post(name: .indexTableRefresh, object: nil)
    }

    @objc private func addIndex() {
        NotificationCenter.default.post(name: .indexAddIndex, object: nil)
    }

    @objc private func editIndex() {
        guard let tableView = tableView as? CustomTableView else { return }
        let location = tableView.getRightClickedCell()
        guard location.row >= 0, location.column >= 0 else { return }

        tableView.selectRowIndexes(IndexSet(integer: location.row), byExtendingSelection: false)
        if let cellView = tableView.view(atColumn: location.column, row: location.row, makeIfNecessary: false) as? IndexEditableCellView {
            cellView.enterEditMode()
        }
    }

    @objc private func deleteIndex() {
        guard let tableView = tableView else { return }
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        NotificationCenter.default.post(
            name: .didRequestDelete,
            object: self,
            userInfo: ["rows": selectedRows, "tableView": tableView]
        )
    }

    /// Empty rows appended after the data so the alternating-row pattern keeps
    /// going past the last index, matching the data table view.
    private var paddingRowCount: Int { 3 }

    private func isPaddingRow(_ row: Int) -> Bool {
        return row >= indexes.count
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return indexes.count + paddingRowCount
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return SchemaNSTableRowView()
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return !isPaddingRow(row)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if isPaddingRow(row) {
            let emptyView = NSView()
            emptyView.wantsLayer = false
            return emptyView
        }
        let index = indexes[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let isLastColumn = tableColumn == tableView.tableColumns.last

        // Check if this index is marked for deletion or is new
        let isMarkedForDeletion = modificationTracker?.isIndexMarkedForDeletion(index.name) ?? false
        let isNew = modificationTracker?.isIndexNew(index.name) ?? false

        switch identifier.rawValue {
        case "number":
            return makeNumberCell(for: row, in: tableView, isLastColumn: isLastColumn, isMarkedForDeletion: isMarkedForDeletion, isNew: isNew)
        case "name":
            return makeEditableCell(for: index, fieldType: .name, row: row, in: tableView, isLastColumn: isLastColumn)
        case "type":
            return makeDropdownCell(for: index, row: row, in: tableView, isLastColumn: isLastColumn)
        case "columns":
            return makeEditableCell(for: index, fieldType: .columns, row: row, in: tableView, isLastColumn: isLastColumn)
        case "unique":
            return makeCheckboxCell(for: index, row: row, in: tableView, isLastColumn: isLastColumn)
        case "condition":
            return makeEditableCell(for: index, fieldType: .condition, row: row, in: tableView, isLastColumn: isLastColumn)
        case "include":
            return makeEditableCell(for: index, fieldType: .include, row: row, in: tableView, isLastColumn: isLastColumn)
        case "comment":
            return makeEditableCell(for: index, fieldType: .comment, row: row, in: tableView, isLastColumn: isLastColumn)
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 28
    }

    // MARK: - Cell Factories

    private func addCellBorders(to cell: NSView, isLastColumn: Bool = false) {
        // When alternating row colors are on, the table view supplies vertical
        // grid lines and the row stripes supply horizontal separation, so we
        // skip per-cell borders entirely (matches the data table view).
        guard !TableAppearanceSettings.alternatingRowColors else { return }

        if !isLastColumn {
            let rightBorderView = NSView()
            rightBorderView.wantsLayer = true
            rightBorderView.layer?.backgroundColor = NSColor.separatorColor.cgColor
            cell.addSubview(rightBorderView)
            rightBorderView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                rightBorderView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: 0),
                rightBorderView.topAnchor.constraint(equalTo: cell.topAnchor),
                rightBorderView.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                rightBorderView.widthAnchor.constraint(equalToConstant: 1.0)
            ])
        }

        let bottomBorderView = NSView()
        bottomBorderView.wantsLayer = true
        bottomBorderView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        cell.addSubview(bottomBorderView)
        bottomBorderView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomBorderView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
            bottomBorderView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: 0),
            bottomBorderView.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: 0),
            bottomBorderView.heightAnchor.constraint(equalToConstant: 1.0)
        ])
    }

    private func makeNumberCell(for row: Int, in tableView: NSTableView, isLastColumn: Bool, isMarkedForDeletion: Bool = false, isNew: Bool = false) -> NSView {
        let cell = IndexDeletableCellView()
        cell.isMarkedForDeletion = isMarkedForDeletion
        cell.isNew = isNew

        let label = NSTextField(labelWithString: "\(row + 1)")
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        addCellBorders(to: cell, isLastColumn: isLastColumn)
        return cell
    }

    // MARK: - Editable Cell Factories

    /// Creates an editable cell for index fields (name, columns, condition, include, comment)
    private func makeEditableCell(for index: DatabaseIndexInfo, fieldType: IndexFieldType, row: Int, in tableView: NSTableView, isLastColumn: Bool) -> NSView? {
        let cell = IndexEditableCellView(frame: .zero)
        cell.configure(
            index: index,
            fieldType: fieldType,
            rowIndex: row,
            modificationTracker: modificationTracker,
            isLastColumn: isLastColumn
        )
        return cell
    }

    /// Creates a dropdown cell for index type field
    private func makeDropdownCell(for index: DatabaseIndexInfo, row: Int, in tableView: NSTableView, isLastColumn: Bool) -> NSView {
        let cell = IndexDropdownCellView(frame: .zero)
        cell.configure(
            index: index,
            rowIndex: row,
            modificationTracker: modificationTracker,
            databaseType: databaseType,
            isLastColumn: isLastColumn
        )
        return cell
    }

    // MARK: - Generic Cell Factories

    /// Generic text cell factory - reusable for all text-based fields
    private func makeTextCell(text: String?, in tableView: NSTableView, isLastColumn: Bool, isMarkedForDeletion: Bool = false, isNew: Bool = false) -> NSView {
        let cell = IndexDeletableCellView()
        cell.isMarkedForDeletion = isMarkedForDeletion
        cell.isNew = isNew

        let label = NSTextField()
        // Treat empty strings as nil for placeholder display
        let displayText = text?.isEmpty == true ? nil : text
        label.stringValue = displayText ?? ""
        label.placeholderString = "(NULL)"
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        addCellBorders(to: cell, isLastColumn: isLastColumn)
        return cell
    }

    /// Checkbox cell factory for unique field with modification tracking
    private func makeCheckboxCell(for index: DatabaseIndexInfo, row: Int, in tableView: NSTableView, isLastColumn: Bool) -> NSView {
        let cell = IndexCheckboxCellView(frame: .zero)
        cell.configure(
            index: index,
            rowIndex: row,
            modificationTracker: modificationTracker,
            isLastColumn: isLastColumn
        )
        return cell
    }
}

// MARK: - Index Deletable Cell View
class IndexDeletableCellView: NSTableCellView {
    var isMarkedForDeletion: Bool = false {
        didSet { needsDisplay = true }
    }
    var isNew: Bool = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isMarkedForDeletion {
            NSColor.red.withAlphaComponent(0.3).setFill()
            let fillRect = NSRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width - 1, height: bounds.height - 1)
            fillRect.fill()
        } else if isNew {
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let newColor = isDarkMode
                ? NSColor(red: 0x2C/255.0, green: 0x59/255.0, blue: 0x3C/255.0, alpha: 1.0)
                : NSColor(red: 0xC8/255.0, green: 0xE6/255.0, blue: 0xC8/255.0, alpha: 1.0)
            newColor.setFill()
            bounds.fill()
        }
    }
}
