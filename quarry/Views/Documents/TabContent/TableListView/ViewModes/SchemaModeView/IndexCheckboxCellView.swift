//
//  IndexCheckboxCellView.swift
//  Quarry
//
//  Custom checkbox cell for index unique field with modification tracking
//

import Foundation
import AppKit

class IndexCheckboxCellView: NSTableCellView {
    // UI
    private var button: RoundedCheckboxButton!
    private var rightBorderView: NSView?
    private var bottomBorderView: NSView?

    // State tracking
    private var originalValue: Bool = false
    private var currentValue: Bool = false
    private var originalIndex: DatabaseIndexInfo?
    private var rowIndex: Int = -1
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

    func configure(index: DatabaseIndexInfo, rowIndex: Int, modificationTracker: SchemaModificationTracker?, isLastColumn: Bool) {
        self.rowIndex = rowIndex
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

        // Original value from the index
        self.originalValue = index.isUnique
        self.currentValue = index.isUnique

        // Check if this index has existing modifications
        if let tracker = modificationTracker,
           let modification = tracker.getIndexModification(for: index.name),
           modification.type == .modifyIndex,
           let modifiedIndex = modification.index {
            // Use the modified value
            self.currentValue = modifiedIndex.isUnique
            updateIcon()
            updateModificationAppearance()
        } else {
            updateIcon()
            if isNew {
                updateNewIndexAppearance()
            } else {
                updateModificationAppearance()
            }
        }
    }

    // MARK: - Icon Updates

    private func updateIcon() {
        button.isOn = currentValue
        button.setAccessibilityLabel(currentValue ? "Unique" : "Not unique")
    }

    // MARK: - Click Handling

    @objc private func buttonClicked(_ sender: NSButton) {
        // Toggle the value
        currentValue.toggle()
        updateIcon()

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
            // Create a modified index with the new unique state
            let modifiedIndex = DatabaseIndexInfo(
                name: originalIndex.name,
                tableName: originalIndex.tableName,
                schemaName: originalIndex.schemaName,
                columns: originalIndex.columns,
                indexType: originalIndex.indexType,
                isUnique: currentValue,
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
                debugLog("New index unique updated: \(originalValue) -> \(currentValue)")
            } else {
                tracker.trackIndexModification(original: originalIndex, modified: modifiedIndex)
                debugLog("Unique toggled for index: \(originalIndex.name) to \(currentValue)")
            }
        } else {
            // Value was reverted - check if we should remove the modification
            if !isNew {
                tracker.removeIndexModification(for: originalIndex.name)
                debugLog("Unique reverted to original for index: \(originalIndex.name)")
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

        // Green tint for new indexes to distinguish from modified existing indexes
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
