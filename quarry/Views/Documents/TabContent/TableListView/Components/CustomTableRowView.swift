//
//  CustomTableRowView.swift
//  Quarry
//
//  Created by Fauzaan on 6/4/25.
//

import Foundation
import AppKit

class CustomTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set { }
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
            guard let tableView = superview as? NSTableView else {
                super.draw(dirtyRect)
                return
            }

            let rowIndex = tableView.row(for: self)
            if rowIndex % 2 == 1 {
                NSColor.alternatingRowStripeColor.setFill()
                bounds.fill()
            }
        }

        super.draw(dirtyRect)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard let tableView = self.superview as? CustomTableView else {
            // Fallback for non-custom table views
            drawFullRowSelection()
            return
        }
        
        let currentRowIndex = tableView.row(for: self)
        let selectedRows = tableView.selectedRowIndexes
        
        // Check if this row is selected
        if selectedRows.contains(currentRowIndex) {
            // Get the current active cell location
            if let cellLocation = tableView.getCurrentSelectedCell(),
               cellLocation.row == currentRowIndex {
                // Draw cell-specific selection
                drawCellSelection(for: cellLocation.column, in: tableView)
            } else {
                // Draw full row selection as fallback
                drawFullRowSelection()
            }
        }
    }
    
    private func drawCellSelection(for columnIndex: Int, in tableView: NSTableView) {
        // If columnIndex is -1, just draw row selection
        if columnIndex == -1 {
            drawFullRowSelection()
            return
        }
        
        guard columnIndex >= 0 && columnIndex < tableView.numberOfColumns else {
            drawFullRowSelection()
            return
        }
        
        drawFullRowSelection()
        
        let cellRect = calculateCellRect(for: columnIndex, in: tableView)
        
        // Draw cell border
        let borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6)
        borderColor.setStroke()
        
        let borderPath = NSBezierPath(rect: cellRect.insetBy(dx: 0.5, dy: 0.5))
        borderPath.lineWidth = 1.5
        borderPath.stroke()
        
        // Optional: Add subtle inner glow effect
        let innerGlowColor = NSColor.controlAccentColor.withAlphaComponent(0.1)
        innerGlowColor.setFill()
        let innerRect = cellRect.insetBy(dx: 1, dy: 1)
        innerRect.fill()
    }
    
    private func calculateCellRect(for columnIndex: Int, in tableView: NSTableView) -> NSRect {
        let columnRect = tableView.rect(ofColumn: columnIndex)
        return NSRect(
            x: columnRect.origin.x,
            y: 0,
            width: columnRect.width,
            height: bounds.height
        )
    }
    
    private func drawFullRowSelection() {
        let isDarkMode = NSApp.effectiveAppearance.isDarkMode
        let selectionColor = isDarkMode
            ? NSColor.controlColor.withAlphaComponent(0.08)
            : NSColor.controlAccentColor.withAlphaComponent(0.08)
        selectionColor.setFill()

        let paddedRect = NSRect(
            x: bounds.origin.x,
            y: bounds.origin.y,
            width: bounds.width,
            height: bounds.height - 1
        )
        paddedRect.fill()
    }
}
