//
//  SchemaTableCoordinator.swift
//  Quarry
//
//  Created by Fauzaan on 10/18/25.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
class SchemaTableCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
    var columns: [DatabaseSchemaInfo]
    var colorScheme: ColorScheme
    var databaseType: DatabaseType
    weak var tableView: NSTableView?
    weak var modificationTracker: SchemaModificationTracker?

    // Menu item references
    private weak var refreshMenuItem: NSMenuItem?
    private weak var addColumnMenuItem: NSMenuItem?
    private weak var editMenuItem: NSMenuItem?
    private weak var deleteMenuItem: NSMenuItem?

    init(columns: [DatabaseSchemaInfo], colorScheme: ColorScheme, databaseType: DatabaseType, modificationTracker: SchemaModificationTracker? = nil) {
        self.columns = columns
        self.colorScheme = colorScheme
        self.databaseType = databaseType
        self.modificationTracker = modificationTracker
        super.init()

        // Add notification observer for table reload requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTableReloadData(notification:)),
            name: .tableReloadData,
            object: nil
        )

        // Add notification observer for delete key requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeleteKey(notification:)),
            name: .didRequestDelete,
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

        // Add Column
        let addColumnItem = NSMenuItem(title: "Add Column", action: #selector(addColumn), keyEquivalent: "")
        addColumnItem.target = self
        menu.addItem(addColumnItem)
        self.addColumnMenuItem = addColumnItem

        // Edit
        let editItem = NSMenuItem(title: "Edit", action: #selector(editColumn), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)
        self.editMenuItem = editItem

        // Delete
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteColumn), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        self.deleteMenuItem = deleteItem

        menu.delegate = self
        menu.autoenablesItems = false
        tableView.menu = menu
    }

    @objc private func handleTableReloadData(notification: Notification) {
        let autoEditLastRow = (notification.userInfo?["autoEditLastRow"] as? Bool) ?? false

        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let tableView = self.tableView else { return }
                tableView.reloadData()

                // Auto-edit the name cell of the last row if requested.
                // Use tableView.numberOfRows instead of columns.count since columns may not be updated yet.
                if autoEditLastRow && tableView.numberOfRows > 0 {
                    self.scrollToLastRowAndEditNameCell()
                }
            }
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
            guard row < columns.count else { continue }
            let column = columns[row]

            // Track deletion (handles both new and existing columns)
            modificationTracker?.trackColumnDeletion(column)

            // Update all cells in this row to show red highlighting
            guard let tableView = tableView else { continue }
            for columnIndex in 0..<tableView.numberOfColumns {
                if let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? SchemaEditableCellView {
                    cellView.isMarkedForDeletion = true
                    cellView.needsDisplay = true
                } else if let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? SchemaCheckboxCellView {
                    cellView.isMarkedForDeletion = true
                    cellView.needsDisplay = true
                } else if let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? SchemaDropdownCellView {
                    cellView.isMarkedForDeletion = true
                    cellView.needsDisplay = true
                } else if let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? SchemaDeletableCellView {
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

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let tableView = tableView as? CustomTableView else { return }
        let rightClickLocation = tableView.getRightClickedCell()
        let hasValidRow = rightClickLocation.row >= 0
        let hasValidCell = hasValidRow && rightClickLocation.column >= 0

        refreshMenuItem?.isEnabled = true
        addColumnMenuItem?.isEnabled = true
        editMenuItem?.isEnabled = hasValidCell
        deleteMenuItem?.isEnabled = hasValidRow
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuNeedsUpdate(menu)
    }

    // MARK: - Context Menu Actions

    @objc private func refreshTable() {
        NotificationCenter.default.post(name: .schemaTableRefresh, object: nil)
    }

    @objc private func addColumn() {
        NotificationCenter.default.post(name: .schemaAddColumn, object: nil)
    }

    @objc private func editColumn() {
        guard let tableView = tableView as? CustomTableView else { return }
        let location = tableView.getRightClickedCell()
        guard location.row >= 0, location.column >= 0 else { return }

        tableView.selectRowIndexes(IndexSet(integer: location.row), byExtendingSelection: false)
        if let cellView = tableView.view(atColumn: location.column, row: location.row, makeIfNecessary: false) as? SchemaEditableCellView {
            cellView.enterEditMode()
        }
    }

    @objc private func deleteColumn() {
        guard let tableView = tableView else { return }
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        NotificationCenter.default.post(
            name: .didRequestDelete,
            object: self,
            userInfo: ["rows": selectedRows, "tableView": tableView]
        )
    }

    /// Scrolls to the last row and enters edit mode on the name cell
    private func scrollToLastRowAndEditNameCell() {
        guard let tableView = tableView else { return }

        // Last *real* row, skipping padding rows we add to extend the
        // alternating-color pattern past the data.
        let lastRowIndex = tableView.numberOfRows - paddingRowCount - 1
        guard lastRowIndex >= 0 else { return }

        tableView.scrollRowToVisible(lastRowIndex)
        tableView.selectRowIndexes(IndexSet(integer: lastRowIndex), byExtendingSelection: false)

        // Find the "name" column index (should be column 1 after the # column)
        guard let nameColumnIndex = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }) else {
            return
        }

        // Delay slightly to ensure the view is created
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let tableView = self?.tableView else { return }
                if let nameCell = tableView.view(atColumn: nameColumnIndex, row: lastRowIndex, makeIfNecessary: true) as? SchemaEditableCellView {
                    nameCell.enterEditMode()
                }
            }
        }
    }

    @objc func tableViewDoubleClick(_ sender: AnyObject) {
        guard let tableView = tableView else { return }

        let clickedRow = tableView.clickedRow
        let clickedColumn = tableView.clickedColumn

        guard clickedRow >= 0 && clickedColumn >= 0,
              clickedColumn < tableView.tableColumns.count else { return }

        // Check if this is an editable column
        let identifier = tableView.tableColumns[clickedColumn].identifier

        // Only handle double-click for editable text columns
        switch identifier.rawValue {
        case "name", "default":
            if let cellView = tableView.view(atColumn: clickedColumn, row: clickedRow, makeIfNecessary: false) as? SchemaEditableCellView {
                cellView.enterEditMode()
            }
        default:
            break
        }
    }

    // MARK: - Data Source

    /// Empty rows appended after the data so the alternating-row pattern keeps
    /// going past the last column, matching the data table view.
    private var paddingRowCount: Int { 3 }

    private func isPaddingRow(_ row: Int) -> Bool {
        return row >= columns.count
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return columns.count + paddingRowCount
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
        let column = columns[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")

        // Check if this is the last column
        let isLastColumn = tableColumn == tableView.tableColumns.last

        // Check if this column is marked for deletion
        let isMarkedForDeletion = modificationTracker?.isColumnMarkedForDeletion(column.columnName) ?? false

        switch identifier.rawValue {
        case "number":
            return makeNumberCell(for: row, in: tableView, isLastColumn: isLastColumn, isMarkedForDeletion: isMarkedForDeletion)
        case "name":
            return makeEditableCell(for: column, fieldType: .name, row: row, in: tableView, isLastColumn: isLastColumn)
        case "type":
            return makeDropdownCell(for: column, row: row, in: tableView, isLastColumn: isLastColumn)
        case "nullable":
            return makeNullableCell(for: column, row: row, in: tableView, isLastColumn: isLastColumn)
        case "default":
            return makeEditableCell(for: column, fieldType: .defaultValue, row: row, in: tableView, isLastColumn: isLastColumn)
        case "constraints":
            let referenceText: String? = column.hasForeignKey && column.primaryForeignKeyConstraint != nil
                ? formatForeignKeyReference(column.primaryForeignKeyConstraint!)
                : nil
            return makeTextCell(text: referenceText, in: tableView, isLastColumn: isLastColumn, isMarkedForDeletion: isMarkedForDeletion)
        default:
            return nil
        }
    }

    // MARK: - Delegate
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 28
    }

    // MARK: - Cell Factories
    private func addCellBorders(to cell: NSView, isLastColumn: Bool = false) {
        // When alternating row colors are on, the table view supplies vertical
        // grid lines and the row stripes supply horizontal separation, so we
        // skip per-cell borders entirely (matches the data table view).
        guard !TableAppearanceSettings.alternatingRowColors else { return }

        // Right border (skip for last column)
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

    // MARK: - Custom cell types
    private func makeNumberCell(for row: Int, in tableView: NSTableView, isLastColumn: Bool, isMarkedForDeletion: Bool = false) -> NSView {
        let cell = SchemaDeletableCellView()
        cell.isMarkedForDeletion = isMarkedForDeletion

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

    private func makeNameCell(for column: DatabaseSchemaInfo, in tableView: NSTableView, isLastColumn: Bool) -> NSView {
        let cell = NSTableCellView()

        let label = NSTextField(labelWithString: column.columnName)
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
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

    // MARK: - Generic Cell Factories

    /// Generic text cell factory - reusable for all text-based fields
    private func makeTextCell(text: String?, in tableView: NSTableView, isLastColumn: Bool, isMarkedForDeletion: Bool = false) -> NSView {
        let cell = SchemaDeletableCellView()
        cell.isMarkedForDeletion = isMarkedForDeletion

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

    /// Generic checkbox cell factory - reusable for all boolean fields
    private func makeCheckboxCell(isChecked: Bool, in tableView: NSTableView, isLastColumn: Bool) -> NSView {
        let cell = NSTableCellView()

        let icon = NSImageView()
        let symbolName = isChecked ? "checkmark.square.fill" : "square"
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.contentTintColor = .controlTextColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])

        addCellBorders(to: cell, isLastColumn: isLastColumn)
        return cell
    }

    // Helper method to format the foreign key reference
    private func formatForeignKeyReference(_ constraint: ConstraintInfo) -> String {
        guard let refTable = constraint.referencedTable else {
            return ""
        }

        // Build schema.table if schema exists
        var reference = ""
        if let refSchema = constraint.referencedSchema, !refSchema.isEmpty {
            reference = "\(refSchema).\(refTable)"
        } else {
            reference = refTable
        }

        // Add column if available
        if let refColumn = constraint.referencedColumns?.first, !refColumn.isEmpty {
            reference += "(\(refColumn))"
        }

        return reference
    }

    // MARK: - Editable Cell Factories

    /// Creates an editable cell for schema fields (name, default)
    private func makeEditableCell(for column: DatabaseSchemaInfo, fieldType: SchemaFieldType, row: Int, in tableView: NSTableView, isLastColumn: Bool) -> NSView? {
        let cell = SchemaEditableCellView(frame: .zero)
        cell.configure(
            column: column,
            fieldType: fieldType,
            rowIndex: row,
            modificationTracker: modificationTracker,
            isLastColumn: isLastColumn
        )
        return cell
    }

    /// Creates a dropdown cell for the type field
    private func makeDropdownCell(for column: DatabaseSchemaInfo, row: Int, in tableView: NSTableView, isLastColumn: Bool) -> NSView {
        let cell = SchemaDropdownCellView(frame: .zero)
        cell.configure(
            column: column,
            rowIndex: row,
            modificationTracker: modificationTracker,
            databaseType: databaseType,
            isLastColumn: isLastColumn
        )
        return cell
    }

    /// Creates a clickable checkbox cell for the nullable field with modification tracking
    private func makeNullableCell(for column: DatabaseSchemaInfo, row: Int, in tableView: NSTableView, isLastColumn: Bool) -> NSView {
        let cell = SchemaCheckboxCellView(frame: .zero)
        cell.configure(
            column: column,
            rowIndex: row,
            modificationTracker: modificationTracker,
            isLastColumn: isLastColumn
        )
        return cell
    }
}

// MARK: - Custom Row styling
class SchemaNSTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }  // Always return false to prevent text color changes
        set {
            // Don't call super to prevent the emphasized state from changing
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        TableAppearanceSettings.initialize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        TableAppearanceSettings.initialize()
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isSelected && TableAppearanceSettings.alternatingRowColors {
            if let tableView = superview as? NSTableView {
                let rowIndex = tableView.row(for: self)
                if rowIndex % 2 == 1 {
                    NSColor.alternatingRowStripeColor.setFill()
                    bounds.fill()
                }
            }
        }

        super.draw(dirtyRect)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        drawFullRowSelection()
    }


    private func drawFullRowSelection() {
        // Subtle row selection color with different colors for light/dark theme
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let customColor = isDarkMode
            ? NSColor.controlColor.withAlphaComponent(0.08)
            : NSColor.controlAccentColor.withAlphaComponent(0.08)
        customColor.setFill()

        // Apply bottom padding to the selection rectangle
        let paddedRect = NSRect(
            x: bounds.origin.x,
            y: bounds.origin.y,
            width: bounds.width,
            height: bounds.height - 1
        )
        paddedRect.fill()
    }
}

// MARK: - Schema table header cell view
class SchemaTableHeaderCellView: NSTableHeaderCell {
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(textCell: String) {
        super.init(textCell: textCell)
    }
    
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        // Create text attributes
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = self.alignment

        let textColor = NSColor.secondaryLabelColor
        let fontWeight: NSFont.Weight = .regular

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: fontWeight),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]

        // Get the proper title rect
        var titleRect = self.titleRect(forBounds: cellFrame)
        titleRect = titleRect.insetBy(dx: 8, dy: 0)

        // Draw the text in the title rect
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        attributedTitle.draw(in: titleRect)
    }
}

// MARK: - Schema deletable cell view for read-only cells with deletion support
class SchemaDeletableCellView: NSTableCellView {
    var isMarkedForDeletion: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isMarkedForDeletion {
            NSColor.red.withAlphaComponent(0.3).setFill()
            let fillRect = NSRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width - 1, height: bounds.height - 1)
            fillRect.fill()
        }
    }
}
