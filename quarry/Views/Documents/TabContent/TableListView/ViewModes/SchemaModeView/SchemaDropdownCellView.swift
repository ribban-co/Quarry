//
//  SchemaDropdownCellView.swift
//  Quarry
//
//  Custom dropdown cell for column type field with modification tracking
//

import Foundation
import AppKit

class SchemaDropdownCellView: NSTableCellView {
    // UI
    private var popupButton: NSPopUpButton!
    private var rightBorderView: NSView?
    private var bottomBorderView: NSView?

    // Database-specific data types
    private static let postgresDataTypes = [
        "bool", "bytea", "char", "date", "float4", "float8",
        "int2", "int4", "int8", "interval", "json", "jsonb",
        "numeric", "text", "time", "timestamp", "timestamptz",
        "timetz", "uuid", "varchar", "xml"
    ]
    private static let mysqlDataTypes = [
        "bigint", "binary", "bit", "blob", "boolean", "char", "date",
        "datetime", "decimal", "double", "enum", "float", "geometry",
        "geometrycollection", "int", "json", "linestring", "longblob",
        "longtext", "mediumblob", "mediumint", "mediumtext",
        "multilinestring", "multipoint", "multipolygon", "point",
        "polygon", "smallint", "text", "time", "timestamp", "tinyblob",
        "tinyint", "tinytext", "varchar(255)", "year"
    ]
    private static let sqliteDataTypes = [
        "INTEGER", "REAL", "TEXT", "BLOB", "NUMERIC"
    ]
    private static let defaultDataTypes = [
        "INTEGER", "TEXT", "REAL", "BLOB"
    ]

    // State tracking
    private var originalValue: String = ""
    private var currentValue: String = ""
    private var originalColumn: DatabaseSchemaInfo?
    private var rowIndex: Int = -1
    private var databaseType: DatabaseType = .postgres
    weak var modificationTracker: SchemaModificationTracker?
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

    private var isModified: Bool {
        return currentValue != originalValue
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupPopupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPopupButton()
    }

    private func setupPopupButton() {
        popupButton = NSPopUpButton(frame: .zero, pullsDown: false)
        popupButton.isBordered = false
        popupButton.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        popupButton.target = self
        popupButton.action = #selector(popupValueChanged(_:))
        popupButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(popupButton)

        NSLayoutConstraint.activate([
            popupButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            popupButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            popupButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func configureMenuItems(for databaseType: DatabaseType, currentType: String) {
        popupButton.removeAllItems()

        let dataTypes: [String]
        switch databaseType {
        case .postgres, .supabase:
            dataTypes = Self.postgresDataTypes
        case .mysql:
            dataTypes = Self.mysqlDataTypes
        case .sqlite:
            dataTypes = Self.sqliteDataTypes
        default:
            dataTypes = Self.defaultDataTypes
        }

        // Add standard data types
        for dataType in dataTypes {
            popupButton.addItem(withTitle: dataType)
        }

        // If current type is not in the list and not empty, add it
        let currentTypeNormalized = normalizeTypeName(currentType)
        let typeExists = dataTypes.contains { normalizeTypeName($0) == currentTypeNormalized }
        if !typeExists && !currentType.isEmpty {
            popupButton.menu?.addItem(NSMenuItem.separator())
            popupButton.addItem(withTitle: currentType)
        }

        // Add separator and manual input option
        popupButton.menu?.addItem(NSMenuItem.separator())
        let manualItem = NSMenuItem(title: "Manual input...", action: #selector(showManualInput), keyEquivalent: "")
        manualItem.target = self
        popupButton.menu?.addItem(manualItem)
    }

    /// Returns the default data type for a database type
    private func defaultDataType(for databaseType: DatabaseType) -> String {
        switch databaseType {
        case .postgres, .supabase:
            return "text"
        case .mysql:
            return "varchar(255)"
        case .sqlite:
            return "TEXT"
        default:
            return "TEXT"
        }
    }

    private func normalizeTypeName(_ type: String) -> String {
        return type.lowercased().trimmingCharacters(in: .whitespaces)
    }

    @objc private func showManualInput() {
        // Create popover
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        // Create content view controller
        let viewController = NSViewController()
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 70))

        // Label
        let label = NSTextField(labelWithString: "Data Type:")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.frame = NSRect(x: 12, y: 42, width: 176, height: 16)
        containerView.addSubview(label)

        // Text field
        let inputTextField = NSTextField(frame: NSRect(x: 12, y: 12, width: 176, height: 24))
        inputTextField.stringValue = currentValue
        inputTextField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        inputTextField.placeholderString = "e.g., varchar(255)"
        containerView.addSubview(inputTextField)

        viewController.view = containerView
        popover.contentViewController = viewController

        // Show popover
        popover.show(relativeTo: popupButton.bounds, of: popupButton, preferredEdge: .minY)

        // Make text field first responder and select all
        inputTextField.window?.makeFirstResponder(inputTextField)
        inputTextField.selectText(nil)

        // Handle Enter key to apply
        inputTextField.target = self
        inputTextField.action = #selector(manualInputFieldAction(_:))

        // Store references for the action handler
        objc_setAssociatedObject(
            inputTextField,
            UnsafeRawPointer(bitPattern: AssociatedKeys.popoverKeyValue)!,
            popover,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private struct AssociatedKeys {
        static let popoverKeyValue = 0x5344_504F
    }

    @objc private func manualInputFieldAction(_ sender: NSTextField) {
        let inputValue = sender.stringValue.trimmingCharacters(in: .whitespaces)

        // Close popover
        if let popover = objc_getAssociatedObject(
            sender,
            UnsafeRawPointer(bitPattern: AssociatedKeys.popoverKeyValue)!
        ) as? NSPopover {
            popover.close()
        }

        if !inputValue.isEmpty {
            currentValue = inputValue

            // Add to menu if not present
            if popupButton.item(withTitle: inputValue) == nil {
                // Insert before the separator
                let separatorIndex = popupButton.menu?.items.firstIndex(where: { $0.isSeparatorItem }) ?? popupButton.numberOfItems
                popupButton.insertItem(withTitle: inputValue, at: separatorIndex)
            }
            popupButton.selectItem(withTitle: inputValue)

            saveCurrentChanges()
            if isNew {
                updateNewColumnAppearance()
            } else {
                updateModificationAppearance()
            }
        } else {
            // Empty input, restore previous selection
            selectDataType(currentValue)
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

    // MARK: - Configuration

    func configure(column: DatabaseSchemaInfo, rowIndex: Int, modificationTracker: SchemaModificationTracker?, databaseType: DatabaseType, isLastColumn: Bool) {
        self.rowIndex = rowIndex
        self.modificationTracker = modificationTracker
        self.originalColumn = column
        self.databaseType = databaseType

        createBorderViewIfNeeded(isLastColumn: isLastColumn)

        // Check if this column is marked for deletion
        if let tracker = modificationTracker, tracker.isColumnMarkedForDeletion(column.columnName) {
            isMarkedForDeletion = true
        } else {
            isMarkedForDeletion = false
        }

        // Check if this is a new column
        if let tracker = modificationTracker, tracker.isColumnNewByOrdinal(column.ordinalPosition) {
            isNew = true
        } else {
            isNew = false
        }

        // Determine the effective data type - use default for new columns with empty type
        let effectiveDataType: String
        if column.dataType.isEmpty && isNew {
            effectiveDataType = defaultDataType(for: databaseType)
        } else {
            effectiveDataType = column.dataType
        }

        // Original value from the column
        self.originalValue = effectiveDataType
        self.currentValue = effectiveDataType

        // Configure menu items based on database type
        configureMenuItems(for: databaseType, currentType: effectiveDataType)

        // Check if this column has existing modifications
        if let tracker = modificationTracker,
           let modification = tracker.getColumnModification(for: column.columnName),
           modification.type == .modifyColumn,
           let modifiedColumn = modification.column {
            // Use the modified value
            self.currentValue = modifiedColumn.dataType
            selectDataType(modifiedColumn.dataType)
            updateModificationAppearance()
        } else {
            selectDataType(effectiveDataType)
            if isNew {
                // For new columns, also update the tracker with the default type
                if column.dataType.isEmpty, let tracker = modificationTracker {
                    let updatedColumn = DatabaseSchemaInfo(
                        ordinalPosition: column.ordinalPosition,
                        columnName: column.columnName,
                        dataType: effectiveDataType,
                        formatType: effectiveDataType,
                        typeOid: column.typeOid,
                        numericPrecision: column.numericPrecision,
                        datetimePrecision: column.datetimePrecision,
                        numericScale: column.numericScale,
                        dataLength: column.dataLength,
                        isNullable: column.isNullable,
                        check: column.check,
                        checkConstraint: column.checkConstraint,
                        columnDefault: column.columnDefault,
                        foreignKey: column.foreignKey,
                        constraints: column.constraints,
                        comment: column.comment,
                        isReadOnly: column.isReadOnly
                    )
                    tracker.updateColumnAddition(originalName: column.columnName, updatedColumn: updatedColumn)
                    self.originalColumn = updatedColumn
                }
                updateNewColumnAppearance()
            } else {
                updateModificationAppearance()
            }
        }
    }

    // MARK: - Selection

    private func selectDataType(_ dataType: String) {
        // Try exact match first
        if popupButton.item(withTitle: dataType) != nil {
            popupButton.selectItem(withTitle: dataType)
            return
        }

        // Try case-insensitive match
        for item in popupButton.itemArray {
            if item.title.lowercased() == dataType.lowercased() {
                popupButton.select(item)
                return
            }
        }

        // If not found, add and select
        let separatorIndex = popupButton.menu?.items.firstIndex(where: { $0.isSeparatorItem }) ?? popupButton.numberOfItems
        popupButton.insertItem(withTitle: dataType, at: separatorIndex)
        popupButton.selectItem(withTitle: dataType)
    }

    // MARK: - Value Change Handling

    @objc private func popupValueChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.selectedItem?.title else { return }
        currentValue = selectedTitle

        // Track the modification
        saveCurrentChanges()

        // Update appearance based on modification state
        if isNew {
            updateNewColumnAppearance()
        } else {
            updateModificationAppearance()
        }
    }

    // MARK: - Modification Tracking

    private func saveCurrentChanges() {
        guard let tracker = modificationTracker,
              let originalColumn = originalColumn,
              rowIndex >= 0 else { return }

        if currentValue != originalValue {
            // Create a modified column with the new type
            let modifiedColumn = DatabaseSchemaInfo(
                ordinalPosition: originalColumn.ordinalPosition,
                columnName: originalColumn.columnName,
                dataType: currentValue,
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

            // Handle new columns differently - update the addition instead of creating a modification
            if isNew {
                let currentTrackerName = tracker.getNewColumnName(byOrdinal: originalColumn.ordinalPosition) ?? originalColumn.columnName
                tracker.updateColumnAddition(originalName: currentTrackerName, updatedColumn: modifiedColumn)
                self.originalColumn = modifiedColumn
                debugLog("New column type updated: \(originalValue) -> \(currentValue)")
            } else {
                tracker.trackColumnModification(original: originalColumn, modified: modifiedColumn)
                debugLog("Type changed for column: \(originalColumn.columnName) to \(currentValue)")
            }
        } else {
            // Value was reverted - check if we should remove the modification
            if !isNew {
                tracker.removeColumnModification(for: originalColumn.columnName)
                debugLog("Type reverted to original for column: \(originalColumn.columnName)")
            }
        }
    }

    // MARK: - Appearance Updates

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

        // Green tint for new columns
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let newColumnColor = isDarkMode
            ? NSColor(red: 0x2C/255.0, green: 0x59/255.0, blue: 0x3C/255.0, alpha: 1.0)
            : NSColor(red: 0xC8/255.0, green: 0xE6/255.0, blue: 0xC8/255.0, alpha: 1.0)
        layer?.backgroundColor = newColumnColor.cgColor
    }

    // MARK: - Border Views

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
}
