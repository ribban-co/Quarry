//
//  SchemaModificationService.swift
//  Quarry
//
//  Service for handling schema modifications (columns and indexes)
//

import Foundation

actor SchemaModificationService {
    private let driverBox: DatabaseDriverBox

    init(driverBox: DatabaseDriverBox) {
        self.driverBox = driverBox
    }

    // MARK: - Column Operations

    /// Add a new column to a table
    func addColumn(
        to tableName: String,
        schema: String?,
        column: DatabaseSchemaInfo
    ) async throws {
        try await driverBox.addColumn(to: tableName, schema: schema, column: column)
    }

    /// Modify an existing column
    func modifyColumn(
        in tableName: String,
        schema: String?,
        columnName: String,
        newColumn: DatabaseSchemaInfo
    ) async throws {
        try await driverBox.modifyColumn(
            in: tableName,
            schema: schema,
            columnName: columnName,
            newColumn: newColumn
        )
    }

    /// Drop a column from a table
    func dropColumn(
        from tableName: String,
        schema: String?,
        columnName: String
    ) async throws {
        try await driverBox.dropColumn(from: tableName, schema: schema, columnName: columnName)
    }

    // MARK: - Index Operations

    /// Create a new index
    func createIndex(
        on tableName: String,
        schema: String?,
        index: DatabaseIndexInfo
    ) async throws {
        try await driverBox.createIndex(on: tableName, schema: schema, index: index)
    }

    /// Drop an index
    func dropIndex(
        indexName: String,
        tableName: String,
        schema: String?
    ) async throws {
        try await driverBox.dropIndex(
            indexName: indexName,
            tableName: tableName,
            schema: schema
        )
    }

    // MARK: - Batch Operations with Transaction Support

    /// Execute multiple schema modifications in a transaction
    func executeModifications(
        tableName: String,
        schema: String?,
        plan: SchemaModificationPlan
    ) async throws {
        // Begin transaction
        _ = try await driverBox.executeRawQuery("BEGIN", databaseSchema: schema)

        do {
            // Execute modifications in dependency order

            // 1. Drop constraints first (if needed)
            // Note: Constraints are handled within column/index operations

            // 2. Drop columns
            for modification in plan.columnDeletions {
                guard let columnName = modification.columnName else { continue }
                try await dropColumn(from: tableName, schema: schema, columnName: columnName)
            }

            // 3. Drop indexes
            for modification in plan.indexDeletions {
                guard let indexName = modification.indexName else { continue }
                try await dropIndex(indexName: indexName, tableName: tableName, schema: schema)
            }

            // 4. Add columns
            for modification in plan.columnAdditions {
                guard let column = modification.column else { continue }
                try await addColumn(to: tableName, schema: schema, column: column)
            }

            // 5. Modify columns
            for modification in plan.columnUpdates {
                guard let columnName = modification.columnName,
                      let newColumn = modification.column else { continue }
                try await modifyColumn(
                    in: tableName,
                    schema: schema,
                    columnName: columnName,
                    newColumn: newColumn
                )
            }

            // 6. Modify indexes (drop old, create new - indexes can't be modified in place)
            for modification in plan.indexUpdates {
                guard let originalIndex = modification.originalIndex,
                      let newIndex = modification.index else { continue }
                // Drop the old index first
                try await dropIndex(indexName: originalIndex.name, tableName: tableName, schema: schema)
                // Create the new index
                try await createIndex(on: tableName, schema: schema, index: newIndex)
            }

            // 7. Create indexes
            for modification in plan.indexAdditions {
                guard let index = modification.index else { continue }
                try await createIndex(on: tableName, schema: schema, index: index)
            }

            // Commit transaction
            _ = try await driverBox.executeRawQuery("COMMIT", databaseSchema: schema)

            // Clear schema cache after successful modifications
            await driverBox.clearSchemaCache(for: tableName, schema: schema)

        } catch {
            // Rollback on any error
            _ = try await driverBox.executeRawQuery("ROLLBACK", databaseSchema: schema)
            throw error
        }
    }

    // MARK: - Schema Refresh

    /// Refresh schema information after modifications
    func refreshSchema(
        for tableName: String,
        schema: String?
    ) async throws -> DatabaseSchemaResult? {
        return try await driverBox.getSchema(for: tableName, schema: schema)
    }

    /// Refresh index information after modifications
    func refreshIndexes(
        for tableName: String,
        schema: String?
    ) async throws -> [DatabaseIndexInfo] {
        return try await driverBox.getIndexes(for: tableName, schema: schema)
    }
}
