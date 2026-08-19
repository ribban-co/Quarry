//
//  SchemaModificationTracker.swift
//  Quarry
//
//  Schema modification tracking for columns and indexes
//

import Foundation
import SwiftUI

// MARK: - Modification Types

enum SchemaModificationType: Equatable, Sendable {
    case addColumn
    case modifyColumn
    case dropColumn
    case createIndex
    case modifyIndex
    case dropIndex
}

// MARK: - Column Modification

struct ColumnModification: Equatable, Identifiable, Sendable {
    let id = UUID()
    let type: SchemaModificationType
    let timestamp: Date

    // For add/modify
    var column: DatabaseSchemaInfo?

    // For modify/drop
    var originalColumn: DatabaseSchemaInfo?
    var columnName: String?

    init(type: SchemaModificationType, column: DatabaseSchemaInfo?, originalColumn: DatabaseSchemaInfo? = nil) {
        self.type = type
        self.timestamp = Date()
        self.column = column
        self.originalColumn = originalColumn
        // For modify operations, use the original column name (the current name in the database)
        // For add operations, use the new column name
        // For drop operations, use whichever is available
        if type == .modifyColumn {
            self.columnName = originalColumn?.columnName ?? column?.columnName
        } else {
            self.columnName = column?.columnName ?? originalColumn?.columnName
        }
    }

    var displayName: String {
        return columnName ?? "Unknown"
    }

    static func == (lhs: ColumnModification, rhs: ColumnModification) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Index Modification

struct IndexModification: Equatable, Identifiable, Sendable {
    let id = UUID()
    let type: SchemaModificationType
    let timestamp: Date

    // For create/modify
    var index: DatabaseIndexInfo?

    // For modify/drop
    var originalIndex: DatabaseIndexInfo?
    var indexName: String?

    init(type: SchemaModificationType, index: DatabaseIndexInfo?, originalIndex: DatabaseIndexInfo? = nil, indexName: String? = nil) {
        self.type = type
        self.timestamp = Date()
        self.index = index
        self.originalIndex = originalIndex
        // For modify operations, use the original index name (the current name in the database)
        // For create operations, use the new index name
        // For drop operations, use whichever is available
        if type == .modifyIndex {
            self.indexName = originalIndex?.name ?? index?.name
        } else {
            self.indexName = indexName ?? index?.name ?? originalIndex?.name
        }
    }

    var displayName: String {
        return indexName ?? "Unknown"
    }

    static func == (lhs: IndexModification, rhs: IndexModification) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Table Rename

struct TableRename: Equatable, Sendable {
    let oldName: String
    let newName: String
}

struct SchemaModificationPlan: Sendable {
    let columnAdditions: [ColumnModification]
    let columnUpdates: [ColumnModification]
    let columnDeletions: [ColumnModification]
    let indexAdditions: [IndexModification]
    let indexUpdates: [IndexModification]
    let indexDeletions: [IndexModification]
}

// MARK: - Schema Modification Tracker

@Observable @MainActor class SchemaModificationTracker {
    private(set) var columnModifications: [ColumnModification] = []
    private(set) var indexModifications: [IndexModification] = []
    private(set) var tableRename: TableRename?
    private var modificationHistory: [Any] = [] // Stores ColumnModification or IndexModification

    // MARK: - Computed Properties

    var hasModifications: Bool {
        return !columnModifications.isEmpty || !indexModifications.isEmpty || tableRename != nil
    }

    var totalModificationCount: Int {
        return columnModifications.count + indexModifications.count + (tableRename != nil ? 1 : 0)
    }

    var canUndo: Bool {
        return !modificationHistory.isEmpty
    }

    var columnAdditions: [ColumnModification] {
        return columnModifications.filter { $0.type == .addColumn }
    }

    var columnUpdates: [ColumnModification] {
        return columnModifications.filter { $0.type == .modifyColumn }
    }

    var columnDeletions: [ColumnModification] {
        return columnModifications.filter { $0.type == .dropColumn }
    }

    var hasPendingDeletions: Bool {
        return !columnDeletions.isEmpty
    }

    var pendingDeletionCount: Int {
        return columnDeletions.count
    }

    var hasPendingIndexDeletions: Bool {
        return !indexDeletions.isEmpty
    }

    var pendingIndexDeletionCount: Int {
        return indexDeletions.count
    }

    var pendingIndexAdditionCount: Int {
        return indexAdditions.count
    }

    var indexAdditions: [IndexModification] {
        return indexModifications.filter { $0.type == .createIndex }
    }

    var indexUpdates: [IndexModification] {
        return indexModifications.filter { $0.type == .modifyIndex }
    }

    var indexDeletions: [IndexModification] {
        return indexModifications.filter { $0.type == .dropIndex }
    }

    var pendingIndexUpdateCount: Int {
        return indexUpdates.count
    }

    func snapshot() -> SchemaModificationPlan {
        SchemaModificationPlan(
            columnAdditions: columnAdditions,
            columnUpdates: columnUpdates,
            columnDeletions: columnDeletions,
            indexAdditions: indexAdditions,
            indexUpdates: indexUpdates,
            indexDeletions: indexDeletions
        )
    }

    // MARK: - Column Operations

    func trackColumnAddition(_ column: DatabaseSchemaInfo) {
        let modification = ColumnModification(type: .addColumn, column: column)
        columnModifications.append(modification)
        modificationHistory.append(modification)
        debugLog("📝 Column addition tracked: \(column.columnName)")
    }

    /// Update an existing column addition with new values (e.g., when user edits column name/type)
    func updateColumnAddition(originalName: String, updatedColumn: DatabaseSchemaInfo) {
        // Find and update the existing addition
        if let index = columnModifications.firstIndex(where: { $0.type == .addColumn && $0.columnName == originalName }) {
            // Create a new modification with updated column but same ID for undo tracking
            let newModification = ColumnModification(type: .addColumn, column: updatedColumn)
            columnModifications[index] = newModification
            debugLog("📝 Column addition updated: \(originalName) → \(updatedColumn.columnName)")
        }
    }

    func trackColumnModification(original: DatabaseSchemaInfo, modified: DatabaseSchemaInfo) {
        // Remove any existing modification for this column
        columnModifications.removeAll { $0.columnName == original.columnName }

        let modification = ColumnModification(type: .modifyColumn, column: modified, originalColumn: original)
        columnModifications.append(modification)
        modificationHistory.append(modification)
        debugLog("📝 Column modification tracked: \(original.columnName)")
    }

    func trackColumnDeletion(_ column: DatabaseSchemaInfo) {
        // If this was a newly added column, just remove the addition
        if let index = columnModifications.firstIndex(where: { $0.type == .addColumn && $0.columnName == column.columnName }) {
            let removed = columnModifications.remove(at: index)
            modificationHistory.append(removed)
            debugLog("📝 Removed pending column addition: \(column.columnName)")
            return
        }

        // Otherwise, mark for deletion
        let modification = ColumnModification(type: .dropColumn, column: nil, originalColumn: column)
        columnModifications.append(modification)
        modificationHistory.append(modification)
        debugLog("📝 Column deletion tracked: \(column.columnName)")
    }

    func removeColumnModification(for columnName: String) {
        columnModifications.removeAll { $0.columnName == columnName }
        debugLog("🗑️ Removed column modification: \(columnName)")
    }

    func getColumnModification(for columnName: String) -> ColumnModification? {
        return columnModifications.first { $0.columnName == columnName }
    }

    func isColumnModified(_ columnName: String) -> Bool {
        return columnModifications.contains { $0.columnName == columnName }
    }

    func isColumnMarkedForDeletion(_ columnName: String) -> Bool {
        return columnModifications.contains { $0.type == .dropColumn && $0.columnName == columnName }
    }

    func isColumnNew(_ columnName: String) -> Bool {
        return columnModifications.contains { $0.type == .addColumn && $0.columnName == columnName }
    }

    /// Check if a column is new by ordinal position (more reliable when name changes)
    func isColumnNewByOrdinal(_ ordinalPosition: Int?) -> Bool {
        guard let position = ordinalPosition else { return false }
        return columnModifications.contains { $0.type == .addColumn && $0.column?.ordinalPosition == position }
    }

    /// Get the current column name for a new column by ordinal position
    func getNewColumnName(byOrdinal ordinalPosition: Int?) -> String? {
        guard let position = ordinalPosition else { return nil }
        return columnModifications.first { $0.type == .addColumn && $0.column?.ordinalPosition == position }?.columnName
    }

    // MARK: - Index Operations

    func trackIndexAddition(_ index: DatabaseIndexInfo) {
        let modification = IndexModification(type: .createIndex, index: index)
        indexModifications.append(modification)
        modificationHistory.append(modification)
        debugLog("📝 Index addition tracked: \(index.name)")
    }

    /// Update an existing index addition with new values (e.g., when user edits index name)
    func updateIndexAddition(originalName: String, updatedIndex: DatabaseIndexInfo) {
        // Find and update the existing addition
        if let idx = indexModifications.firstIndex(where: { $0.type == .createIndex && $0.indexName == originalName }) {
            let newModification = IndexModification(type: .createIndex, index: updatedIndex)
            indexModifications[idx] = newModification
            debugLog("📝 Index addition updated: \(originalName) → \(updatedIndex.name)")
        }
    }

    func trackIndexModification(original: DatabaseIndexInfo, modified: DatabaseIndexInfo) {
        // Remove any existing modification for this index
        indexModifications.removeAll { $0.indexName == original.name && $0.type == .modifyIndex }

        let modification = IndexModification(type: .modifyIndex, index: modified, originalIndex: original)
        indexModifications.append(modification)
        modificationHistory.append(modification)
        debugLog("📝 Index modification tracked: \(original.name)")
    }

    func trackIndexDeletion(_ index: DatabaseIndexInfo) {
        // If this was a newly added index, just remove the addition
        if let idx = indexModifications.firstIndex(where: { $0.type == .createIndex && $0.indexName == index.name }) {
            let removed = indexModifications.remove(at: idx)
            modificationHistory.append(removed)
            debugLog("📝 Removed pending index addition: \(index.name)")
            return
        }

        // Otherwise, mark for deletion
        let modification = IndexModification(type: .dropIndex, index: nil, indexName: index.name)
        indexModifications.append(modification)
        modificationHistory.append(modification)
        debugLog("📝 Index deletion tracked: \(index.name)")
    }

    func removeIndexModification(for indexName: String) {
        indexModifications.removeAll { $0.indexName == indexName }
        debugLog("🗑️ Removed index modification: \(indexName)")
    }

    func getIndexModification(for indexName: String) -> IndexModification? {
        return indexModifications.first { $0.indexName == indexName }
    }

    func isIndexModified(_ indexName: String) -> Bool {
        return indexModifications.contains { $0.indexName == indexName }
    }

    func isIndexMarkedForDeletion(_ indexName: String) -> Bool {
        return indexModifications.contains { $0.type == .dropIndex && $0.indexName == indexName }
    }

    func isIndexNew(_ indexName: String) -> Bool {
        return indexModifications.contains { $0.type == .createIndex && $0.indexName == indexName }
    }

    func isIndexUpdated(_ indexName: String) -> Bool {
        return indexModifications.contains { $0.type == .modifyIndex && $0.indexName == indexName }
    }

    // MARK: - Table Rename Operations

    func trackTableRename(from oldName: String, to newName: String) {
        tableRename = TableRename(oldName: oldName, newName: newName)
        debugLog("📝 Table rename tracked: \(oldName) → \(newName)")
    }

    func removeTableRename() {
        tableRename = nil
        debugLog("🗑️ Removed table rename")
    }

    // MARK: - Undo Functionality

    func undo() -> Bool {
        guard let lastModification = modificationHistory.popLast() else {
            debugLog("❌ No modifications to undo")
            return false
        }

        if let columnMod = lastModification as? ColumnModification {
            // Remove the column modification
            if let index = columnModifications.firstIndex(where: { $0.id == columnMod.id }) {
                columnModifications.remove(at: index)
                debugLog("⏪ Undid column modification: \(columnMod.displayName)")
                return true
            }
        } else if let indexMod = lastModification as? IndexModification {
            // Remove the index modification
            if let index = indexModifications.firstIndex(where: { $0.id == indexMod.id }) {
                indexModifications.remove(at: index)
                debugLog("⏪ Undid index modification: \(indexMod.displayName)")
                return true
            }
        }

        return false
    }

    // MARK: - Reset Operations

    func clearAll() {
        columnModifications.removeAll()
        indexModifications.removeAll()
        tableRename = nil
        modificationHistory.removeAll()
        debugLog("🗑️ Cleared all schema modifications")
    }

    func clearColumnModifications() {
        columnModifications.removeAll()
        modificationHistory.removeAll { $0 is ColumnModification }
        debugLog("🗑️ Cleared column modifications")
    }

    func clearIndexModifications() {
        indexModifications.removeAll()
        modificationHistory.removeAll { $0 is IndexModification }
        debugLog("🗑️ Cleared index modifications")
    }

    func clearColumnDeletions() {
        columnModifications.removeAll { $0.type == .dropColumn }
        modificationHistory.removeAll {
            ($0 as? ColumnModification)?.type == .dropColumn
        }
        debugLog("🗑️ Cleared column deletions")
    }

    // MARK: - Validation

    func validateModifications() -> [String] {
        var errors: [String] = []

        // Check for duplicate column names in additions
        let newColumnNames = columnAdditions.compactMap { $0.column?.columnName }
        let duplicates = Dictionary(grouping: newColumnNames, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys

        if !duplicates.isEmpty {
            errors.append("Duplicate column names: \(duplicates.joined(separator: ", "))")
        }

        // Check for duplicate index names in additions
        let newIndexNames = indexAdditions.compactMap { $0.index?.name }
        let indexDuplicates = Dictionary(grouping: newIndexNames, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys

        if !indexDuplicates.isEmpty {
            errors.append("Duplicate index names: \(indexDuplicates.joined(separator: ", "))")
        }

        return errors
    }

    // MARK: - Description for Debugging

    func printSummary() {
        debugLog("📋 Schema Modification Summary:")
        debugLog("  Column Additions: \(columnAdditions.count)")
        debugLog("  Column Updates: \(columnUpdates.count)")
        debugLog("  Column Deletions: \(columnDeletions.count)")
        debugLog("  Index Additions: \(indexAdditions.count)")
        debugLog("  Index Deletions: \(indexDeletions.count)")
        debugLog("  Total: \(totalModificationCount) modifications")
    }
}
