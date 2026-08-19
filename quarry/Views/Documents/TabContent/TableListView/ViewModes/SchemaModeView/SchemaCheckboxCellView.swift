//
//  SchemaCheckboxCellView.swift
//  Quarry
//
//  Custom checkbox cell for schema nullable field with modification tracking
//

import Foundation
import AppKit

class SchemaCheckboxCellView: NSTableCellView {
    // UI
    private var button: RoundedCheckboxButton!
    private var rightBorderView: NSView?
    private var bottomBorderView: NSView?

    // State tracking
    private var originalValue: Bool = false
    private var currentValue: Bool = false
    private var originalColumn: DatabaseSchemaInfo?
    private var rowIndex: Int = -1
    weak var modificationTracker: SchemaModificationTracker?
    var isMarkedForDeletion: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    private var isModified: Bool {
        return currentValue != originalValue
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }

    private func setupButton() {
        button = RoundedCheckboxButton(frame: .zero)
        button.target = self
        button.action = #selector(buttonClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false

        addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isMarkedForDeletion {
            NSColor.red.withAlphaComponent(0.3).setFill()
            let fillRect = NSRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width - 1, height: bounds.height - 1)
            fillRect.fill()
        }
    }

    // MARK: - Configuration

    func configure(column: DatabaseSchemaInfo, rowIndex: Int, modificationTracker: SchemaModificationTracker?, isLastColumn: Bool) {
        self.rowIndex = rowIndex
        self.modificationTracker = modificationTracker
        self.originalColumn = column

        createBorderViewIfNeeded(isLastColumn: isLastColumn)

        // Check if this column is marked for deletion
        if let tracker = modificationTracker, tracker.isColumnMarkedForDeletion(column.columnName) {
            isMarkedForDeletion = true
        } else {
            isMarkedForDeletion = false
        }

        // Original value from the column
        let originalNullable = column.isNullable == "YES"
        self.originalValue = originalNullable

        // Check if this is a new column (not yet saved to DB)
        if let tracker = modificationTracker, tracker.isColumnNewByOrdinal(column.ordinalPosition) {
            self.currentValue = originalNullable
            updateIcon()
            updateNewColumnAppearance()
        }
        // Check if this cell has existing modifications
        else if let tracker = modificationTracker,
                let modification = tracker.getColumnModification(for: column.columnName),
                modification.type == .modifyColumn,
                let modifiedColumn = modification.column {
            // Use the modified value
            self.currentValue = modifiedColumn.isNullable == "YES"
            updateIcon()
            updateModificationAppearance()
        } else {
            self.currentValue = originalNullable
            updateIcon()
            updateModificationAppearance()
        }
    }

    // MARK: - Icon Updates

    private func updateIcon() {
        button.isOn = currentValue
        button.setAccessibilityLabel(currentValue ? "Nullable" : "Not nullable")
    }

    // MARK: - Click Handling

    @objc private func buttonClicked(_ sender: NSButton) {
        // Toggle the value
        currentValue.toggle()
        updateIcon()

        // Track the modification
        saveCurrentChanges()

        // Update appearance based on modification state
        if let tracker = modificationTracker, let column = originalColumn, tracker.isColumnNewByOrdinal(column.ordinalPosition) {
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

        let newNullableValue = currentValue ? "YES" : "NO"
        let originalNullableValue = originalValue ? "YES" : "NO"

        if newNullableValue != originalNullableValue {
            // Create a modified column with the new nullable state
            let modifiedColumn = DatabaseSchemaInfo(
                ordinalPosition: originalColumn.ordinalPosition,
                columnName: originalColumn.columnName,
                dataType: originalColumn.dataType,
                formatType: originalColumn.formatType,
                typeOid: originalColumn.typeOid,
                numericPrecision: originalColumn.numericPrecision,
                datetimePrecision: originalColumn.datetimePrecision,
                numericScale: originalColumn.numericScale,
                dataLength: originalColumn.dataLength,
                isNullable: newNullableValue,
                check: originalColumn.check,
                checkConstraint: originalColumn.checkConstraint,
                columnDefault: originalColumn.columnDefault,
                foreignKey: originalColumn.foreignKey,
                constraints: originalColumn.constraints,
                comment: originalColumn.comment,
                isReadOnly: originalColumn.isReadOnly
            )

            // Handle new columns differently - update the addition instead of creating a modification
            let isNewColumn = tracker.isColumnNewByOrdinal(originalColumn.ordinalPosition)
            if isNewColumn {
                let currentTrackerName = tracker.getNewColumnName(byOrdinal: originalColumn.ordinalPosition) ?? originalColumn.columnName
                tracker.updateColumnAddition(originalName: currentTrackerName, updatedColumn: modifiedColumn)
                self.originalColumn = modifiedColumn
                debugLog("📝 New column nullable updated: \(originalNullableValue) → \(newNullableValue)")
            } else {
                tracker.trackColumnModification(original: originalColumn, modified: modifiedColumn)
                debugLog("📝 Nullable toggled for column: \(originalColumn.columnName) to \(newNullableValue)")
            }
        } else {
            // Value was reverted - check if we should remove the modification
            let isNewColumn = tracker.isColumnNewByOrdinal(originalColumn.ordinalPosition)
            if !isNewColumn {
                tracker.removeColumnModification(for: originalColumn.columnName)
                debugLog("🔄 Nullable reverted to original for column: \(originalColumn.columnName)")
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

        // Green tint for new columns to distinguish from modified existing columns
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let newColumnColor = isDarkMode
            ? NSColor(red: 0x2C/255.0, green: 0x59/255.0, blue: 0x3C/255.0, alpha: 1.0)  // Dark green for dark mode
            : NSColor(red: 0xC8/255.0, green: 0xE6/255.0, blue: 0xC8/255.0, alpha: 1.0)  // Light green for light mode
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
