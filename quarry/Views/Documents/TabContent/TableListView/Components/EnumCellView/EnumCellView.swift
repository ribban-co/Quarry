//
//  EnumCellView.swift
//  Quarry
//
//  Dropdown cell for enum column values with modification tracking
//

import Foundation
import AppKit

class EnumCellView: NSView {
    private var popupButton: NSPopUpButton!
    private var rightBorderView: NSView?
    private var bottomBorderView: NSView?

    private var rowIndex: Int = -1
    var columnName: String = ""
    var tableName: String = ""
    weak var modificationTracker: TableModificationTracker?
    private var originalValue: String = ""
    private var enumValues: [String] = []
    private var dataType: String = ""
    private var isNullable: Bool = true
    private var isModified = false {
        didSet {
            if oldValue != isModified {
                updateModificationAppearance()
            }
        }
    }
    var isFieldEditable = true
    var isMarkedForDeletion: Bool = false {
        didSet {
            needsDisplay = true
        }
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
        popupButton.font = .systemFont(ofSize: 12)
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isMarkedForDeletion {
            NSColor.red.withAlphaComponent(0.3).setFill()
            let fillRect = NSRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width - 1, height: bounds.height - 1)
            fillRect.fill()
        }
    }

    override func prepareForReuse() {
        isModified = false
        isMarkedForDeletion = false
        originalValue = ""
        enumValues = []
        popupButton.removeAllItems()
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    func configure(
        value: String,
        enumValues: [String],
        rowIndex: Int,
        columnName: String,
        dataType: String,
        modificationTracker: TableModificationTracker?,
        tableName: String,
        isReadOnly: Bool,
        isNullable: Bool = true
    ) {
        self.rowIndex = rowIndex
        self.columnName = columnName
        self.dataType = dataType
        self.modificationTracker = modificationTracker
        self.tableName = tableName
        self.isFieldEditable = !isReadOnly
        self.enumValues = enumValues
        self.isNullable = isNullable

        createBorderViewIfNeeded()

        if let modification = modificationTracker?.getRowModification(for: rowIndex), modification.type == .delete {
            self.isMarkedForDeletion = true
        } else {
            self.isMarkedForDeletion = false
        }

        popupButton.isEnabled = isFieldEditable

        popupButton.removeAllItems()

        if isNullable {
            popupButton.addItem(withTitle: "(NULL)")
        }

        for enumValue in enumValues {
            popupButton.addItem(withTitle: enumValue)
        }

        if let cellMod = modificationTracker?.getCellModification(rowIndex: rowIndex, columnName: columnName) {
            self.originalValue = cellMod.originalValue
            let displayValue = cellMod.newValue.isEmpty ? "(NULL)" : cellMod.newValue
            selectValue(displayValue)
            isModified = cellMod.hasChanged
        } else {
            self.originalValue = value
            let displayValue = value.isEmpty ? "(NULL)" : value
            selectValue(displayValue)
            isModified = false
        }

        updateModificationAppearance()
    }

    private func selectValue(_ value: String) {
        if popupButton.item(withTitle: value) != nil {
            popupButton.selectItem(withTitle: value)
        } else if !value.isEmpty && value != "(NULL)" {
            let insertIndex = isNullable ? 1 : 0
            popupButton.insertItem(withTitle: value, at: insertIndex)
            popupButton.selectItem(withTitle: value)
        }
    }

    @objc private func popupValueChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.selectedItem?.title else { return }

        let newValue = selectedTitle == "(NULL)" ? "" : selectedTitle
        let hasChanged = newValue != originalValue

        isModified = hasChanged

        if let tracker = modificationTracker, rowIndex >= 0 {
            if hasChanged {
                tracker.updateCell(
                    rowIndex: rowIndex,
                    columnName: columnName,
                    newValue: newValue,
                    originalValue: originalValue,
                    dataType: dataType
                )
            } else {
                tracker.resetCell(rowIndex: rowIndex, columnName: columnName)
            }
        }
    }

    private func updateModificationAppearance() {
        if !wantsLayer {
            wantsLayer = true
        }

        if isModified {
            layer?.backgroundColor = NSColor.cellModificationColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func createBorderViewIfNeeded() {
        if rightBorderView == nil || bottomBorderView == nil {
            createBorderView()
        }
        updateBorderVisibility()
    }

    private func updateBorderVisibility() {
        let alternatingRowsEnabled = TableAppearanceSettings.alternatingRowColors
        bottomBorderView?.isHidden = alternatingRowsEnabled
        rightBorderView?.isHidden = alternatingRowsEnabled
    }

    private func createBorderView() {
        rightBorderView = NSView()
        rightBorderView?.wantsLayer = true
        rightBorderView?.layer?.backgroundColor = NSColor.separatorColor.cgColor

        addSubview(rightBorderView!)
        rightBorderView?.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rightBorderView!.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            rightBorderView!.topAnchor.constraint(equalTo: topAnchor),
            rightBorderView!.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightBorderView!.widthAnchor.constraint(equalToConstant: 1.0)
        ])

        bottomBorderView = NSView()
        bottomBorderView?.wantsLayer = true
        bottomBorderView?.layer?.backgroundColor = NSColor.separatorColor.cgColor

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
