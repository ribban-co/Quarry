//
//  SchemaModeView.swift
//  Quarry
//
//  Created by Fauzaan on 10/15/25.
//

import SwiftUI

struct SchemaModeView: View {
    let schema: DatabaseSchemaResult?
    let indexes: [DatabaseIndexInfo]?
    let tableName: String
    let schemaName: String?

    @Environment(\.colorScheme) var colorScheme
    @Environment(ConnectionInstance.self) private var instance

    @State private var splitRatio: CGFloat = 0.6
    @State private var searchText: String = ""
    @Binding var modificationTracker: SchemaModificationTracker
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showingSaveConfirmation: Bool = false
    @State private var showingCancelConfirmation: Bool = false
    @State private var currentSchema: DatabaseSchemaResult?
    @State private var currentIndexes: [DatabaseIndexInfo]?

    /// Merge existing schema columns with new columns from the tracker
    private var displayColumns: [DatabaseSchemaInfo] {
        var columns = currentSchema?.columns ?? []

        // Append new columns from tracker (not yet saved to DB)
        let newColumns = modificationTracker.columnAdditions.compactMap { $0.column }
        columns.append(contentsOf: newColumns)

        return columns
    }

    /// Merge existing indexes with new indexes from the tracker
    private var displayIndexes: [DatabaseIndexInfo] {
        var indexes = currentIndexes ?? []

        // Append new indexes from tracker (not yet saved to DB)
        let newIndexes = modificationTracker.indexAdditions.compactMap { $0.index }
        indexes.append(contentsOf: newIndexes)

        return indexes
    }

    var body: some View {
        VStack(spacing: 0) {
            SchemaModeViewHeader(
                tableName: tableName,
                searchText: $searchText,
                modificationTracker: $modificationTracker
            )

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Saving changes...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SplitView(.vertical, $splitRatio, dividerColor: Color(.separatorColor), minSize: 0) {
                    ShemaTableView(
                        columns: displayColumns,
                        searchText: searchText,
                        databaseType: instance.connection.databaseType,
                        modificationTracker: $modificationTracker
                    )
                } right: {
                    IndexTableView(
                        indexes: displayIndexes,
                        tableName: tableName,
                        searchText: searchText,
                        databaseType: instance.connection.databaseType,
                        modificationTracker: $modificationTracker
                    )
                }
            }

            // Action bar at bottom
//            SchemaModificationActionBar(
//                columnCount: currentSchema?.columns.count ?? 0,
//                hasModifications: modificationTracker.hasModifications,
//                modificationCount: modificationTracker.totalModificationCount,
//                canUndo: modificationTracker.canUndo,
//                onRefresh: handleRefresh,
//                onUndo: handleUndo,
//                onSave: handleSave,
//                onCancel: { showingCancelConfirmation = true }
//            )
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Discard Changes?", isPresented: $showingCancelConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                handleCancelModifications()
            }
        } message: {
            Text("Are you sure you want to discard all \(modificationTracker.totalModificationCount) pending modification\(modificationTracker.totalModificationCount == 1 ? "" : "s")?")
        }
        .onAppear {
            currentSchema = schema
            currentIndexes = indexes
        }
        .onChange(of: schema) { _, newSchema in
            // Update local state when parent schema changes (e.g., after refresh)
            currentSchema = newSchema
        }
        .onChange(of: indexes) { _, newIndexes in
            // Update local state when parent indexes changes
            currentIndexes = newIndexes
        }
        .onReceive(NotificationCenter.default.publisher(for: .schemaTableRefresh)) { _ in
            handleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .schemaAddColumn)) { _ in
            handleAddColumn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .indexTableRefresh)) { _ in
            handleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .indexAddIndex)) { _ in
            handleAddIndex()
        }
    }

    // MARK: - Actions

    private func handleRefresh() {
        Task {
            await refreshSchema()
        }
    }

    private func handleUndo() {
        _ = modificationTracker.undo()
    }

    private func handleSave() {
        Task {
            await saveModifications()
        }
    }

    private func handleCancelModifications() {
        modificationTracker.clearAll()
    }

    private func handleAddColumn() {
        // Create a new column with default values
        let newColumn = DatabaseSchemaInfo(
            ordinalPosition: (currentSchema?.columns.count ?? 0) + modificationTracker.columnAdditions.count + 1,
            columnName: generateUniqueColumnName(),
            dataType: "",
            formatType: "character varying",
            typeOid: 1043,
            isNullable: "YES",
            columnDefault: nil
        )

        // Track the addition
        modificationTracker.trackColumnAddition(newColumn)

        // Post notification to reload table view and auto-edit the new row
        NotificationCenter.default.post(
            name: .tableReloadData,
            object: nil,
            userInfo: ["autoEditLastRow": true, "tabID": instance.selectedTab?.id.uuidString ?? ""]
        )
    }

    private func generateUniqueColumnName() -> String {
        let existingNames = Set((currentSchema?.columns ?? []).map { $0.columnName })
        var counter = 1
        var name = "new_column"
        while existingNames.contains(name) || modificationTracker.isColumnNew(name) {
            name = "new_column_\(counter)"
            counter += 1
        }
        return name
    }

    private func handleAddIndex() {
        // Create a new index with default values
        let newIndex = DatabaseIndexInfo(
            name: generateUniqueIndexName(),
            tableName: tableName,
            schemaName: schemaName ?? "public",
            columns: [],
            indexType: .btree,
            isUnique: false,
            isPrimaryKey: false
        )

        // Track the addition
        modificationTracker.trackIndexAddition(newIndex)

        // Post notification to reload table view
        NotificationCenter.default.post(
            name: .tableReloadData,
            object: nil,
            userInfo: ["autoEditLastRow": true, "tabID": instance.selectedTab?.id.uuidString ?? ""]
        )
    }

    private func generateUniqueIndexName() -> String {
        let existingNames = Set((currentIndexes ?? []).map { $0.name })
        var counter = 1
        var name = "\(tableName)_new_index"
        while existingNames.contains(name) || modificationTracker.isIndexNew(name) {
            name = "\(tableName)_new_index_\(counter)"
            counter += 1
        }
        return name
    }

    // MARK: - Async Operations

    private func refreshSchema() async {
        // Silent in-place refresh — like the data table view. The cell views
        // reload via updateNSView when currentSchema / currentIndexes change,
        // so we don't take over the whole pane with a spinner.
        do {
            let schemaResult = try await instance.databaseService.getSchema(
                for: tableName,
                databaseSchema: schemaName,
                forceFetch: true
            )
            let indexesResult = try await instance.databaseService.getIndexes(
                for: tableName,
                databaseSchema: schemaName,
                forceFetch: true
            )

            await MainActor.run {
                currentSchema = schemaResult
                currentIndexes = indexesResult
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to refresh schema: \(error.localizedDescription)"
            }
        }
    }

    private func saveModifications() async {
        // Validate modifications first
        let validationErrors = modificationTracker.validateModifications()
        guard validationErrors.isEmpty else {
            await MainActor.run {
                errorMessage = validationErrors.joined(separator: "\n")
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Create modification service
            guard let service = instance.databaseService.makeSchemaModificationService() else {
                throw DatabaseError.operationFailed("No active database driver")
            }

            let plan = modificationTracker.snapshot()

            // Execute all modifications in a transaction
            try await service.executeModifications(
                tableName: tableName,
                schema: schemaName,
                plan: plan
            )

            // Clear modifications on success
            await MainActor.run {
                modificationTracker.clearAll()
            }

            // Refresh schema to show updated state
            await refreshSchema()

        } catch {
            await MainActor.run {
                errorMessage = "Failed to save changes: \(error.localizedDescription)"
            }
        }
    }
}

extension ConstraintType {
    var abbreviation: String {
        switch self {
        case .primaryKey: return "PK"
        case .foreignKey: return "FK"
        case .unique: return "UQ"
        case .check: return "CK"
        case .exclusion: return "EX"
        case .trigger: return "TR"
        }
    }

    var color: Color {
        switch self {
        case .primaryKey: return .yellow
        case .foreignKey: return .blue
        case .unique: return .purple
        case .check: return .orange
        case .exclusion: return .red
        case .trigger: return .green
        }
    }
}

// MARK: - Schema Header
struct SchemaModeViewHeader: View {
    let tableName: String
    @Binding var searchText: String
    @Binding var modificationTracker: SchemaModificationTracker
    @Environment(\.colorScheme) var colorScheme

    @State private var isEditingTableName: Bool = false
    @State private var editedTableName: String = ""
    @FocusState private var isTableNameFieldFocused: Bool

    private var hasTableNameChanged: Bool {
        editedTableName != tableName
    }

    private var tableNameBackgroundColor: Color {
        if isEditingTableName {
            return colorScheme == .dark ? Color(.white).opacity(0.1) : Color(.gray).opacity(0.15)
        } else if modificationTracker.tableRename != nil {
            return colorScheme == .dark
                ? Color(red: 0x7C/255.0, green: 0x59/255.0, blue: 0x2C/255.0)
                : Color(red: 0xFF/255.0, green: 0xE5/255.0, blue: 0x99/255.0)
        } else {
            return colorScheme == .dark ? Color(.white).opacity(0.06) : Color(.gray).opacity(0.1)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Table name with label
            HStack(spacing: 8) {
                Text("Table name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                // Table name field (consistent size in both modes)
                Group {
                    if isEditingTableName {
                        TextField("Table name", text: $editedTableName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .focused($isTableNameFieldFocused)
                            .onSubmit {
                                saveTableName()
                            }
                            .onKeyPress(.escape) {
                                cancelTableNameEdit()
                                return .handled
                            }
                    } else {
                        // Display mode - clickable to edit
                        Text(modificationTracker.tableRename?.newName ?? tableName)
                            .font(.system(size: 12, weight: .medium))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                startEditingTableName()
                            }
                    }
                }
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tableNameBackgroundColor)
                )

                // Action buttons (outside the pill)
                if isEditingTableName {
                    if hasTableNameChanged {
                        // Save button when text has changed
                        Button(action: saveTableName) {
                            Text("Save").font(.system(size: 11))
                        }
                        .buttonStyle(
                            RenameSaveButtonStyle(
                                backgroundColor: .primaryButton
                            )
                        )
                    } else {
                        // Cancel button when no changes
                        Button(action: cancelTableNameEdit) {
                            Text("Cancel").font(.system(size: 11))
                        }
                        .buttonStyle(RenameCancelButtonStyle())
                    }
                }
            }

            Spacer()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color(.white).opacity(0.06) : Color(.gray).opacity(0.1))
            )
            .frame(width: 220)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func startEditingTableName() {
        editedTableName = modificationTracker.tableRename?.newName ?? tableName
        isEditingTableName = true
        // Focus the text field after a short delay
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isTableNameFieldFocused = true
        }
    }

    private func saveTableName() {
        let trimmedName = editedTableName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            cancelTableNameEdit()
            return
        }

        // If name changed from original, track the modification
        if trimmedName != tableName {
            modificationTracker.trackTableRename(from: tableName, to: trimmedName)
        } else {
            // Reverted to original - remove any existing rename
            modificationTracker.removeTableRename()
        }

        isEditingTableName = false
    }

    private func cancelTableNameEdit() {
        isEditingTableName = false
    }
}

// MARK: - Schema Table View
struct ShemaTableView: View {
    let columns: [DatabaseSchemaInfo]
    let searchText: String
    let databaseType: DatabaseType
    @Binding var modificationTracker: SchemaModificationTracker

    var body: some View {
        if !columns.isEmpty {
            SchemaTableView(
                columns: columns,
                searchText: searchText,
                databaseType: databaseType,
                modificationTracker: $modificationTracker
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "tablecells")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.5))

                Text("No schema data")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
