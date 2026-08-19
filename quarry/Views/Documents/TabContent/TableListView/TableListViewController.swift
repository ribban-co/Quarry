//
//  TableListViewController.swift
//  Quarry
//
//  Created by Fauzaan on 6/2/25.
//
import Foundation
import SwiftUI
import AppKit

struct TableListViewController: NSViewRepresentable {
    var selectedTab: DatabaseTab?
    let schema: DatabaseSchemaResult?
    let queryResult: QueryResult?
    let tableName: String
    let cacheNamespace: String?
    let onSort: ((String, Bool) -> Void)?
    let modificationTracker: TableModificationTracker?
    let needsToSelectLastRow: Bool
    let onDeleteNewRow: ((Int) -> Void)?
    let onForeignKeyNavigation: ((String, String, String) -> Void)?
    let highlightedFields: Set<String>
    let highlightedRows: Set<Int>
    let onRowSelected: (([String: QueryRowInfo]?) -> Void)?
    let onUndoRowInsert: ((Int) -> Void)?
    var showPaddingRows: Bool = true

    init(selectedTab: DatabaseTab? = nil, schema: DatabaseSchemaResult? = nil, queryResult: QueryResult?, tableName: String = "", cacheNamespace: String? = nil, onSort: ((String, Bool) -> Void)? = nil, modificationTracker: TableModificationTracker? = nil, needsToSelectLastRow: Bool = false, onDeleteNewRow: ((Int) -> Void)? = nil, onForeignKeyNavigation: ((String, String, String) -> Void)? = nil, highlightedFields: Set<String> = [], highlightedRows: Set<Int> = [], onRowSelected: (([String: QueryRowInfo]?) -> Void)? = nil, onUndoRowInsert: ((Int) -> Void)? = nil, showPaddingRows: Bool = true) {
        self.selectedTab = selectedTab
        self.schema = schema
        self.queryResult = queryResult
        self.tableName = tableName
        self.cacheNamespace = cacheNamespace
        self.onSort = onSort
        self.modificationTracker = modificationTracker
        self.needsToSelectLastRow = needsToSelectLastRow
        self.onDeleteNewRow = onDeleteNewRow
        self.onForeignKeyNavigation = onForeignKeyNavigation
        self.highlightedFields = highlightedFields
        self.highlightedRows = highlightedRows
        self.onRowSelected = onRowSelected
        self.onUndoRowInsert = onUndoRowInsert
        self.showPaddingRows = showPaddingRows
    }

    func makeCoordinator() -> TableCoordinator {
        return TableCoordinator(schema: schema, queryResult: queryResult, tableName: tableName, onSort: onSort, modificationTracker: modificationTracker, onDeleteNewRow: onDeleteNewRow, onForeignKeyNavigation: onForeignKeyNavigation, highlightedFields: highlightedFields, highlightedRows: highlightedRows, cacheNamespace: cacheNamespace ?? "", onRowSelected: onRowSelected, onUndoRowInsert: onUndoRowInsert, showPaddingRows: showPaddingRows)
    }
    
    func makeNSView(context: Context) -> NSView {
        return context.coordinator.setupTableView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if needsToSelectLastRow {
            context.coordinator.needsToSelectLastRow = true
        }
        // Pass current tab to coordinator for per-tab selection state
        context.coordinator.currentTab = selectedTab
        // Update data first, then apply highlighting
        context.coordinator.updateRows(queryResult, newSchema: schema)
        context.coordinator.updateHighlighting(fields: highlightedFields, rows: highlightedRows)
    }
    
    // Public method to set sorting state
    func setSortState(coordinator: Coordinator, column: String?, ascending: Bool) {
        coordinator.setSortState(column: column, ascending: ascending)
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
