//
//  CustomTableView.swift
//  Quarry
//
//  Created by Fauzaan on 6/24/25.
//
import Foundation
import AppKit

@MainActor
protocol CustomTableViewEditingDelegate: AnyObject {
    func customTableView(_ tableView: CustomTableView, editCellAtRow row: Int, column: Int)
    func customTableView(_ tableView: CustomTableView, foreignKeyClickedAtRow row: Int, column: Int)
}

// MARK: - Custom NSTableView using built-in selection mechanisms
@MainActor
class CustomTableView: NSTableView {
    // Handler for undo operations
    var undoHandler: (() -> Bool)?
    weak var editingDelegate: CustomTableViewEditingDelegate?

    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    // MARK: - Grid Line Drawing

    override func drawGrid(inClipRect clipRect: NSRect) {
        super.drawGrid(inClipRect: clipRect)

        // Draw right border for last column (native grid only draws between columns)
        guard TableAppearanceSettings.alternatingRowColors,
              numberOfColumns > 0 else { return }

        let lastColumnRect = rect(ofColumn: numberOfColumns - 1)
        let lineX = floor(lastColumnRect.maxX) + 0.5

        if lineX >= clipRect.minX && lineX <= clipRect.maxX {
            gridColor.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: lineX, y: clipRect.minY))
            line.line(to: NSPoint(x: lineX, y: clipRect.maxY))
            line.lineWidth = 1.0
            line.stroke()
        }
    }

    // MARK: - Alternating Row Background Drawing

    override func drawBackground(inClipRect clipRect: NSRect) {
        super.drawBackground(inClipRect: clipRect)

        guard TableAppearanceSettings.alternatingRowColors else { return }

        drawAlternatingRowsAbove(clipRect: clipRect)
        drawAlternatingRowsBelow(clipRect: clipRect)
    }

    private func drawAlternatingRowsAbove(clipRect: NSRect) {
        guard clipRect.minX >= 0 && clipRect.width <= bounds.width + 10 else { return }

        let visibleRows = rows(in: visibleRect)
        guard visibleRows.location != NSNotFound, visibleRows.location > 0 || visibleRect.minY < 0 else { return }

        let firstVisibleRow = max(0, visibleRows.location)
        let topOfFirstRow = rect(ofRow: firstVisibleRow).minY
        guard clipRect.minY < topOfFirstRow else { return }

        let rowHeight = self.rowHeight
        var rowIndex = firstVisibleRow - 1
        var rowY = topOfFirstRow - rowHeight

        // Align to first odd row (stripes are on odd indices)
        if rowIndex % 2 == 0 {
            rowIndex -= 1
            rowY -= rowHeight
        }

        guard rowY + rowHeight > clipRect.minY else { return }

        NSColor.alternatingRowStripeColor.setFill()

        while rowY + rowHeight > clipRect.minY && rowIndex >= 0 {
            let stripeMinY = max(rowY, clipRect.minY)
            let stripeMaxY = min(rowY + rowHeight, clipRect.maxY)
            if stripeMaxY > stripeMinY {
                NSRect(x: clipRect.minX, y: stripeMinY, width: clipRect.width, height: stripeMaxY - stripeMinY).fill()
            }
            rowY -= rowHeight * 2
            rowIndex -= 2
        }
    }

    private func drawAlternatingRowsBelow(clipRect: NSRect) {
        let totalRows = numberOfRows
        guard totalRows > 0 else { return }
        guard clipRect.minX >= 0 && clipRect.width <= bounds.width + 10 else { return }

        let rowHeight = self.rowHeight > 0 ? self.rowHeight : 24
        let contentEndY = rect(ofRow: totalRows - 1).maxY
        guard clipRect.maxY > contentEndY else { return }

        let effectiveMinY = max(clipRect.minY, contentEndY)
        let effectiveMaxY = clipRect.maxY
        guard effectiveMaxY > effectiveMinY else { return }

        // Calculate starting row index and Y position
        let rowsFromContent = Int(floor((effectiveMinY - contentEndY) / rowHeight))
        let rowIndex = totalRows + rowsFromContent
        var rowY = contentEndY + CGFloat(rowsFromContent) * rowHeight

        // Align to first odd row (stripes are on odd indices)
        if rowIndex % 2 == 0 {
            rowY += rowHeight
        }

        guard rowY < effectiveMaxY else { return }

        NSColor.alternatingRowStripeColor.setFill()

        while rowY < effectiveMaxY {
            let stripeMinY = max(rowY, clipRect.minY)
            let stripeMaxY = min(rowY + rowHeight, clipRect.maxY)
            if stripeMaxY > stripeMinY {
                NSRect(x: clipRect.minX, y: stripeMinY, width: clipRect.width, height: stripeMaxY - stripeMinY).fill()
            }
            rowY += rowHeight * 2
        }
    }
    
    // Delegate for cell-level selection events
    weak var cellSelectionDelegate: TableViewCellSelectionDelegate?
    
    // Current cell selection (computed from built-in selection)
    private var currentCellLocation: (row: Int, column: Int)? {
        let selectedRow = self.selectedRow
        let clickedCol = self.clickedColumn
        
        // Only return a location if we have a valid selected row
        guard selectedRow >= 0 else {
            return nil
        }
        
        // If we have a valid clicked column, use it; otherwise use -1 for row-only selection
        let column = (clickedCol >= 0 && clickedCol < numberOfColumns) ? clickedCol : -1
        
        return (selectedRow, column)
    }
    
    // MARK: - Action-Target Pattern for Click Detection
    @objc private func handleTableClick() {
        let selectedRow = self.selectedRow
        let clickedCol = self.clickedColumn
        
        if selectedRow >= 0 && clickedCol >= 0 {
            debugLog("🎯 Cell clicked: (\(selectedRow), \(clickedCol))")
            cellSelectionDelegate?.tableView(self, didSelectCellAt: selectedRow, column: clickedCol)
        }
    }
    
    // MARK: - Keyboard Navigation

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self || isDescendant(of: window?.firstResponder as? NSView ?? self) else {
            return super.performKeyEquivalent(with: event)
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+C (copy)
        if flags == .command && event.charactersIgnoringModifiers == "c" {
            if !selectedRowIndexes.isEmpty {
                NotificationCenter.default.post(
                    name: .didRequestCopy,
                    object: self,
                    userInfo: ["tableView": self]
                )
            }
            return true
        }

        // Cmd+V (paste)
        if flags == .command && event.charactersIgnoringModifiers == "v" {
            NotificationCenter.default.post(
                name: .didRequestPaste,
                object: self,
                userInfo: ["tableView": self]
            )
            return true
        }

        // Cmd+Z (undo)
        if flags == .command && event.charactersIgnoringModifiers == "z" {
            if let undoHandler = undoHandler, undoHandler() {
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Handle navigation keys
        if handleKeyboardNavigation(with: event) {
            return
        }

        // Let the superclass handle other key events
        super.keyDown(with: event)
    }

    /// The effective column for keyboard navigation, defaulting to 0 when no column has been clicked.
    private var effectiveColumn: Int {
        storedClickedColumn >= 0 ? storedClickedColumn : 0
    }

    @discardableResult
    private func moveSelectionHorizontally(offset: Int) -> Bool {
        guard numberOfColumns > 0, numberOfRows > 0 else { return false }

        if selectedRow < 0 {
            selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            updateActiveColumn(0)
            scrollRowToVisible(0)
            return true
        }

        let newColumn = min(max(effectiveColumn + offset, 0), numberOfColumns - 1)
        guard newColumn != effectiveColumn else { return true }

        updateActiveColumn(newColumn)
        return true
    }

    @discardableResult
    private func moveSelectionVertically(offset: Int) -> Bool {
        guard numberOfRows > 0 else { return false }

        if selectedRow < 0 {
            selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            if storedClickedColumn < 0 {
                updateActiveColumn(0)
            } else {
                refreshActiveCellDisplay()
            }
            scrollRowToVisible(0)
            return true
        }

        let newRow = min(max(selectedRow + offset, 0), numberOfRows - 1)
        guard newRow != selectedRow else { return true }

        selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        scrollRowToVisible(newRow)
        refreshActiveCellDisplay()
        return true
    }

    @discardableResult
    private func activateSelectedCell() -> Bool {
        guard selectedRow >= 0 else { return false }

        enterEditModeForCell(row: selectedRow, column: effectiveColumn)
        return true
    }

    private func updateActiveColumn(_ column: Int) {
        guard column >= 0 && column < numberOfColumns else { return }

        setClickedColumn(column)
        scrollColumnToVisible(column)
        refreshActiveCellDisplay()
    }

    private func refreshActiveCellDisplay() {
        guard selectedRow >= 0 else { return }

        if let rowView = rowView(atRow: selectedRow, makeIfNecessary: false) {
            rowView.needsDisplay = true
        }

        needsDisplay = true

        if storedClickedColumn >= 0 {
            cellSelectionDelegate?.tableView(self, didSelectCellAt: selectedRow, column: storedClickedColumn)
        }
    }

    private func handleKeyboardNavigation(with event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let navigationModifiers = flags.subtracting([.numericPad, .function])
        let currentRow = selectedRow

        // Handle Cmd+Enter for Quick Look
        if navigationModifiers == .command && keyCode == 36 {
            if let cellLocation = currentCellLocation, cellLocation.column >= 0 {
                NotificationCenter.default.post(
                    name: .cellQuickLookRequested,
                    object: self,
                    userInfo: ["row": cellLocation.row, "column": cellLocation.column, "tableView": self]
                )
                return true
            }
        }

        // Let super handle arrow keys with modifiers (Shift for extend selection, etc.)
        let isArrowKey = keyCode == 126 || keyCode == 125 || keyCode == 123 || keyCode == 124
        if isArrowKey && !navigationModifiers.isEmpty {
            return false
        }

        // Initialize selection if none exists and user presses navigation key
        if currentRow < 0 && isArrowKey {
            selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            if storedClickedColumn < 0 {
                setClickedColumn(0)
            }
            refreshActiveCellDisplay()
            scrollRowToVisible(0)
            return true
        }

        var newRow = currentRow
        var handled = false

        switch keyCode {
        case 126: // Up arrow
            newRow = max(0, currentRow - 1)
            handled = true

        case 125: // Down arrow
            newRow = min(numberOfRows - 1, currentRow + 1)
            handled = true

        case 123: // Left arrow - move to previous column
            return moveSelectionHorizontally(offset: -1)

        case 124: // Right arrow - move to next column
            return moveSelectionHorizontally(offset: 1)

        case 48, 36: // Tab/Enter - enter edit mode
            return activateSelectedCell()

        case 53: // Escape - clear selection
            selectRowIndexes(IndexSet(), byExtendingSelection: false)
            handled = true

        case 51, 117: // Delete/Backspace
            let selectedRows = selectedRowIndexes
            NotificationCenter.default.post(
                name: .didRequestDelete,
                object: self,
                userInfo: ["rows": selectedRows, "tableView": self]
            )
            handled = true

        default:
            return false
        }

        if handled && newRow != currentRow && keyCode != 53 {
            selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
            scrollRowToVisible(newRow)
        }

        return handled
    }
    
    func refreshSelectedRowByReselection() {
        guard selectedRow >= 0 else { return }
        
        let currentRow = selectedRow
        let currentColumn = storedClickedColumn
        
        // Deselect
        selectRowIndexes(IndexSet(), byExtendingSelection: false)
        
        // Immediately reselect
        selectRowIndexes(IndexSet(integer: currentRow), byExtendingSelection: false)
        
        // Restore column selection
        if currentColumn >= 0 {
            storedClickedColumn = currentColumn
        }

        refreshActiveCellDisplay()
    }
    
    // MARK: - Mouse Event Handling
    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: clickPoint)
        let clickedColumn = column(at: clickPoint)
        
        debugLog("🖱️ Mouse down at: (\(clickedRow), \(clickedColumn))")
        
        // Check for foreign key click before handling normal selection
        if clickedRow >= 0 && clickedColumn >= 0 {
            if let cellView = view(atColumn: clickedColumn, row: clickedRow, makeIfNecessary: false) as? (NSView & TableForeignKeyCell) {
                let cellClickPoint = convert(clickPoint, to: cellView)

                if cellView.isForeignKeyCell && cellView.containsForeignKeyHit(point: cellClickPoint) {
                    debugLog("🔗 Foreign key icon clicked at (\(clickedRow), \(clickedColumn))")
                    editingDelegate?.customTableView(self, foreignKeyClickedAtRow: clickedRow, column: clickedColumn)
                }
            }
        }
        
        // Check if clicking the same row
        let isSameRow = (clickedRow == selectedRow && clickedRow >= 0)
        
        setClickedColumn(clickedColumn)
        // If same row clicked, force refresh
        if isSameRow {
            debugLog("🔄 Same row clicked - refreshing selection")
            refreshSelectedRowByReselection()
        }
        
        super.mouseDown(with: event)

        if acceptsFirstResponder, event.clickCount == 1, !(window?.firstResponder is NSTextView) {
            window?.makeFirstResponder(self)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: clickPoint)
        let clickedColumn = column(at: clickPoint)
        
        debugLog("🖱️ Right click at: (\(clickedRow), \(clickedColumn))")
        
        // Store right-click location for menu validation
        rightClickedRow = clickedRow
        rightClickedColumn = clickedColumn
        
        // Only update selection if no multiple selection exists or if right-clicking outside selected rows
        let currentSelection = selectedRowIndexes
        let hasMultipleSelection = currentSelection.count > 1
        let rightClickedOnSelectedRow = clickedRow >= 0 && currentSelection.contains(clickedRow)
        
        if !hasMultipleSelection || !rightClickedOnSelectedRow {
            // Update selection to the right-clicked location
            if clickedRow >= 0 {
                selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
                if clickedColumn >= 0 {
                    setClickedColumn(clickedColumn)
                }
            }
        }
        
        super.rightMouseDown(with: event)
    }
    
    // Helper to store clicked column (since NSTableView doesn't always track this reliably)
    private var storedClickedColumn: Int = -1
    
    // Store right-click location for context menu validation (separate from selection)
    private var rightClickedRow: Int = -1
    private var rightClickedColumn: Int = -1
    
    private func setClickedColumn(_ column: Int) {
        storedClickedColumn = column
    }
    
    override var clickedColumn: Int {
        // Return stored column if available, otherwise use built-in
        if storedClickedColumn >= 0 {
            return storedClickedColumn
        }
        
        return super.clickedColumn
    }
    
    // MARK: - Edit Mode
    func enterEditModeForCell(row: Int, column: Int) {
        guard row >= 0 && row < numberOfRows && column >= 0 && column < numberOfColumns else {
            debugLog("❌ Invalid cell position: (\(row), \(column))")
            return
        }

        if view(atColumn: column, row: row, makeIfNecessary: false) is TableDisplayCellView {
            debugLog("✅ Entering lazy edit mode for TableDisplayCellView at (\(row), \(column))")
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            editingDelegate?.customTableView(self, editCellAtRow: row, column: column)
        } else if let cellView = view(atColumn: column, row: row, makeIfNecessary: false) as? TextCellView {
            debugLog("✅ Entering edit mode for TextCellView at (\(row), \(column))")
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            cellView.enterEditMode()
        } else if let cellView = view(atColumn: column, row: row, makeIfNecessary: false) as? SchemaEditableCellView {
            debugLog("✅ Entering edit mode for SchemaEditableCellView at (\(row), \(column))")
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            cellView.enterEditMode()
        } else {
            debugLog("❌ Could not find editable cell at (\(row), \(column))")
        }
    }
    
    override func editColumn(_ column: Int, row: Int, with event: NSEvent?, select: Bool) {
        debugLog("✏️ editColumn called for (\(row), \(column)) with select: \(select)")
        
        // Validate bounds
        guard row >= 0 && row < numberOfRows && column >= 0 && column < numberOfColumns else {
            super.editColumn(column, row: row, with: event, select: select)
            return
        }
        
        // Select the row using built-in selection
        if select {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        
        if view(atColumn: column, row: row, makeIfNecessary: false) is TableDisplayCellView {
            editingDelegate?.customTableView(self, editCellAtRow: row, column: column)
            scrollRowToVisible(row)
            scrollColumnToVisible(column)
        } else if let cellView = view(atColumn: column, row: row, makeIfNecessary: false) as? TextCellView {
            cellView.enterEditMode()
            scrollRowToVisible(row)
            scrollColumnToVisible(column)
        } else {
            // Fall back to default behavior
            super.editColumn(column, row: row, with: event, select: select)
        }
    }
    
    // MARK: - Selection Management
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    /// Gets the currently selected cell coordinates
    func getCurrentSelectedCell() -> (row: Int, column: Int)? {
        return currentCellLocation
    }
    
    /// Gets the right-clicked cell coordinates (for context menu validation)
    func getRightClickedCell() -> (row: Int, column: Int) {
        return (rightClickedRow, rightClickedColumn)
    }
    
    /// Programmatically select a specific cell
    func selectCell(row: Int, column: Int) {
        guard row >= 0 && row < numberOfRows && column >= 0 && column < numberOfColumns else {
            return
        }
        
        // Use built-in row selection
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        
        // Store column for later retrieval
        storedClickedColumn = column

        // Scroll to make visible
        scrollRowToVisible(row)
        scrollColumnToVisible(column)

        refreshActiveCellDisplay()

        if acceptsFirstResponder {
            window?.makeFirstResponder(self)
        }
    }
    
    /// Clears all selection
    func clearAllSelection() {
        debugLog("🧹 Clearing all table selection state")
        selectRowIndexes(IndexSet(), byExtendingSelection: false)
        storedClickedColumn = -1
    }
    
    /// Get column index for identifier
    func columnIndex(for identifier: String) -> Int {
        for (index, column) in tableColumns.enumerated() {
            if column.identifier.rawValue == identifier {
                return index
            }
        }
        return -1
    }
}

// MARK: - Cell Selection Delegate Protocol
protocol TableViewCellSelectionDelegate: AnyObject {
    func tableView(_ tableView: NSTableView, didSelectCellAt row: Int, column: Int)
}
