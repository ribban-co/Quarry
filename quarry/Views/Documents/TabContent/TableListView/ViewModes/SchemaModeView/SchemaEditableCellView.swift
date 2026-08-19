//
//  SchemaEditableCellView.swift
//  Quarry
//
//  Created by Claude Code
//

import Foundation
import AppKit

// MARK: - Schema Field Type
enum SchemaFieldType {
    case name
    case type
    case defaultValue
    case nullable
}

// MARK: - Custom NSTextField for Schema Editing
class SchemaEditableTextField: NSTextField {
    weak var cellView: SchemaEditableCellView?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Check for Cmd+Z
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            let undoManager = self.window?.firstResponder?.undoManager

            if let undoManager = undoManager, undoManager.canUndo {
                return super.performKeyEquivalent(with: event)
            } else {
                let _ = cellView?.modificationTracker?.undo()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        debugLog("🚫 cancelOperation triggered (schema cell)")

        guard let cellView = cellView else {
            super.cancelOperation(sender)
            return
        }

        let originalValue = cellView.originalValue

        if abortEditing() {
            debugLog("✅ abortEditing succeeded")

            DispatchQueue.main.async(qos: .userInteractive) { [weak self, weak cellView] in
                guard let self = self, let cellView = cellView else { return }

                self.stringValue = originalValue
                cellView.isModified = false
                cellView.exitEditMode()

                if let tableView = cellView.findTableView() {
                    DispatchQueue.main.async(qos: .userInteractive) {
                        let _ = tableView.window?.makeFirstResponder(tableView)
                    }
                }
            }
        } else {
            debugLog("⚠️ abortEditing failed, falling back to manual exit")

            DispatchQueue.main.async(qos: .userInteractive) { [weak self, weak cellView] in
                guard let self = self, let cellView = cellView else { return }

                self.stringValue = originalValue
                cellView.isModified = false
                cellView.exitEditMode()
            }
        }
    }
}

// MARK: - SchemaEditableCellView
class SchemaEditableCellView: NSView, NSTextFieldDelegate {
    var textField: SchemaEditableTextField!
    private var rightBorderView: NSView?
    private var bottomBorderView: NSView?

    private static weak var currentEditingCell: SchemaEditableCellView?

    /// Returns the currently editing cell, if any
    static func getCurrentEditingCell() -> SchemaEditableCellView? {
        return currentEditingCell
    }

    public var isSelected: Bool = false
    var isMarkedForDeletion: Bool = false {
        didSet {
            needsDisplay = true
        }
    }
    private var isEditing: Bool = false {
        didSet {
            if oldValue != isEditing {
                updateEditingAppearance()

                if isEditing {
                    SchemaEditableCellView.currentEditingCell = self
                } else if SchemaEditableCellView.currentEditingCell === self {
                    SchemaEditableCellView.currentEditingCell = nil
                }
            }
        }
    }

    private var rowIndex: Int = -1
    var fieldType: SchemaFieldType = .name

    weak var modificationTracker: SchemaModificationTracker?
    fileprivate var originalValue: String = ""
    fileprivate var isModified: Bool = false {
        didSet {
            if oldValue != isModified {
                updateModificationAppearance()
            }
        }
    }

    // Store the original column info for modification tracking
    private var originalColumn: DatabaseSchemaInfo?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextField()
    }

    override func prepareForReuse() {
        if isEditing { exitEditMode() }
        isModified = false
        isMarkedForDeletion = false
        if SchemaEditableCellView.currentEditingCell === self {
            SchemaEditableCellView.currentEditingCell = nil
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

    private func setupTextField() {
        textField = SchemaEditableTextField(frame: .zero)
        textField.configureForTableCell()
        textField.delegate = self
        textField.cellView = self

        textField.cell = PaddedTextFieldCell()

        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0)
        ])
    }

    // MARK: - Edit Mode Management

    func enterEditMode() {
        debugLog("Entering edit mode for schema cell at row: \(rowIndex), field: \(fieldType)")

        exitEditModeForAllCells()
        enableEditMode()
        window?.makeFirstResponder(textField)

        debugLog("✅ Edit mode entered for schema cell")
    }

    private func enableEditMode() {
        guard !isEditing else { return }

        if let currentEditingCell = SchemaEditableCellView.currentEditingCell, currentEditingCell !== self {
            debugLog("Warning: Another cell is still in edit mode, forcing exit")
            currentEditingCell.exitEditMode()
        }

        if !isModified {
            originalValue = textField.stringValue
            debugLog("📝 Setting fresh originalValue: '\(originalValue)'")
        }

        textField.isEditable = true
        isEditing = true
    }

    fileprivate func exitEditMode() {
        debugLog("Exiting edit mode for schema cell: \(isEditing)")

        guard isEditing else {
            debugLog("⚠️ Cell is not in edit mode, nothing to exit")
            return
        }

        disableEditMode()

        if window?.firstResponder == textField {
            debugLog("🔄 Removing first responder status from text field")
            window?.makeFirstResponder(window)
        }

        handleEditingCompleted()
    }

    private func exitEditModeForAllCells() {
        if let currentEditingCell = SchemaEditableCellView.currentEditingCell, currentEditingCell !== self {
            debugLog("🔄 Exiting edit mode for previous schema cell before entering new one")
            currentEditingCell.exitEditMode()
        }
    }

    fileprivate func disableEditMode() {
        guard isEditing else { return }

        textField.isEditable = false
        isEditing = false
    }

    private func updateEditingAppearance() {
        debugLog("updateEditingAppearance - isEditing: \(isEditing)")
        if isEditing {
            textField.backgroundColor = NSColor.clear
            textField.drawsBackground = true
        } else {
            textField.backgroundColor = NSColor.clear
            textField.drawsBackground = false
        }

        updateModificationAppearance()
    }

    private func updateModificationAppearance() {
        if !wantsLayer {
            wantsLayer = true
        }

        if isModified {
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let modificationColor = isDarkMode
                ? NSColor(red: 0x7C/255.0, green: 0x59/255.0, blue: 0x2C/255.0, alpha: 1.0)
                : NSColor(red: 0xFF/255.0, green: 0xE5/255.0, blue: 0x99/255.0, alpha: 1.0)
            layer?.backgroundColor = modificationColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func updateNewColumnAppearance() {
        if !wantsLayer {
            wantsLayer = true
        }

        // Green tint for new columns to distinguish from modified existing columns
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let newColumnColor = isDarkMode
            ? NSColor(red: 0x2C/255.0, green: 0x59/255.0, blue: 0x3C/255.0, alpha: 1.0)  // Dark green for dark mode
            : NSColor(red: 0xC8/255.0, green: 0xE6/255.0, blue: 0xC8/255.0, alpha: 1.0)  // Light green for light mode
        layer?.backgroundColor = newColumnColor.cgColor
    }

    fileprivate func handleEditingCompleted() {
        debugLog("Schema cell editing completed with value: \(textField.stringValue)")

        NotificationCenter.default.post(
            name: NSNotification.Name("SchemaCellEditingCompleted"),
            object: self,
            userInfo: [
                "newValue": textField.stringValue,
                "cell": self,
                "wasModified": textField.stringValue != originalValue
            ]
        )
    }

    // MARK: - NSTextFieldDelegate Methods

    /// Handle Tab/Shift-Tab/Enter during editing to prevent default focus movement
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        debugLog("🔍 Command during editing: \(NSStringFromSelector(commandSelector))")

        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            debugLog("🎯 Tab pressed - navigating to next cell")
            handleTabKeyInEditMode()
            return true // We handled it - prevent default Tab behavior

        case #selector(NSResponder.insertBacktab(_:)):
            debugLog("🎯 Shift+Tab pressed - navigating to previous cell")
            handleShiftTabKeyInEditMode()
            return true // We handled it - prevent default Shift+Tab behavior

        case #selector(NSResponder.insertNewline(_:)):
            debugLog("🎯 Enter pressed - exiting edit mode")
            handleEnterKeyInEditMode()
            return true // We handled it - prevent default Enter behavior

        default:
            return false // Let the text view handle other commands
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditing else { return }

        // Tab/Shift-Tab/Enter are handled in control(_:textView:doCommandBy:)
        // This is called for other ways editing can end (e.g., clicking outside)
        saveCurrentChanges()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if !isEditing {
            enterEditMode()
            debugLog("Text editing began - ensuring edit mode is active")
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        let currentValue = textField.stringValue
        let hasChanged = currentValue != originalValue

        if hasChanged != isModified {
            isModified = hasChanged
            debugLog("Schema text field modification state changed: \(isModified)")
        }
    }

    // MARK: - Configuration

    func configure(column: DatabaseSchemaInfo, fieldType: SchemaFieldType, rowIndex: Int, modificationTracker: SchemaModificationTracker?, isLastColumn: Bool = false) {
        self.rowIndex = rowIndex
        self.fieldType = fieldType
        self.modificationTracker = modificationTracker
        self.originalColumn = column

        createBorderViewIfNeeded(isLastColumn: isLastColumn)

        // Check if this column is marked for deletion
        if let tracker = modificationTracker, tracker.isColumnMarkedForDeletion(column.columnName) {
            isMarkedForDeletion = true
        } else {
            isMarkedForDeletion = false
        }

        // Get the appropriate value based on field type
        let value: String
        switch fieldType {
        case .name:
            value = column.columnName
        case .type:
            value = column.dataType
        case .defaultValue:
            value = column.columnDefault ?? ""
        case .nullable:
            value = column.isNullable
        }

        // Check if this is a new column (not yet saved to DB)
        // Use ordinal position for checking since column name may have been edited
        if let tracker = modificationTracker, tracker.isColumnNewByOrdinal(column.ordinalPosition) {
            textField.stringValue = value
            textField.placeholderString = value.isEmpty ? "(NULL)" : ""
            originalValue = value
            isModified = true  // Show as modified (new columns are pending changes)
            updateNewColumnAppearance()
        }
        // Check if this cell has existing modifications
        else if let tracker = modificationTracker,
           let modification = tracker.getColumnModification(for: column.columnName),
           modification.type == .modifyColumn,
           let modifiedColumn = modification.column {

            // Use the modified value and only mark as modified if THIS specific field changed
            switch fieldType {
            case .name:
                textField.stringValue = modifiedColumn.columnName
                isModified = modifiedColumn.columnName != column.columnName
            case .type:
                textField.stringValue = modifiedColumn.dataType
                isModified = modifiedColumn.dataType != column.dataType
            case .defaultValue:
                textField.stringValue = modifiedColumn.columnDefault ?? ""
                isModified = modifiedColumn.columnDefault != column.columnDefault
            case .nullable:
                textField.stringValue = modifiedColumn.isNullable
                isModified = modifiedColumn.isNullable != column.isNullable
            }

            textField.placeholderString = textField.stringValue.isEmpty ? "(NULL)" : ""
            originalValue = value
            updateModificationAppearance()
        } else {
            textField.stringValue = value
            textField.placeholderString = value.isEmpty ? "(NULL)" : ""
            isModified = false
            updateModificationAppearance()
        }
    }

    private func createBorderViewIfNeeded(isLastColumn: Bool) {
        if rightBorderView == nil || bottomBorderView == nil {
            createBorderView(isLastColumn: isLastColumn)
        }
    }

    private func createBorderView(isLastColumn: Bool) {
        // When alternating row colors are on, the table view supplies vertical
        // grid lines and the row stripes supply horizontal separation, so we
        // hide per-cell borders (matches the data table view's TextCellView).
        let alternatingRowsEnabled = TableAppearanceSettings.alternatingRowColors

        // Right border (skip for last column)
        if !isLastColumn {
            rightBorderView = NSView()
            rightBorderView?.wantsLayer = true
            rightBorderView?.layer?.backgroundColor = NSColor.separatorColor.cgColor
            rightBorderView?.isHidden = alternatingRowsEnabled

            addSubview(rightBorderView!)
            rightBorderView?.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                rightBorderView!.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
                rightBorderView!.topAnchor.constraint(equalTo: topAnchor),
                rightBorderView!.bottomAnchor.constraint(equalTo: bottomAnchor),
                rightBorderView!.widthAnchor.constraint(equalToConstant: 1.0)
            ])
        }

        // Bottom border
        bottomBorderView = NSView()
        bottomBorderView?.wantsLayer = true
        bottomBorderView?.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bottomBorderView?.isHidden = alternatingRowsEnabled

        addSubview(bottomBorderView!)
        bottomBorderView?.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomBorderView!.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            bottomBorderView!.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            bottomBorderView!.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
            bottomBorderView!.heightAnchor.constraint(equalToConstant: 1.0)
        ])
    }

    // MARK: - Helper Methods

    func findTableView() -> NSTableView? {
        var view: NSView? = self.superview
        while view != nil {
            if let tableView = view as? NSTableView {
                return tableView
            }
            view = view?.superview
        }
        return nil
    }

    private func saveCurrentChanges() {
        guard let tracker = modificationTracker,
              let originalColumn = originalColumn,
              rowIndex >= 0 else { return }

        let finalValue = textField.stringValue
        if finalValue != originalValue {
            // Create a modified column with the new value
            let modifiedColumn: DatabaseSchemaInfo

            switch fieldType {
            case .name:
                modifiedColumn = DatabaseSchemaInfo(
                    ordinalPosition: originalColumn.ordinalPosition,
                    columnName: finalValue,
                    dataType: originalColumn.dataType,
                    formatType: originalColumn.formatType,
                    typeOid: originalColumn.typeOid,
                    numericPrecision: originalColumn.numericPrecision,
                    datetimePrecision: originalColumn.datetimePrecision,
                    numericScale: originalColumn.numericScale,
                    dataLength: originalColumn.dataLength,
                    isNullable: originalColumn.isNullable,
                    check: originalColumn.check,
                    checkConstraint: originalColumn.checkConstraint,
                    columnDefault: originalColumn.columnDefault,
                    foreignKey: originalColumn.foreignKey,
                    constraints: originalColumn.constraints,
                    comment: originalColumn.comment,
                    isReadOnly: originalColumn.isReadOnly
                )
            case .type:
                modifiedColumn = DatabaseSchemaInfo(
                    ordinalPosition: originalColumn.ordinalPosition,
                    columnName: originalColumn.columnName,
                    dataType: finalValue,
                    formatType: originalColumn.formatType,
                    typeOid: originalColumn.typeOid,
                    numericPrecision: originalColumn.numericPrecision,
                    datetimePrecision: originalColumn.datetimePrecision,
                    numericScale: originalColumn.numericScale,
                    dataLength: originalColumn.dataLength,
                    isNullable: originalColumn.isNullable,
                    check: originalColumn.check,
                    checkConstraint: originalColumn.checkConstraint,
                    columnDefault: originalColumn.columnDefault,
                    foreignKey: originalColumn.foreignKey,
                    constraints: originalColumn.constraints,
                    comment: originalColumn.comment,
                    isReadOnly: originalColumn.isReadOnly
                )
            case .defaultValue:
                modifiedColumn = DatabaseSchemaInfo(
                    ordinalPosition: originalColumn.ordinalPosition,
                    columnName: originalColumn.columnName,
                    dataType: originalColumn.dataType,
                    formatType: originalColumn.formatType,
                    typeOid: originalColumn.typeOid,
                    numericPrecision: originalColumn.numericPrecision,
                    datetimePrecision: originalColumn.datetimePrecision,
                    numericScale: originalColumn.numericScale,
                    dataLength: originalColumn.dataLength,
                    isNullable: originalColumn.isNullable,
                    check: originalColumn.check,
                    checkConstraint: originalColumn.checkConstraint,
                    columnDefault: finalValue.isEmpty ? nil : finalValue,
                    foreignKey: originalColumn.foreignKey,
                    constraints: originalColumn.constraints,
                    comment: originalColumn.comment,
                    isReadOnly: originalColumn.isReadOnly
                )
            case .nullable:
                modifiedColumn = DatabaseSchemaInfo(
                    ordinalPosition: originalColumn.ordinalPosition,
                    columnName: originalColumn.columnName,
                    dataType: originalColumn.dataType,
                    formatType: originalColumn.formatType,
                    typeOid: originalColumn.typeOid,
                    numericPrecision: originalColumn.numericPrecision,
                    datetimePrecision: originalColumn.datetimePrecision,
                    numericScale: originalColumn.numericScale,
                    dataLength: originalColumn.dataLength,
                    isNullable: finalValue,
                    check: originalColumn.check,
                    checkConstraint: originalColumn.checkConstraint,
                    columnDefault: originalColumn.columnDefault,
                    foreignKey: originalColumn.foreignKey,
                    constraints: originalColumn.constraints,
                    comment: originalColumn.comment,
                    isReadOnly: originalColumn.isReadOnly
                )
            }

            // Handle new columns differently - update the addition instead of creating a modification
            // Use ordinal position for checking since column name may have changed
            let isNewColumn = tracker.isColumnNewByOrdinal(originalColumn.ordinalPosition)
            if isNewColumn {
                // Get the current name in the tracker (may differ from originalColumn.columnName if name was edited)
                let currentTrackerName = tracker.getNewColumnName(byOrdinal: originalColumn.ordinalPosition) ?? originalColumn.columnName
                tracker.updateColumnAddition(originalName: currentTrackerName, updatedColumn: modifiedColumn)
                // Update our stored originalColumn to reflect the new values for subsequent edits
                self.originalColumn = modifiedColumn
                debugLog("📝 New column updated: \(fieldType), \(originalValue) → \(finalValue)")
            } else {
                tracker.trackColumnModification(original: originalColumn, modified: modifiedColumn)
                debugLog("📝 Schema cell modification tracked: \(fieldType), \(originalValue) → \(finalValue)")
            }
        } else {
            // Value was reverted - check if we should remove the modification
            // For new columns (by ordinal), don't try to remove - they should stay as additions
            // For existing columns, remove the modification if value reverted
            let isNewColumn = tracker.isColumnNewByOrdinal(originalColumn.ordinalPosition)
            if !isNewColumn {
                tracker.removeColumnModification(for: originalColumn.columnName)
                debugLog("🔄 Schema cell reverted to original: \(fieldType)")
            }
        }
    }

    // MARK: - Navigation Handlers

    private func handleTabKeyInEditMode() {
        debugLog("🔄 Handling Tab key - navigating to next cell")
        saveCurrentChanges()
        navigateToCell(direction: .next)
    }

    private func handleShiftTabKeyInEditMode() {
        debugLog("🔄 Handling Shift+Tab key - navigating to previous cell")
        saveCurrentChanges()
        navigateToCell(direction: .previous)
    }

    private func handleEnterKeyInEditMode() {
        debugLog("🔄 Handling Enter key")
        saveCurrentChanges()
        exitEditMode()
    }

    private enum NavigationDirection {
        case next, previous
    }

    private func navigateToCell(direction: NavigationDirection) {
        guard let tableView = findTableView() as? CustomTableView else {
            debugLog("❌ Could not find CustomTableView")
            exitEditMode()
            return
        }

        let currentRow = tableView.row(for: self)
        let currentColumn = tableView.column(for: self)

        guard currentRow >= 0 && currentColumn >= 0 else {
            debugLog("❌ Invalid current position")
            return
        }

        var nextColumn = currentColumn

        switch direction {
        case .next:
            nextColumn = currentColumn + 1
            if nextColumn >= tableView.numberOfColumns {
                debugLog("At last column - staying in current cell")
                return
            }

        case .previous:
            nextColumn = currentColumn - 1
            if nextColumn < 0 {
                debugLog("At first column - staying in current cell")
                return
            }
        }

        debugLog("🎯 Navigating from (\(currentRow), \(currentColumn)) to (\(currentRow), \(nextColumn))")

        // Exit current edit mode
        exitEditMode()

        // Let CustomTableView handle entering edit mode for the next cell
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            tableView.enterEditModeForCell(row: currentRow, column: nextColumn)
        }
    }

}
