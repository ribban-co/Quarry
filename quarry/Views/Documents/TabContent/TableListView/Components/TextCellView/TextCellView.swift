//
//  TextCellView.swift
//  Quarry
//
//  Created by Fauzaan on 06/22/25.
//

import Foundation
import AppKit

// MARK: - Custom NSTextField that handles Escape key via cancelOperation
class EditableTextField: NSTextField {
    weak var cellView: TextCellView?

    override var acceptsFirstResponder: Bool {
        isEditable
    }

    // Size is fully determined by parent cell constraints — skip expensive CoreText measurement
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Check for Cmd+Z
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            // First, check if there's an undo operation available
            let undoManager = self.window?.firstResponder?.undoManager
            
            if let undoManager = undoManager, undoManager.canUndo {
                // There's something to undo, let the default implementation handle it
                return super.performKeyEquivalent(with: event)
            } else {
                let _ = cellView?.modificationTracker?.undo()
                return true
            }
        }
        
        return super.performKeyEquivalent(with: event)
    }

    // Override cancdelOperation which is called when Escape is pressed during editing
    override func cancelOperation(_ sender: Any?) {
        debugLog("🚫 cancelOperation triggered")
        
        guard let cellView = cellView else {
            super.cancelOperation(sender)
            return
        }
        
        let originalValue = cellView.originalValue
        
        // Perform abort editing synchronously (this should be fast)
        if abortEditing() {
            let tableView = cellView.findTableView()
            debugLog("✅ abortEditing succeeded")
            
            // Set values immediately on main thread with User Interactive QoS
            DispatchQueue.main.async(qos: .userInteractive) { [weak self, weak cellView] in
                guard let self = self, let cellView = cellView else { return }
                
                // Ensure our value is what we expect
                self.stringValue = originalValue
                cellView.isModified = false
                
                // Call exit edit mode on main thread with proper QoS
                cellView.exitEditMode()
                
                if let tableView = tableView {
                    if tableView.acceptsFirstResponder {
                        DispatchQueue.main.async(qos: .userInteractive) {
                            let success = tableView.window?.makeFirstResponder(tableView) ?? false
                            debugLog("   - Table view became first responder: \(success)")
                            
                            if !success {
                                debugLog("⚠️ Failed to make table view first responder, trying window")
                                tableView.window?.makeFirstResponder(tableView.window)
                            }
                        }
                    } else {
                        debugLog("⚠️ Table view doesn't accept first responder")
                        // Fallback: make window first responder
                        window?.makeFirstResponder(window)
                    }
                    
                }
                
                debugLog("   - Current first responder: \(self.window?.firstResponder?.className ?? "nil")")
                debugLog("   - Text field isEditable: \(self.isEditable)")
            }
        } else {
            debugLog("⚠️ abortEditing failed, falling back to manual exit")
            
            // Fallback: manual revert and exit on main thread with User Interactive QoS
            DispatchQueue.main.async(qos: .userInteractive) { [weak self, weak cellView] in
                guard let self = self, let cellView = cellView else { return }
                
                self.stringValue = originalValue
                cellView.isModified = false
                cellView.exitEditMode()
            }
        }
    }
}

// MARK: - TextCellView
class TextCellView: NSView, NSTextFieldDelegate, NSTextViewDelegate {
    var textField: EditableTextField!
    private var rightBorderView: NSView?
    private var bottomBorderView: NSView?
    private var foreignKeyIconView: NSImageView?
    private var lastPlaceholderString: String?

    private static weak var currentEditingCell: TextCellView?
    
    public var isSelected: Bool = false
    private var isEditing: Bool = false {
        didSet {
            if oldValue != isEditing {
                updateEditingAppearance()
                
                // Update global editing state
                if isEditing {
                    TextCellView.currentEditingCell = self
                } else if TextCellView.currentEditingCell === self {
                    TextCellView.currentEditingCell = nil
                }
            }
        }
    }
    private var isExitingEditMode = false
    private var rowIndex: Int = -1
    var columnName: String = ""
    private var dataType: String = ""
    var tableName: String = ""
    var constraintInfo: ConstraintInfo?
    
    // Weak reference to modification tracker to avoid retain cycles
    weak var modificationTracker: TableModificationTracker?
    fileprivate var originalValue: String = ""
    fileprivate var isModified: Bool = false {
        didSet {
            if oldValue != isModified {
                updateModificationAppearance()
            }
        }
    }
    var isMarkedForDeletion: Bool = false
    
    // Foreign key styling properties
    var isForeignKey: Bool {
        return constraintInfo?.isForeignKey ?? false
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextField()
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
        if isEditing { exitEditMode() }
        isModified = false
        lastPlaceholderString = nil
        // Clear static references
        if TextCellView.currentEditingCell === self {
            TextCellView.currentEditingCell = nil
        }
    }
    
    private func setupTextField() {
        textField = EditableTextField(frame: .zero)
        textField.configureForTableCell()
        textField.isSelectable = false
        textField.delegate = self
        textField.cellView = self  // Connect the text field to this cell view
        
        textField.cell = PaddedTextFieldCell()
        
        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        // Add padding through constraints instead of cell manipulation for better control
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0)
        ])
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        debugLog("🔍 Command during editing: \(NSStringFromSelector(commandSelector))")
        
        // Handle arrow keys during active editing
        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            debugLog("Tab key pressed - moving to next cell")
            handleTabKeyInEditMode()
            return true

        case #selector(NSResponder.insertBacktab(_:)):
            debugLog("Shift+Tab key pressed - moving to previous cell")
            handleShiftTabKeyInEditMode()
            return true

        case #selector(NSResponder.insertNewline(_:)):
            debugLog("Return key pressed - exiting edit mode")
            handleEnterKeyInEditMode()
            return true

        case #selector(NSResponder.moveUp(_:)):
            debugLog("⬆️ Up arrow pressed during editing")
            handleUpKeyDuringEditing()
            return true // We handled it, don't let the text view process it
            
        case #selector(NSResponder.moveDown(_:)):
            debugLog("⬇️ Down arrow pressed during editing")
            handleDownKeyDuringEditing()
            return true // We handled it, don't let the text view process it
            
        default:
            debugLog("🔄 Other command: \(NSStringFromSelector(commandSelector))")
            return false // Let the text view handle other commands
        }
    }
    
    
    // Public method for exiting edit mode (can be called externally)
    func exitEditModeForRow() {
        exitEditMode()
    }
    
    // Public method for entering edit mode
    func enterEditMode() {
        debugLog("Entering edit mode for cell at row: \(rowIndex), column: \(columnName)")
        
        // First, ensure no other cell is in edit mode
        exitEditModeForAllCells()
        
        enableEditMode()
        window?.makeFirstResponder(textField)
        normalizeFieldEditorSelection()
        
        debugLog("✅ Edit mode entered for cell at row: \(rowIndex), column: \(columnName)")
    }
    
    // Public method to reset modification state (useful for external control)
    func resetModificationState() {
        originalValue = textField.stringValue
        isModified = false
    }
    
    var isFieldEditable = false

    // Internal method to enable edit mode for individual cell
    private func enableEditMode() {
        guard !isEditing else { return }

        // Double-check that no other cell is editing
        if let currentEditingCell = TextCellView.currentEditingCell, currentEditingCell !== self {
            debugLog("Warning: Another cell is still in edit mode, forcing exit")
            currentEditingCell.exitEditMode()
        }
        
        // Store original value for modification tracking ONLY if this cell hasn't been modified yet
        // This preserves the true original value when returning to modified cells
        if !isModified {
            // This is a fresh cell that hasn't been modified yet
            originalValue = textField.stringValue
            debugLog("📝 Setting fresh originalValue: '\(originalValue)'")
        }
        
        // Enable editing UI
        textField.isEditable = true
        textField.isSelectable = true
        isEditing = true
    }
    
    fileprivate func exitEditMode() {
        debugLog("Exiting edit mode for cell: \(isEditing)")
        
        guard isEditing else {
            debugLog("⚠️ Cell is not in edit mode, nothing to exit")
            return
        }
        
        guard !isExitingEditMode else {
            debugLog("⚠️ Cell is already exiting edit mode")
            return
        }
        
        isExitingEditMode = true
        defer { isExitingEditMode = false }

        clearFieldEditorSelection()
        // Simply disable edit mode for this cell
        disableEditMode()
        
        // Remove first responder status from the shared field editor if this cell owns it.
        if let fieldEditor = textField.currentEditor(), window?.firstResponder === fieldEditor {
            debugLog("🔄 Removing first responder status from field editor")
            window?.makeFirstResponder(window) // Give focus back to window
        }
        
        // Notify that editing has ended
        handleEditingCompleted()
    }
    
    // Method to exit edit mode for all cells in the table
    private func exitEditModeForAllCells() {
        // If there's a currently editing cell, exit its edit mode
        if let currentEditingCell = TextCellView.currentEditingCell, currentEditingCell !== self {
            debugLog("🔄 Exiting edit mode for previous cell (row: \(currentEditingCell.rowIndex), col: \(currentEditingCell.columnName)) before entering new one")
            currentEditingCell.exitEditMode()
        } else if TextCellView.currentEditingCell == nil {
            debugLog("✅ No previous cell in edit mode")
        } else {
            debugLog("✅ Same cell - no need to exit")
        }
    }
    
    // Static method to get the currently editing cell (for debugging or external use)
    static func getCurrentEditingCell() -> TextCellView? {
        return currentEditingCell
    }
    
    // Static method to exit edit mode for any currently editing cell
    static func exitCurrentEditMode() {
        currentEditingCell?.exitEditMode()
    }
    
    // Internal method to disable edit mode for individual cell
    private func disableEditMode() {
        guard isEditing else { return }
        
        // Disable editing
        textField.isEditable = false
        textField.isSelectable = false
        
        // Update visual state
        isEditing = false
    }
    
    private func updateEditingAppearance() {
        debugLog("updateEditingAppearance - isEditing: \(isEditing)")
        textField.backgroundColor = NSColor.clear
        textField.drawsBackground = false
        
        // Ensure modification appearance is updated after editing changes
        updateModificationAppearance()
        invalidateActiveCellHighlight()
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

        updateForeignKeyIcon()
    }
    
    private func updateHighlightAppearance(shouldHighlight: Bool) {
        // Ensure the cell has a layer for animations
        if !wantsLayer {
            wantsLayer = true
        }
        
        if shouldHighlight {
            let highlightColor = NSColor.systemOrange.withAlphaComponent(0.45)
            
            let keyframeAnimation = CAKeyframeAnimation(keyPath: "backgroundColor")
            keyframeAnimation.values = [
                NSColor.clear.cgColor,
                highlightColor.cgColor,
                highlightColor.cgColor,
                NSColor.clear.cgColor
            ]
            keyframeAnimation.keyTimes = [0.0, 0.15, 0.85, 1.0] // Hold highlight for most of the time
            keyframeAnimation.duration = 0.50
            keyframeAnimation.fillMode = .forwards
            keyframeAnimation.isRemovedOnCompletion = true
            
            layer?.add(keyframeAnimation, forKey: "pulseAnimation")
        }
    }
    
    private func updateForeignKeyIcon() {
        if isForeignKey {
            createForeignKeyIconIfNeeded()
            foreignKeyIconView?.isHidden = false
        } else {
            foreignKeyIconView?.isHidden = true
        }
    }
    
    private func createForeignKeyIconIfNeeded() {
        guard foreignKeyIconView == nil else { return }

        // Create the foreign key icon with symbol configuration to prevent color changes on selection
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(hierarchicalColor: NSColor.secondaryLabelColor))

        foreignKeyIconView = NSImageView()
        foreignKeyIconView?.image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: "Foreign Key")?
            .withSymbolConfiguration(config)
        foreignKeyIconView?.symbolConfiguration = config
        foreignKeyIconView?.translatesAutoresizingMaskIntoConstraints = false
        addSubview(foreignKeyIconView!)
        
        // Position the icon at the right edge of the cell
        NSLayoutConstraint.activate([
            foreignKeyIconView!.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            foreignKeyIconView!.centerYAnchor.constraint(equalTo: centerYAnchor),
            foreignKeyIconView!.widthAnchor.constraint(equalToConstant: 16),
            foreignKeyIconView!.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        // Adjust text field constraints to make room for the icon
        if let textFieldConstraints = textField.superview?.constraints.filter({ $0.firstItem === textField || $0.secondItem === textField }) {
            for constraint in textFieldConstraints {
                if constraint.firstAttribute == .trailing {
                    constraint.constant = -24 // Make room for the icon
                }
            }
        }
    }
    
    private func handleEditingCompleted() {
        // This is where you can add logic to save the edited value
        // For example, update your data model, send to database, etc.
        debugLog("Cell editing completed with value: \(textField.stringValue)")
        
        // Keep the modification state visible after editing is completed
        // The modification background should remain until the data is actually saved to the database
        // Don't reset isModified here - it should remain true to show the visual indication
        
        // You might want to notify a delegate or post a notification
        NotificationCenter.default.post(
            name: NSNotification.Name("CellEditingCompleted"),
            object: self,
            userInfo: [
                "newValue": textField.stringValue,
                "cell": self,
                "wasModified": textField.stringValue != originalValue
            ]
        )
    }
    
    // MARK: - NSTextFieldDelegate Methods
    func controlTextDidEndEditing(_ obj: Notification) {
        // Only exit edit mode if we're actually editing and the reason is appropriate
        guard isEditing else { return }
        
        if isExitingEditMode {
            debugLog("Skipping controlTextDidEndEditing during programmatic exit")
            return
        }

        // Tab/Shift-Tab/Enter are handled in control(_:textView:doCommandBy:)
        // This is called for other ways editing can end (e.g., clicking outside)
        let finalValue = textField.stringValue
        if let tracker = modificationTracker, rowIndex >= 0 {
            if finalValue != originalValue {
                // Cell was changed - add to modification tracker and history
                tracker.updateCell(
                    rowIndex: rowIndex,
                    columnName: columnName,
                    newValue: finalValue,
                    originalValue: originalValue,
                    dataType: dataType
                )
                debugLog("📝 Cell editing completed: Row \(rowIndex), Column \(columnName), \(originalValue) → \(finalValue)")
            } else {
                // Cell was reverted to original value - remove from tracker
                tracker.resetCell(rowIndex: rowIndex, columnName: columnName)
                debugLog("🔄 Cell reverted to original: Row \(rowIndex), Column \(columnName)")
            }
        }

        exitEditMode()
    }
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        // Ensure we're in edit mode when editing begins
        if !isEditing {
            enterEditMode()
            debugLog("Text editing began - ensuring edit mode is active")
        }
        // Attach field editor delegate to block changes on read-only cells
        if !isFieldEditable, let editor = window?.fieldEditor(true, for: textField) as? NSTextView {
            editor.delegate = self
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        // Only update the visual state during typing, don't track history yet
        let currentValue = textField.stringValue
        let hasChanged = currentValue != originalValue
        
        // Update the visual state only when modification state changes
        if hasChanged != isModified {
            isModified = hasChanged
            debugLog("Text field modification state changed: \(isModified)")
        }
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
    
    func configure(queryRowInfo: QueryRowInfo?, columnInfo: QueryColumnInfo) {
        createBorderViewIfNeeded()
        
        guard let queryRowInfo = queryRowInfo else {
            textField.placeholderString = "(EMPTY)"
            return
        }
        
        textField.placeholderString = "(EMPTY)"
        
        // Handle nil values
        guard let value = queryRowInfo.value else {
            textField.placeholderString = !isFieldEditable ? "(Auto-generated)" : "(NULL)"
            textField.stringValue = ""
            return
        }
        
        switch value {
        case .string(let stringValue), .decimalString(let stringValue), .objectID(let stringValue):
            textField.stringValue = stringValue

            if stringValue.isEmpty {
                textField.placeholderString = "(EMPTY)"
            } else {
                textField.textColor = NSColor.controlTextColor
            }
        default:
            let stringRepresentation = value.description
            textField.stringValue = stringRepresentation
            textField.textColor = NSColor.controlTextColor
        }
    }
    
    // New method that includes tracking information
    func configure(queryRowInfo: QueryRowInfo?, columnInfo: QueryColumnInfo, rowIndex: Int, modificationTracker: TableModificationTracker?, constraintInfo: ConstraintInfo? = nil, tableName: String = "", shouldHighlight: Bool = false, isReadOnly: Bool = false) {
        createBorderViewIfNeeded()

        // Store tracking information
        self.rowIndex = rowIndex
        self.columnName = columnInfo.name
        self.dataType = columnInfo.dataType
        self.modificationTracker = modificationTracker
        self.constraintInfo = constraintInfo
        self.tableName = tableName
        self.isFieldEditable = !isReadOnly
        
        if let modification = modificationTracker?.getRowModification(for: rowIndex), modification.type == .delete {
            self.isMarkedForDeletion = true
        } else {
            self.isMarkedForDeletion = false
        }
        
        // Check if this row is a new insert row
        let isInsertRow = modificationTracker?.getRowModification(for: rowIndex)?.type == .insert

        // Check if this cell has existing modifications
        if let tracker = modificationTracker,
           let cellMod = tracker.getCellModification(rowIndex: rowIndex, columnName: columnInfo.name) {
            // Use the modified value instead of the original
            textField.stringValue = cellMod.newValue
            originalValue = cellMod.originalValue
            // For insert rows, always show as modified; otherwise check if value changed
            isModified = isInsertRow || cellMod.hasChanged

            // Ensure the modification appearance is applied immediately
            updateModificationAppearance()
        } else {
            // Configure normally
            configure(queryRowInfo: queryRowInfo, columnInfo: columnInfo)
            // For insert rows without cell modifications, still show as modified
            isModified = isInsertRow
            updateModificationAppearance()
        }
        
        // Apply or clear real-time highlighting
        updateHighlightAppearance(shouldHighlight: shouldHighlight)
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
            rightBorderView!.trailingAnchor.constraint(equalTo: trailingAnchor),
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
            bottomBorderView!.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorderView!.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorderView!.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorderView!.heightAnchor.constraint(equalToConstant: 1.0)
        ])
    }

    private func invalidateActiveCellHighlight() {
        guard let tableView = findTableView() else {
            return
        }

        let row = tableView.row(for: self)
        if row >= 0, let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
            rowView.needsDisplay = true
        }

        tableView.needsDisplay = true
    }
    
    override func viewWillDraw() {
        let currentPlaceholder = self.textField.placeholderString
        if currentPlaceholder != lastPlaceholderString {
            lastPlaceholderString = currentPlaceholder
            if let placeholder = currentPlaceholder, !placeholder.isEmpty {
                self.textField.placeholderAttributedString = NSAttributedString(
                    string: placeholder,
                    attributes: [.foregroundColor: NSColor.placeholderTextColor]
                )
            }
        }
        super.viewWillDraw()
    }
}


extension TextCellView: TableForeignKeyCell {
    var isForeignKeyCell: Bool {
        isForeignKey
    }

    func containsForeignKeyHit(point: NSPoint) -> Bool {
        let iconArea = NSRect(x: bounds.width - 24, y: 0, width: 24, height: bounds.height)
        return iconArea.contains(point)
    }
}

extension TextCellView {
    func handleTabKeyInEditMode() {
        debugLog("🔄 Handling Tab key - navigating to next cell")
        
        // Save current changes first
        saveCurrentChanges()
        
        // Navigate to next cell
        navigateToCell(direction: .next)
    }
    
    func handleShiftTabKeyInEditMode() {
        debugLog("🔄 Handling Shift+Tab key - navigating to previous cell")
        
        // Save current changes first
        saveCurrentChanges()
        
        // Navigate to previous cell
        navigateToCell(direction: .previous)
    }
    
    func handleEnterKeyInEditMode() {
        debugLog("🔄 Handling Enter key - navigating down")
        
        // Save current changes first
        saveCurrentChanges()
        
        exitEditMode()
    }
    
    
    func handleUpKeyInEditMode() {
        debugLog("🔄 Handling Up arrow key - navigating up")
        
        // Save current changes first
        saveCurrentChanges()
        
        forceEnterEditMode()
        // Navigate up
        navigateToCell(direction: .up)
    }
    
    func handleDownKeyInEditMode() {
        debugLog("🔄 Handling Down arrow key - navigating down")
        
        // Save current changes first
        saveCurrentChanges()
        
        forceEnterEditMode()
        // Navigate down (same as Enter)
        navigateToCell(direction: .down)
    }
    
    func handleUpKeyDuringEditing() {
        // Save current changes and navigate up
        saveCurrentChanges()
        
        // Check if we're at the first line of a multi-line text field
        let textView = textField.currentEditor() as? NSTextView
        let selectedRange = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
        
        // If cursor is at the beginning or this is single-line, navigate to previous row
        if selectedRange.location == 0 || textField.usesSingleLineMode {
            navigateToCell(direction: .up)
        }
    }
    
    private func handleDownKeyDuringEditing() {
        // Save current changes and navigate down
        saveCurrentChanges()
        
        // Check if we're at the last line of a multi-line text field
        let textView = textField.currentEditor() as? NSTextView
        let selectedRange = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
        let textLength = textField.stringValue.count
        
        // If cursor is at the end or this is single-line, navigate to next row
        if selectedRange.location == textLength || textField.usesSingleLineMode {
            navigateToCell(direction: .down)
        }
    }

    private func saveCurrentChanges() {
        // Save current changes to modification tracker
        if let tracker = modificationTracker, rowIndex >= 0 {
            let finalValue = textField.stringValue
            if finalValue != originalValue {
                // Cell was changed - add to modification tracker
                tracker.updateCell(
                    rowIndex: rowIndex,
                    columnName: columnName,
                    newValue: finalValue,
                    originalValue: originalValue,
                    dataType: dataType
                )
                debugLog("💾 Saved changes: \(originalValue) → \(finalValue)")
            } else {
                // Cell was reverted to original value - remove from tracker
                tracker.resetCell(rowIndex: rowIndex, columnName: columnName)
                debugLog("🔄 Cell reverted to original: Row \(rowIndex), Column \(columnName)")
            }
        }
    }
    
    private enum NavigationDirection {
        case next, previous, down, up
    }
    
    func forceEnterEditMode() {
        debugLog("🔧 Force entering edit mode for cell at (\(rowIndex), \(columnName))")
        
        // Ensure we're not already editing
        if isEditing {
            debugLog("Already in edit mode")
            return
        }
        // First, ensure no other cell is in edit mode
        exitEditModeForAllCells()
        
        // Store original value
        originalValue = textField.stringValue
        
        // Enable editing directly
        textField.isEditable = true
        
        // Set edit state
        isEditing = true
        
        // Force first responder
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self.textField)
            self.normalizeFieldEditorSelection()
            debugLog("🔧 Forced edit mode complete")
        }
    }

    private func normalizeFieldEditorSelection() {
        guard let editor = window?.fieldEditor(true, for: textField) as? NSTextView else {
            return
        }

        if !isFieldEditable {
            editor.delegate = self
        }

        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: textField.bounds.height)
        editor.textContainerInset = .zero

        if let scrollView = editor.enclosingScrollView {
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.borderType = .noBorder
        }

        if let textContainer = editor.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = true
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: textField.bounds.height)
            textContainer.lineFragmentPadding = 0
        }

        let insertionLocation = textField.stringValue.utf16.count
        editor.setSelectedRange(NSRange(location: insertionLocation, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
    }

    private func clearFieldEditorSelection() {
        guard let editor = textField.currentEditor() as? NSTextView else {
            return
        }

        editor.setSelectedRange(NSRange(location: 0, length: 0))
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
        var nextRow = currentRow
        var shouldMove = true
        
        switch direction {
        case .next:
            nextColumn = currentColumn + 1
            // Stop at last column instead of wrapping
            if nextColumn >= tableView.numberOfColumns {
                shouldMove = false
                debugLog("At last column - staying in current cell")
            }
            
        case .previous:
            nextColumn = currentColumn - 1
            // Stop at first column instead of wrapping
            if nextColumn < 0 {
                shouldMove = false
                debugLog("At first column - staying in current cell")
            }
            
        case .down:
            nextRow = currentRow + 1
            // Stop at last row instead of wrapping
            if nextRow >= tableView.numberOfRows {
                shouldMove = false
                debugLog("At last row - staying in current cell")
            }
            
        case .up:
            nextRow = currentRow - 1
            // Stop at first row instead of wrapping
            if nextRow < 0 {
                shouldMove = false
                debugLog("At first row - staying in current cell")
            }
        }
        
        // Only navigate if we should move
        if shouldMove {
            debugLog("🎯 Navigating from (\(currentRow), \(currentColumn)) to (\(nextRow), \(nextColumn))")
            
            // Exit edit mode for current cell immediately
            exitEditMode()
            
            // Select the next cell
            tableView.selectCell(row: nextRow, column: nextColumn)
            
            // Enter edit mode for the next cell
            if tableView.view(atColumn: nextColumn, row: nextRow, makeIfNecessary: false) is TextCellView {
                // Use a small delay to ensure the current cell has fully exited edit mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    // Route through tableView to respect read-only redirects
                    tableView.enterEditModeForCell(row: nextRow, column: nextColumn)
                    debugLog("✅ Successfully navigated to new cell")
                }
            } else {
                debugLog("❌ Could not find next cell view")
            }
        }
    }
}

// MARK: - NSTextViewDelegate (block edits on read-only cells)
extension TextCellView {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        return isFieldEditable
    }
}
