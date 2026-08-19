//
//  IndexEditableCellView.swift
//  Quarry
//
//  Created by Claude Code
//

import Foundation
import AppKit

// MARK: - Index Field Type
enum IndexFieldType {
    case name
    case columns
    case condition
    case include
    case comment
}

// MARK: - Custom NSTextField for Index Editing
class IndexEditableTextField: NSTextField {
    weak var cellView: IndexEditableCellView?

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
        debugLog("cancelOperation triggered (index cell)")

        guard let cellView = cellView else {
            super.cancelOperation(sender)
            return
        }

        let originalValue = cellView.originalValue

        if abortEditing() {
            debugLog("abortEditing succeeded")

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
            debugLog("abortEditing failed, falling back to manual exit")

            DispatchQueue.main.async(qos: .userInteractive) { [weak self, weak cellView] in
                guard let self = self, let cellView = cellView else { return }

                self.stringValue = originalValue
                cellView.isModified = false
                cellView.exitEditMode()
            }
        }
    }
}

// MARK: - IndexEditableCellView
class IndexEditableCellView: NSView, NSTextFieldDelegate {
    var textField: IndexEditableTextField!
    private var rightBorderView: NSView?
    private var bottomBorderView: NSView?

    private static weak var currentEditingCell: IndexEditableCellView?

    /// Returns the currently editing cell, if any
    static func getCurrentEditingCell() -> IndexEditableCellView? {
        return currentEditingCell
    }

    public var isSelected: Bool = false
    var isMarkedForDeletion: Bool = false {
        didSet {
            needsDisplay = true
        }
    }
    var isNew: Bool = false {
        didSet {
            needsDisplay = true
        }
    }
    private var isEditing: Bool = false {
        didSet {
            if oldValue != isEditing {
                updateEditingAppearance()

                if isEditing {
                    IndexEditableCellView.currentEditingCell = self
                } else if IndexEditableCellView.currentEditingCell === self {
                    IndexEditableCellView.currentEditingCell = nil
                }
            }
        }
    }

    private var rowIndex: Int = -1
    var fieldType: IndexFieldType = .name

    weak var modificationTracker: SchemaModificationTracker?
    fileprivate var originalValue: String = ""
    fileprivate var isModified: Bool = false {
        didSet {
            if oldValue != isModified {
                updateModificationAppearance()
            }
        }
    }

    // Store the original index info for modification tracking
    private var originalIndex: DatabaseIndexInfo?

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
        isNew = false
        if IndexEditableCellView.currentEditingCell === self {
            IndexEditableCellView.currentEditingCell = nil
        }
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

    private func setupTextField() {
        textField = IndexEditableTextField(frame: .zero)
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
        debugLog("Entering edit mode for index cell at row: \(rowIndex), field: \(fieldType)")

        exitEditModeForAllCells()
        enableEditMode()
        window?.makeFirstResponder(textField)

        debugLog("Edit mode entered for index cell")
    }

    private func enableEditMode() {
        guard !isEditing else { return }

        if let currentEditingCell = IndexEditableCellView.currentEditingCell, currentEditingCell !== self {
            debugLog("Warning: Another cell is still in edit mode, forcing exit")
            currentEditingCell.exitEditMode()
        }

        if !isModified {
            originalValue = textField.stringValue
            debugLog("Setting fresh originalValue: '\(originalValue)'")
        }

        textField.isEditable = true
        isEditing = true
    }

    fileprivate func exitEditMode() {
        debugLog("Exiting edit mode for index cell: \(isEditing)")

        guard isEditing else {
            debugLog("Cell is not in edit mode, nothing to exit")
            return
        }

        disableEditMode()

        if window?.firstResponder == textField {
            debugLog("Removing first responder status from text field")
            window?.makeFirstResponder(window)
        }

        handleEditingCompleted()
    }

    private func exitEditModeForAllCells() {
        if let currentEditingCell = IndexEditableCellView.currentEditingCell, currentEditingCell !== self {
            debugLog("Exiting edit mode for previous index cell before entering new one")
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

        if isModified && !isNew {
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let modificationColor = isDarkMode
                ? NSColor(red: 0x7C/255.0, green: 0x59/255.0, blue: 0x2C/255.0, alpha: 1.0)
                : NSColor(red: 0xFF/255.0, green: 0xE5/255.0, blue: 0x99/255.0, alpha: 1.0)
            layer?.backgroundColor = modificationColor.cgColor
        } else if isNew {
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let newColor = isDarkMode
                ? NSColor(red: 0x2C/255.0, green: 0x59/255.0, blue: 0x3C/255.0, alpha: 1.0)
                : NSColor(red: 0xC8/255.0, green: 0xE6/255.0, blue: 0xC8/255.0, alpha: 1.0)
            layer?.backgroundColor = newColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    fileprivate func handleEditingCompleted() {
        debugLog("Index cell editing completed with value: \(textField.stringValue)")

        NotificationCenter.default.post(
            name: NSNotification.Name("IndexCellEditingCompleted"),
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
        debugLog("Command during editing: \(NSStringFromSelector(commandSelector))")

        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            debugLog("Tab pressed - navigating to next cell")
            handleTabKeyInEditMode()
            return true

        case #selector(NSResponder.insertBacktab(_:)):
            debugLog("Shift+Tab pressed - navigating to previous cell")
            handleShiftTabKeyInEditMode()
            return true

        case #selector(NSResponder.insertNewline(_:)):
            debugLog("Enter pressed - exiting edit mode")
            handleEnterKeyInEditMode()
            return true

        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditing else { return }
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
            debugLog("Index text field modification state changed: \(isModified)")
        }
    }

    // MARK: - Configuration

    func configure(index: DatabaseIndexInfo, fieldType: IndexFieldType, rowIndex: Int, modificationTracker: SchemaModificationTracker?, isLastColumn: Bool = false) {
        self.rowIndex = rowIndex
        self.fieldType = fieldType
        self.modificationTracker = modificationTracker
        self.originalIndex = index

        createBorderViewIfNeeded(isLastColumn: isLastColumn)

        // Check if this index is marked for deletion
        if let tracker = modificationTracker, tracker.isIndexMarkedForDeletion(index.name) {
            isMarkedForDeletion = true
        } else {
            isMarkedForDeletion = false
        }

        // Check if this is a new index
        if let tracker = modificationTracker, tracker.isIndexNew(index.name) {
            isNew = true
        } else {
            isNew = false
        }

        // Get the appropriate value based on field type
        let value: String
        switch fieldType {
        case .name:
            value = index.name
        case .columns:
            value = index.columnsDisplay
        case .condition:
            value = index.condition ?? ""
        case .include:
            value = index.includeColumnsDisplay ?? ""
        case .comment:
            value = index.comment ?? ""
        }

        // Check if this index has existing modifications
        if let tracker = modificationTracker,
           let modification = tracker.getIndexModification(for: index.name),
           modification.type == .modifyIndex,
           let modifiedIndex = modification.index {

            // Use the modified value and only mark as modified if THIS specific field changed
            switch fieldType {
            case .name:
                textField.stringValue = modifiedIndex.name
                isModified = modifiedIndex.name != index.name
            case .columns:
                textField.stringValue = modifiedIndex.columnsDisplay
                isModified = modifiedIndex.columns != index.columns
            case .condition:
                textField.stringValue = modifiedIndex.condition ?? ""
                isModified = modifiedIndex.condition != index.condition
            case .include:
                textField.stringValue = modifiedIndex.includeColumnsDisplay ?? ""
                isModified = modifiedIndex.includeColumns != index.includeColumns
            case .comment:
                textField.stringValue = modifiedIndex.comment ?? ""
                isModified = modifiedIndex.comment != index.comment
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
              let originalIndex = originalIndex,
              rowIndex >= 0 else { return }

        let finalValue = textField.stringValue
        if finalValue != originalValue {
            // Create a modified index with the new value
            let modifiedIndex: DatabaseIndexInfo

            switch fieldType {
            case .name:
                modifiedIndex = DatabaseIndexInfo(
                    name: finalValue,
                    tableName: originalIndex.tableName,
                    schemaName: originalIndex.schemaName,
                    columns: originalIndex.columns,
                    indexType: originalIndex.indexType,
                    isUnique: originalIndex.isUnique,
                    isPrimaryKey: originalIndex.isPrimaryKey,
                    definition: originalIndex.definition,
                    condition: originalIndex.condition,
                    includeColumns: originalIndex.includeColumns,
                    comment: originalIndex.comment
                )
            case .columns:
                // Parse comma-separated column names
                let newColumns = finalValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                modifiedIndex = DatabaseIndexInfo(
                    name: originalIndex.name,
                    tableName: originalIndex.tableName,
                    schemaName: originalIndex.schemaName,
                    columns: newColumns,
                    indexType: originalIndex.indexType,
                    isUnique: originalIndex.isUnique,
                    isPrimaryKey: originalIndex.isPrimaryKey,
                    definition: originalIndex.definition,
                    condition: originalIndex.condition,
                    includeColumns: originalIndex.includeColumns,
                    comment: originalIndex.comment
                )
            case .condition:
                modifiedIndex = DatabaseIndexInfo(
                    name: originalIndex.name,
                    tableName: originalIndex.tableName,
                    schemaName: originalIndex.schemaName,
                    columns: originalIndex.columns,
                    indexType: originalIndex.indexType,
                    isUnique: originalIndex.isUnique,
                    isPrimaryKey: originalIndex.isPrimaryKey,
                    definition: originalIndex.definition,
                    condition: finalValue.isEmpty ? nil : finalValue,
                    includeColumns: originalIndex.includeColumns,
                    comment: originalIndex.comment
                )
            case .include:
                // Parse comma-separated include column names
                let newIncludeColumns = finalValue.isEmpty ? nil : finalValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                modifiedIndex = DatabaseIndexInfo(
                    name: originalIndex.name,
                    tableName: originalIndex.tableName,
                    schemaName: originalIndex.schemaName,
                    columns: originalIndex.columns,
                    indexType: originalIndex.indexType,
                    isUnique: originalIndex.isUnique,
                    isPrimaryKey: originalIndex.isPrimaryKey,
                    definition: originalIndex.definition,
                    condition: originalIndex.condition,
                    includeColumns: newIncludeColumns,
                    comment: originalIndex.comment
                )
            case .comment:
                modifiedIndex = DatabaseIndexInfo(
                    name: originalIndex.name,
                    tableName: originalIndex.tableName,
                    schemaName: originalIndex.schemaName,
                    columns: originalIndex.columns,
                    indexType: originalIndex.indexType,
                    isUnique: originalIndex.isUnique,
                    isPrimaryKey: originalIndex.isPrimaryKey,
                    definition: originalIndex.definition,
                    condition: originalIndex.condition,
                    includeColumns: originalIndex.includeColumns,
                    comment: finalValue.isEmpty ? nil : finalValue
                )
            }

            // Handle new indexes differently - update the addition instead of creating a modification
            if isNew {
                tracker.updateIndexAddition(originalName: originalIndex.name, updatedIndex: modifiedIndex)
                // Update our stored originalIndex to reflect the new values for subsequent edits
                self.originalIndex = modifiedIndex
                debugLog("New index updated: \(fieldType), \(originalValue) -> \(finalValue)")
            } else {
                tracker.trackIndexModification(original: originalIndex, modified: modifiedIndex)
                debugLog("Index cell modification tracked: \(fieldType), \(originalValue) -> \(finalValue)")
            }
        } else {
            // Value was reverted - check if we should remove the modification
            // For new indexes, don't try to remove - they should stay as additions
            if !isNew {
                tracker.removeIndexModification(for: originalIndex.name)
                debugLog("Index cell reverted to original: \(fieldType)")
            }
        }
    }

    // MARK: - Navigation Handlers

    private func handleTabKeyInEditMode() {
        debugLog("Handling Tab key - navigating to next cell")
        saveCurrentChanges()
        navigateToCell(direction: .next)
    }

    private func handleShiftTabKeyInEditMode() {
        debugLog("Handling Shift+Tab key - navigating to previous cell")
        saveCurrentChanges()
        navigateToCell(direction: .previous)
    }

    private func handleEnterKeyInEditMode() {
        debugLog("Handling Enter key")
        saveCurrentChanges()
        exitEditMode()
    }

    private enum NavigationDirection {
        case next, previous
    }

    private func navigateToCell(direction: NavigationDirection) {
        guard let tableView = findTableView() as? CustomTableView else {
            debugLog("Could not find CustomTableView")
            exitEditMode()
            return
        }

        let currentRow = tableView.row(for: self)
        let currentColumn = tableView.column(for: self)

        guard currentRow >= 0 && currentColumn >= 0 else {
            debugLog("Invalid current position")
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

        debugLog("Navigating from (\(currentRow), \(currentColumn)) to (\(currentRow), \(nextColumn))")

        // Exit current edit mode
        exitEditMode()

        // Let CustomTableView handle entering edit mode for the next cell
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            tableView.enterEditModeForCell(row: currentRow, column: nextColumn)
        }
    }
}
