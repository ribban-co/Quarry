//
//  IndexDropdownCellView.swift
//  Quarry
//
//  Custom dropdown cell for index type field with modification tracking
//

import Foundation
import AppKit

class IndexDropdownCellView: NSTableCellView {
    // UI
    private var popupButton: NSPopUpButton!
    private var rightBorderView: NSView?
    private var bottomBorderView: NSView?

    // Database-specific index types
    private static let postgresIndexTypes = ["BTREE", "HASH", "GIST", "SPGIST", "GIN", "BRIN"]
    private static let mysqlIndexTypes = ["BTREE", "HASH", "FULLTEXT", "SPATIAL"]
    private static let sqliteIndexTypes = ["BTREE"]
    private static let defaultIndexTypes = ["BTREE", "HASH"]

    // State tracking
    private var originalValue: IndexType = .btree
    private var currentValue: IndexType = .btree
    private var customValue: String? = nil
    private var originalIndex: DatabaseIndexInfo?
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

    private func configureMenuItems(for databaseType: DatabaseType, currentType: IndexType) {
        popupButton.removeAllItems()

        let indexTypes: [String]
        switch databaseType {
        case .postgres, .supabase:
            indexTypes = Self.postgresIndexTypes
        case .mysql:
            indexTypes = Self.mysqlIndexTypes
        case .sqlite:
            indexTypes = Self.sqliteIndexTypes
        default:
            indexTypes = Self.defaultIndexTypes
        }

        // Add standard index types
        for indexType in indexTypes {
            popupButton.addItem(withTitle: indexType)
        }

        // If current type is not in the list, add it
        let currentTypeString = currentType.rawValue.uppercased()
        if !indexTypes.contains(currentTypeString) && currentType != .other {
            popupButton.menu?.addItem(NSMenuItem.separator())
            popupButton.addItem(withTitle: currentTypeString)
        }

        // Add separator and manual input option
        popupButton.menu?.addItem(NSMenuItem.separator())
        let manualItem = NSMenuItem(title: "Manual input...", action: #selector(showManualInput), keyEquivalent: "")
        manualItem.target = self
        popupButton.menu?.addItem(manualItem)
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
        let label = NSTextField(labelWithString: "Index Type:")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.frame = NSRect(x: 12, y: 42, width: 176, height: 16)
        containerView.addSubview(label)

        // Text field
        let inputTextField = NSTextField(frame: NSRect(x: 12, y: 12, width: 176, height: 24))
        inputTextField.stringValue = currentValue.rawValue.uppercased()
        inputTextField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        inputTextField.placeholderString = "e.g., BTREE"
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
        static let popoverKeyValue = 0x4944_504F
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
            // Try to parse as known type first
            if let knownType = IndexType(rawValue: inputValue.lowercased()) {
                currentValue = knownType
                customValue = nil
            } else {
                currentValue = .other
                customValue = inputValue
            }

            // Add to menu if not present
            let upperValue = inputValue.uppercased()
            if popupButton.item(withTitle: upperValue) == nil {
                // Insert before the separator
                let separatorIndex = popupButton.menu?.items.firstIndex(where: { $0.isSeparatorItem }) ?? popupButton.numberOfItems
                popupButton.insertItem(withTitle: upperValue, at: separatorIndex)
            }
            popupButton.selectItem(withTitle: upperValue)

            saveCurrentChanges()
            if isNew {
                updateNewIndexAppearance()
            } else {
                updateModificationAppearance()
            }
        } else {
            // Empty input, restore previous selection
            selectIndexType(currentValue)
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

    func configure(index: DatabaseIndexInfo, rowIndex: Int, modificationTracker: SchemaModificationTracker?, databaseType: DatabaseType, isLastColumn: Bool) {
        self.rowIndex = rowIndex
        self.modificationTracker = modificationTracker
        self.originalIndex = index
        self.databaseType = databaseType

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

        // Original value from the index
        self.originalValue = index.indexType
        self.currentValue = index.indexType

        // Configure menu items based on database type
        configureMenuItems(for: databaseType, currentType: index.indexType)

        // Check if this index has existing modifications
        if let tracker = modificationTracker,
           let modification = tracker.getIndexModification(for: index.name),
           modification.type == .modifyIndex,
           let modifiedIndex = modification.index {
            // Use the modified value
            self.currentValue = modifiedIndex.indexType
            selectIndexType(modifiedIndex.indexType)
            updateModificationAppearance()
        } else {
            selectIndexType(index.indexType)
            if isNew {
                updateNewIndexAppearance()
            } else {
                updateModificationAppearance()
            }
        }
    }

    // MARK: - Selection

    private func selectIndexType(_ indexType: IndexType) {
        let title = indexType.rawValue.uppercased()
        popupButton.selectItem(withTitle: title)
    }

    private func indexTypeFromSelection() -> IndexType {
        guard let selectedTitle = popupButton.selectedItem?.title else {
            return .btree
        }
        return IndexType(rawValue: selectedTitle.lowercased()) ?? .btree
    }

    // MARK: - Value Change Handling

    @objc private func popupValueChanged(_ sender: NSPopUpButton) {
        currentValue = indexTypeFromSelection()

        // Track the modification
        saveCurrentChanges()

        // Update appearance based on modification state
        if isNew {
            updateNewIndexAppearance()
        } else {
            updateModificationAppearance()
        }
    }

    // MARK: - Modification Tracking

    private func saveCurrentChanges() {
        guard let tracker = modificationTracker,
              let originalIndex = originalIndex,
              rowIndex >= 0 else { return }

        if currentValue != originalValue {
            // Create a modified index with the new type
            let modifiedIndex = DatabaseIndexInfo(
                name: originalIndex.name,
                tableName: originalIndex.tableName,
                schemaName: originalIndex.schemaName,
                columns: originalIndex.columns,
                indexType: currentValue,
                isUnique: originalIndex.isUnique,
                isPrimaryKey: originalIndex.isPrimaryKey,
                definition: originalIndex.definition,
                condition: originalIndex.condition,
                includeColumns: originalIndex.includeColumns,
                comment: originalIndex.comment
            )

            // Handle new indexes differently - update the addition instead of creating a modification
            if isNew {
                tracker.updateIndexAddition(originalName: originalIndex.name, updatedIndex: modifiedIndex)
                self.originalIndex = modifiedIndex
                debugLog("New index type updated: \(originalValue) -> \(currentValue)")
            } else {
                tracker.trackIndexModification(original: originalIndex, modified: modifiedIndex)
                debugLog("Type changed for index: \(originalIndex.name) to \(currentValue)")
            }
        } else {
            // Value was reverted - check if we should remove the modification
            if !isNew {
                tracker.removeIndexModification(for: originalIndex.name)
                debugLog("Type reverted to original for index: \(originalIndex.name)")
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

    private func updateNewIndexAppearance() {
        if !wantsLayer {
            wantsLayer = true
        }

        // Green tint for new indexes
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let newIndexColor = isDarkMode
            ? NSColor(red: 0x2C/255.0, green: 0x59/255.0, blue: 0x3C/255.0, alpha: 1.0)
            : NSColor(red: 0xC8/255.0, green: 0xE6/255.0, blue: 0xC8/255.0, alpha: 1.0)
        layer?.backgroundColor = newIndexColor.cgColor
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
