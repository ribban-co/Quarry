//
//  ModificationTracker.swift
//  Quarry
//
//  Created by Fauzaan on 06/22/25.
//
import Foundation
import SwiftUI

// MARK: - Cell Modification Model
struct CellModification {
    let rowIndex: Int
    let columnName: String
    let originalValue: String
    var newValue: String
    let dataType: String
    
    var hasChanged: Bool {
        return originalValue != newValue
    }
}

// MARK: - Modification History Entry
struct ModificationHistoryEntry {
    let id = UUID()
    let timestamp: Date
    let rowIndex: Int
    let columnName: String
    let previousValue: String
    let newValue: String
    let dataType: String

    init(rowIndex: Int, columnName: String, previousValue: String, newValue: String, dataType: String) {
        self.timestamp = Date()
        self.rowIndex = rowIndex
        self.columnName = columnName
        self.previousValue = previousValue
        self.newValue = newValue
        self.dataType = dataType
    }
}

// MARK: - Row History Entry
struct RowHistoryEntry: @unchecked Sendable {
    let id = UUID()
    let timestamp: Date
    let rowIndex: Int
    let type: RowModificationType
    let rowData: [String: Any]?

    init(rowIndex: Int, type: RowModificationType, rowData: [String: Any]? = nil) {
        self.timestamp = Date()
        self.rowIndex = rowIndex
        self.type = type
        self.rowData = rowData
    }
}

enum RowModificationType {
    case update
    case insert
    case delete
}

// MARK: - Row Modification Model
struct RowModification {
    let rowIndex: Int
    var type: RowModificationType
    var cellModifications: [String: CellModification] = [:]
    
    var hasModifications: Bool {
        return cellModifications.values.contains { $0.hasChanged }
    }
    
    var modifiedColumns: [String] {
        return cellModifications.compactMap { key, value in
            value.hasChanged ? key : nil
        }
    }
    
    mutating func updateCell(columnName: String, newValue: String, originalValue: String, dataType: String) {
        cellModifications[columnName] = CellModification(
            rowIndex: rowIndex,
            columnName: columnName,
            originalValue: originalValue,
            newValue: newValue,
            dataType: dataType
        )
    }
    
    mutating func removeCell(columnName: String) {
        cellModifications.removeValue(forKey: columnName)
    }
    
    func getModification(for columnName: String) -> CellModification? {
        return cellModifications[columnName]
    }
}

// MARK: - Table Modification Tracker
@Observable @MainActor class TableModificationTracker {
    private var rowModifications: [Int: RowModification] = [:]
    private var modificationHistory: [ModificationHistoryEntry] = []
    private var rowHistory: [RowHistoryEntry] = []

    // Delegate to notify about undo events
    weak var undoDelegate: TableModificationUndoDelegate?
    weak var rowUndoDelegate: RowUndoDelegate?
    
    // Public computed properties
    var modifiedRowCount: Int {
        return rowModifications.values.filter { $0.hasModifications || $0.type == .insert }.count
    }
    
    var allModifications: [RowModification] {
        return rowModifications.values.filter { $0.hasModifications || $0.type == .insert || $0.type == .delete }
    }
    
    var hasModifications: Bool {
        return modifiedRowCount > 0
    }
    
    var hasPendingDeletions: Bool {
        return rowModifications.values.contains { $0.type == .delete }
    }
    
    var pendingDeletionCount: Int {
        return rowModifications.values.filter { $0.type == .delete }.count
    }
    
    var canUndo: Bool {
        return !modificationHistory.isEmpty || !rowHistory.isEmpty
    }
    
    var historyCount: Int {
        return modificationHistory.count
    }
    
    // MARK: - Modification Management
    func markAsNewRow(rowIndex: Int, initialData: [String: Any]) {
        var newRow = RowModification(rowIndex: rowIndex, type: .insert)
        for (key, value) in initialData {
            let stringValue = String(describing: value)
            newRow.cellModifications[key] = CellModification(
                rowIndex: rowIndex,
                columnName: key,
                originalValue: stringValue,
                newValue: stringValue,
                dataType: ""
            )
        }
        rowModifications[rowIndex] = newRow

        let historyEntry = RowHistoryEntry(rowIndex: rowIndex, type: .insert, rowData: initialData)
        rowHistory.append(historyEntry)
        debugLog("rowModification: \(rowModifications)")
    }
    
    func deleteRow(rowIndex: Int) {
        if rowModifications[rowIndex] != nil {
            rowModifications.removeValue(forKey: rowIndex)
        }
    }
    
    func markAsDeleted(rowIndex: Int) {
        if var row = rowModifications[rowIndex] {
            if row.type == .delete {
                // If it's already marked as delete, unmark it
                row.type = .update // Or revert to its original state if you track that
                rowModifications[rowIndex] = row
            } else {
                // If it's an update or insert, mark it as delete
                row.type = .delete
                rowModifications[rowIndex] = row
            }
        } else {
            // If there's no modification yet, create a new one and mark it as delete
            rowModifications[rowIndex] = RowModification(rowIndex: rowIndex, type: .delete)
        }
    }
    
    func updateCell(rowIndex: Int, columnName: String, newValue: String, originalValue: String, dataType: String) {
        debugLog("updateCell: \(rowModifications)")
        // Check if there's already a modification for this cell
        let existingModification = getCellModification(rowIndex: rowIndex, columnName: columnName)
        
        if let existing = existingModification {
            // Cell already has a modification - we're updating an existing change
            // Only add to history if the new value is different from current modified value
            if existing.newValue != newValue {
                let historyEntry = ModificationHistoryEntry(
                    rowIndex: rowIndex,
                    columnName: columnName,
                    previousValue: existing.newValue,
                    newValue: newValue,
                    dataType: dataType
                )
                modificationHistory.append(historyEntry)
                debugLog("📝 Updated existing modification: Row \(rowIndex), Column \(columnName), \(existing.newValue) → \(newValue)")
            }
        } else {
            // New modification - add to history
            let historyEntry = ModificationHistoryEntry(
                rowIndex: rowIndex,
                columnName: columnName,
                previousValue: originalValue,
                newValue: newValue,
                dataType: dataType
            )
            modificationHistory.append(historyEntry)
            debugLog("📝 New cell modification: Row \(rowIndex), Column \(columnName), \(originalValue) → \(newValue)")
        }
        
        if rowModifications[rowIndex] == nil {
            rowModifications[rowIndex] = RowModification(rowIndex: rowIndex, type: .update)
        }
        
        rowModifications[rowIndex]?.updateCell(
            columnName: columnName,
            newValue: newValue,
            originalValue: originalValue,
            dataType: dataType
        )
        
        // Remove the row modification if no changes remain
        if let rowMod = rowModifications[rowIndex], !rowMod.hasModifications, rowMod.type == .update {
            rowModifications.removeValue(forKey: rowIndex)
        }
    }
    
    func resetCell(rowIndex: Int, columnName: String) {
        // Get the current modified value before resetting
        if let cellMod = getCellModification(rowIndex: rowIndex, columnName: columnName) {
            let historyEntry = ModificationHistoryEntry(
                rowIndex: rowIndex,
                columnName: columnName,
                previousValue: cellMod.newValue,
                newValue: cellMod.originalValue,
                dataType: cellMod.dataType
            )
            modificationHistory.append(historyEntry)
            debugLog("🔄 Cell reset to original: Row \(rowIndex), Column \(columnName), \(cellMod.newValue) → \(cellMod.originalValue)")
        }
        
        rowModifications[rowIndex]?.removeCell(columnName: columnName)
        
        // Remove the row modification if no changes remain
        if let rowMod = rowModifications[rowIndex], !rowMod.hasModifications, rowMod.type == .update {
            rowModifications.removeValue(forKey: rowIndex)
        }
    }
    
    func resetRow(rowIndex: Int) {
        // Add reset entries to history for all modified cells in this row
        if let rowMod = rowModifications[rowIndex] {
            for (_, cellMod) in rowMod.cellModifications where cellMod.hasChanged {
                let historyEntry = ModificationHistoryEntry(
                    rowIndex: rowIndex,
                    columnName: cellMod.columnName,
                    previousValue: cellMod.newValue,
                    newValue: cellMod.originalValue,
                    dataType: cellMod.dataType
                )
                modificationHistory.append(historyEntry)
            }
        }
        
        rowModifications.removeValue(forKey: rowIndex)
    }
    
    func resetAllModifications() {
        resetAllModifications(of: .insert, .update, .delete)
    }
    
    func resetAllModifications(of types: RowModificationType...) {
        let typeSet = Set(types)
        guard !typeSet.isEmpty else { return }
        
        // Collect changes to avoid mutating while iterating
        var rowsToRemove: [Int] = []
        var rowsToUpdate: [(Int, RowModification)] = []
        
        for (rowIndex, rowMod) in rowModifications {
            guard typeSet.contains(rowMod.type) else { continue }
            var working = rowMod
            
            switch rowMod.type {
            case .update:
                // Log history for changed cells, then remove the row modification
                for (_, cellMod) in working.cellModifications where cellMod.hasChanged {
                    let historyEntry = ModificationHistoryEntry(
                        rowIndex: cellMod.rowIndex,
                        columnName: cellMod.columnName,
                        previousValue: cellMod.newValue,
                        newValue: cellMod.originalValue,
                        dataType: cellMod.dataType
                    )
                    modificationHistory.append(historyEntry)
                }
                rowsToRemove.append(rowIndex)
                
            case .insert:
                // Cancel the pending insert; no changed cells typically, just drop the row modification
                rowsToRemove.append(rowIndex)
                
            case .delete:
                // Unmark deletion. If there are no cell modifications, drop the entry; otherwise revert to .update
                if working.cellModifications.isEmpty {
                    rowsToRemove.append(rowIndex)
                } else {
                    working.type = .update
                    rowsToUpdate.append((rowIndex, working))
                }
            }
        }
        
        // Apply removals and updates
        for rowIndex in rowsToRemove {
            rowModifications.removeValue(forKey: rowIndex)
        }
        for (rowIndex, updated) in rowsToUpdate {
            rowModifications[rowIndex] = updated
        }
    }
    
    // MARK: - Undo Functionality
    func undo() -> Bool {
        let lastCellEntry = modificationHistory.last
        let lastRowEntry = rowHistory.last

        guard lastCellEntry != nil || lastRowEntry != nil else {
            debugLog("❌ No modifications to undo")
            return false
        }

        let shouldUndoRow: Bool
        if let cellEntry = lastCellEntry, let rowEntry = lastRowEntry {
            shouldUndoRow = rowEntry.timestamp >= cellEntry.timestamp
        } else {
            shouldUndoRow = lastRowEntry != nil
        }

        if shouldUndoRow, let rowEntry = rowHistory.popLast() {
            return undoRowOperation(rowEntry)
        } else if let cellEntry = modificationHistory.popLast() {
            return undoCellOperation(cellEntry)
        }

        return false
    }

    private func undoRowOperation(_ entry: RowHistoryEntry) -> Bool {
        switch entry.type {
        case .insert:
            debugLog("⏪ Undoing row insert at index \(entry.rowIndex)")
            rowModifications.removeValue(forKey: entry.rowIndex)
            rowUndoDelegate?.didUndoRowInsert(rowIndex: entry.rowIndex)
            return true
        case .delete:
            debugLog("⏪ Undoing row delete at index \(entry.rowIndex)")
            rowModifications.removeValue(forKey: entry.rowIndex)
            rowUndoDelegate?.didUndoRowDelete(rowIndex: entry.rowIndex, rowData: entry.rowData)
            return true
        case .update:
            return false
        }
    }

    private func undoCellOperation(_ lastEntry: ModificationHistoryEntry) -> Bool {
        debugLog("⏪ Undoing: Row \(lastEntry.rowIndex), Column \(lastEntry.columnName), \(lastEntry.newValue) → \(lastEntry.previousValue)")

        undoDelegate?.willUndoModification(
            rowIndex: lastEntry.rowIndex,
            columnName: lastEntry.columnName,
            fromValue: lastEntry.newValue,
            toValue: lastEntry.previousValue
        )

        let originalValue = findOriginalValue(rowIndex: lastEntry.rowIndex, columnName: lastEntry.columnName)

        if lastEntry.previousValue == originalValue {
            if rowModifications[lastEntry.rowIndex] != nil {
                rowModifications[lastEntry.rowIndex]?.removeCell(columnName: lastEntry.columnName)

                if let rowMod = rowModifications[lastEntry.rowIndex], !rowMod.hasModifications {
                    rowModifications.removeValue(forKey: lastEntry.rowIndex)
                }
            }
        } else {
            if rowModifications[lastEntry.rowIndex] == nil {
                rowModifications[lastEntry.rowIndex] = RowModification(rowIndex: lastEntry.rowIndex, type: .update)
            }

            rowModifications[lastEntry.rowIndex]?.updateCell(
                columnName: lastEntry.columnName,
                newValue: lastEntry.previousValue,
                originalValue: originalValue,
                dataType: lastEntry.dataType
            )
        }

        undoDelegate?.didUndoModification(
            rowIndex: lastEntry.rowIndex,
            columnName: lastEntry.columnName,
            newValue: lastEntry.previousValue
        )

        return true
    }
    
    private func findOriginalValue(rowIndex: Int, columnName: String) -> String {
        // Look through history to find the first entry for this cell (which would contain the original value)
        // We need to find the earliest entry for this cell
        var earliestEntry: ModificationHistoryEntry?
        for entry in modificationHistory {
            if entry.rowIndex == rowIndex && entry.columnName == columnName {
                if earliestEntry == nil || entry.timestamp < earliestEntry!.timestamp {
                    earliestEntry = entry
                }
            }
        }
        
        if let earliest = earliestEntry {
            return earliest.previousValue
        }
        
        // If not found in history, check current modifications
        if let cellMod = getCellModification(rowIndex: rowIndex, columnName: columnName) {
            return cellMod.originalValue
        }
        
        // Fallback - should not happen in normal operation
        return ""
    }
    
    func clearHistory() {
        modificationHistory.removeAll()
        rowHistory.removeAll()
        debugLog("🗑️ Cleared modification history")
    }
    
    func printHistory() {
        debugLog("📋 Modification History (\(modificationHistory.count) entries):")
        for (index, entry) in modificationHistory.enumerated() {
            debugLog("  \(index + 1). Row \(entry.rowIndex), \(entry.columnName): '\(entry.previousValue)' → '\(entry.newValue)'")
        }
    }
    
    // MARK: - Query Methods
    func getRowModification(for rowIndex: Int) -> RowModification? {
        return rowModifications[rowIndex]
    }
    
    func getCellModification(rowIndex: Int, columnName: String) -> CellModification? {
        return rowModifications[rowIndex]?.getModification(for: columnName)
    }
    
    func isRowModified(_ rowIndex: Int) -> Bool {
        return rowModifications[rowIndex]?.hasModifications ?? false
    }
    
    func isCellModified(rowIndex: Int, columnName: String) -> Bool {
        return getCellModification(rowIndex: rowIndex, columnName: columnName)?.hasChanged ?? false
    }

    // MARK: - Reconciliation with server data
    func reconcile(with updatedResult: QueryResult) {
        var updatedRows: [Int: RowModification] = [:]
        var rowsToRemove: [Int] = []
        
        for (rowIndex, var rowMod) in rowModifications {
            var changed = false
            for (colName, cellMod) in rowMod.cellModifications {
                guard cellMod.hasChanged else { continue }
                let serverAny = updatedResult.rawValue(row: rowIndex, column: colName)
                let serverString = serverAny.map { String(describing: $0) } ?? ""
                if serverString == cellMod.newValue {
                    // Server now has the same value; drop this cell modification silently
                    rowMod.cellModifications.removeValue(forKey: colName)
                    changed = true
                }
            }
            if changed {
                if rowMod.type == .update && !rowMod.hasModifications {
                    rowsToRemove.append(rowIndex)
                } else {
                    updatedRows[rowIndex] = rowMod
                }
            }
        }
        for idx in rowsToRemove { rowModifications.removeValue(forKey: idx) }
        for (idx, mod) in updatedRows { rowModifications[idx] = mod }
    }
    
    func reconcile(changedCells: [Int: Set<String>], in updatedResult: QueryResult) {
        var updatedRows: [Int: RowModification] = [:]
        var rowsToRemove: [Int] = []
        
        for (rowIndex, cols) in changedCells {
            guard var rowMod = rowModifications[rowIndex] else { continue }
            var changed = false
            for colName in cols {
                if let cellMod = rowMod.cellModifications[colName], cellMod.hasChanged {
                    let serverAny = updatedResult.rawValue(row: rowIndex, column: colName)
                    let serverString = serverAny.map { String(describing: $0) } ?? ""
                    if serverString == cellMod.newValue {
                        rowMod.cellModifications.removeValue(forKey: colName)
                        changed = true
                    }
                }
            }
            if changed {
                if rowMod.type == .update && !rowMod.hasModifications {
                    rowsToRemove.append(rowIndex)
                } else {
                    updatedRows[rowIndex] = rowMod
                }
            }
        }
        for idx in rowsToRemove { rowModifications.removeValue(forKey: idx) }
        for (idx, mod) in updatedRows { rowModifications[idx] = mod }
    }
}

// MARK: - Undo Delegate Protocol
@MainActor protocol TableModificationUndoDelegate: AnyObject {
    func willUndoModification(rowIndex: Int, columnName: String, fromValue: String, toValue: String)
    func didUndoModification(rowIndex: Int, columnName: String, newValue: String)
}

// MARK: - Row Undo Delegate Protocol
@MainActor protocol RowUndoDelegate: AnyObject {
    func didUndoRowInsert(rowIndex: Int)
    func didUndoRowDelete(rowIndex: Int, rowData: [String: Any]?)
}
