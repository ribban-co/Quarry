import Foundation
import SQLiteNIO
import NIOCore
import Logging
import Darwin

// MARK: - SQLite Wrappers
struct SQLiteDatabaseWrapper: DatabaseWrapper {
    let name: String
    let size: String?
    let tableCount: Int?
}

struct SQLiteCollectionWrapper: CollectionWrapper {
    var schema: String?
    
    var id: ObjectIdentifier
    let name: String
    let type: String
}

// MARK: - SQLite Driver
actor SQLiteDriver: DatabaseDriver {
    func getInformationSchema() async throws -> [InformationSchema] {
        throw DatabaseError.notImplemented("MySQL driver not yet implemented")
    }
    
    typealias Database = SQLiteDatabaseWrapper
    typealias Collection = SQLiteCollectionWrapper

    /// Maximum number of rows materialized per raw-query statement
    private static let maxRawQueryRows = 100_000
    
    // Store connection and event loop group for proper cleanup
    private var connection: SQLiteConnection?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var isConnected = false
    
    // Connection configuration
    private var databasePath: String?
    private var threadPool: NIOThreadPool?
    private var securityScopedURL: URL? = nil
    private var databases: [SQLiteDatabaseWrapper] = []
    private var collections: [SQLiteCollectionWrapper] = []
    
    deinit {
        // Ensure cleanup happens even if disconnect wasn't called explicitly.
        // Capture the resources themselves into a detached task — never self or
        // actor state, since the actor is being torn down.
        let connection = self.connection
        let eventLoopGroup = self.eventLoopGroup
        let threadPool = self.threadPool
        let securityScopedURL = self.securityScopedURL

        Task.detached { [connection, eventLoopGroup, threadPool, securityScopedURL] in
            if let connection = connection {
                try? await connection.close()
            }
            
            if let threadPool = threadPool {
                try? await threadPool.shutdownGracefully()
            }
            
            if let eventLoopGroup = eventLoopGroup {
                try? await eventLoopGroup.shutdownGracefully()
            }
            
            // Stop accessing security-scoped resource
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }
    }
    
    func connect(to connectionUri: String) async throws -> SQLiteDatabaseWrapper {
        self.databasePath = connectionUri
        
        // Regular flow for other files
        let path = try parseConnectionString(connectionUri)
        return try await establishConnection(to: path)
    }
    
    private func establishConnection(to path: String) async throws -> SQLiteDatabaseWrapper {
        // Store the current security-scoped URL before cleanup
        let preservedSecurityScopedURL = self.securityScopedURL
        
        // Clean up any existing connection first (but don't stop security-scoped access yet)
        if let connection = self.connection {
            try? await connection.close()
            self.connection = nil
        }
        
        if let threadPool = self.threadPool {
            try? await threadPool.shutdownGracefully()
            self.threadPool = nil
        }
        
        if let eventLoopGroup = self.eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
            self.eventLoopGroup = nil
        }
        
        // Restore the security-scoped URL after partial cleanup
        self.securityScopedURL = preservedSecurityScopedURL
        
        do {
            // Create event loop group with proper lifecycle management
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            self.eventLoopGroup = eventLoopGroup
            
            // Create thread pool for SQLite operations
            let threadPool = NIOThreadPool(numberOfThreads: 1)
            threadPool.start()
            self.threadPool = threadPool
            
            // Always require security-scoped URL for file access
            guard let securityScopedURL = self.securityScopedURL else {
                throw DatabaseError.configurationError("Security-scoped URL is required. Please select the file again using the folder button (📁).")
            }
            
            // Establish security-scoped resource access
            securityScopedURL.stopAccessingSecurityScopedResource()
            guard securityScopedURL.startAccessingSecurityScopedResource() else {
                throw DatabaseError.configurationError("Lost access to the selected path. Please select the file again using the folder button (📁).")
            }
            
            // Check if it's a directory and handle accordingly
            let finalPath: String
            let isWALMode: Bool
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: securityScopedURL.path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                // Search for SQLite files in the directory
                guard let sqliteFile = try findFirstSQLiteFile(securityScopedURL: securityScopedURL) else {
                    throw DatabaseError.configurationError("No SQLite database files found in the selected folder.\n\n→ Go to Edit Connection → Click \"Change\" → Select a folder containing .db, .sqlite, or .sqlite3 files, or select a specific database file")
                }
                finalPath = sqliteFile
                // Directory selection can handle WAL mode properly, so always allow it
                isWALMode = false
                debugLog("📁 Found SQLite file in directory: \(URL(fileURLWithPath: sqliteFile).lastPathComponent)")
            } else {
                // Use the file directly and check its WAL mode
                finalPath = securityScopedURL.path
                isWALMode = SQLiteWALDetector.isInWALMode(at: securityScopedURL)
                debugLog("📄 Using selected file: \(URL(fileURLWithPath: finalPath).lastPathComponent) (WAL: \(isWALMode))")
            }
            
            let storage = SQLiteConnection.Storage.file(path: finalPath)
            
            let connection = try await SQLiteConnection.open(
                storage: storage,
                threadPool: threadPool,
                on: eventLoopGroup.next()
            )
            
            // Store connection immediately so it can be cleaned up if anything fails
            self.connection = connection
            
            // Leave the database's own journal mode untouched — changing it mutates
            // the user's file and risks corruption if the app crashes mid-write
            self.isConnected = true

            // Extract database name from final path
            let databaseName = URL(fileURLWithPath: finalPath).lastPathComponent

            return SQLiteDatabaseWrapper(name: databaseName, size: nil, tableCount: nil)

        } catch {
            // Clean up on failure (handles cases where connection creation itself failed)
            await cleanup()
            
            if error is CancellationError {
                throw DatabaseError.connectionFailed("SQLite connection was cancelled - this might be due to app lifecycle or rapid connection changes")
            } else {
                throw DatabaseError.connectionFailed(error.localizedDescription)
            }
        }
    }
    
    func disconnect() async {
        await cleanup()
    }
    
    private func cleanup() async {
        do {
            let _ = try await connection?.query("PRAGMA wal_checkpoint;")
        } catch {
            debugLog("Safely ignored error: \(error)")
        }
        
        if let connection = self.connection {
            try? await connection.close()
            self.connection = nil
        }
        
        if let threadPool = self.threadPool {
            try? await threadPool.shutdownGracefully()
            self.threadPool = nil
        }
        
        if let eventLoopGroup = self.eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
            self.eventLoopGroup = nil
        }
        
        // Stop accessing security-scoped resource
        if let securityScopedURL = self.securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
            self.securityScopedURL = nil
        }
        
        self.isConnected = false
    }
    
    private func ensureConnected() async throws -> SQLiteConnection {
        guard let connection = self.connection else {
            throw DatabaseError.connectionFailed("Not connected to SQLite database")
        }
        
        if connection.isClosed {
            guard let path = self.databasePath else {
                throw DatabaseError.configurationError("No active connection configuration")
            }
            
            _ = try await establishConnection(to: path)
            return self.connection!
        }
        
        return connection
    }
    
    func reconnect() async throws {
        await disconnect()
        if let databasePath = self.databasePath {
            let path = try parseConnectionString(databasePath)
            _ = try await establishConnection(to: path)
        }
    }
    
    func ping(to connectionUri: String) async throws {
        // For SQLite, the URI is a path or bookmark; try opening and closing
        let path = try parseConnectionString(connectionUri)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let pool = NIOThreadPool(numberOfThreads: 1)
        pool.start()

        // Shut down inline (not fire-and-forget) so ping's resources are fully
        // released before the caller can replace or reuse the connection
        do {
            let temp = try await SQLiteConnection.open(
                storage: .file(path: path),
                threadPool: pool,
                on: group.next()
            )
            try await temp.close()
        } catch {
            try? await pool.shutdownGracefully()
            try? await group.shutdownGracefully()
            throw DatabaseError.connectionFailed("Ping failed: \(error.localizedDescription)")
        }

        try? await pool.shutdownGracefully()
        try? await group.shutdownGracefully()
    }
    
    func switchDatabase(to databaseName: String) async throws {
        // For SQLite, switching database means connecting to a different file
        await disconnect()
        _ = try await establishConnection(to: databaseName)
    }
    
    func getBuildInfo() async throws -> BuildInfo {
        let connection = try await ensureConnected()
        
        do {
            let rows = try await connection.query("SELECT sqlite_version()")
            
            var version = "Unknown"
            for row in rows {
                if let versionString = row.column("sqlite_version()")?.string {
                    version = versionString
                    break
                }
            }
            
            return BuildInfo(
                version: version,
                databaseType: DatabaseType.sqlite
            )
        } catch {
            throw DatabaseError.operationFailed("Failed to get build info: \(error.localizedDescription)")
        }
    }
    
    func listDatabases() async throws -> [SQLiteDatabaseWrapper] {
        // SQLite only has one database per file
        guard let path = self.databasePath else {
            throw DatabaseError.configurationError("No database path configured")
        }
        
        let databaseName = URL(fileURLWithPath: path).lastPathComponent
        return [SQLiteDatabaseWrapper(name: databaseName, size: nil, tableCount: nil)]
    }
    
    func getDatabaseMetadata() async throws -> [SQLiteDatabaseWrapper] {
        return try await listDatabases()
    }
    
    func listCollections(schema: String?) async throws -> [SQLiteCollectionWrapper] {
        let connection = try await ensureConnected()
        
        do {
            let rows = try await connection.query("""
                SELECT name, type FROM sqlite_master 
                WHERE type IN ('table', 'view') 
                AND name NOT LIKE 'sqlite_%'
                ORDER BY name
            """)
            
            var collections: [SQLiteCollectionWrapper] = []
            for row in rows {
                if let name = row.column("name")?.string,
                   let type = row.column("type")?.string {
                    collections.append(SQLiteCollectionWrapper(
                        id: ObjectIdentifier(NSString(string: name)),
                        name: name,
                        type: type
                    ))
                }
            }
            
            return collections
        } catch {
            throw DatabaseError.operationFailed("Failed to list tables: \(error.localizedDescription)")
        }
    }
    
    func getDocumentCount(for collectionName: String, filter: DatabaseDocument) async throws -> Int {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)
        
        do {
            let whereClause = buildWhereClause(from: filter)
            var queryString = "SELECT COUNT(*) as count FROM \(sanitizedTableName)"
            
            if !whereClause.isEmpty {
                queryString += " WHERE \(whereClause)"
            }
            
            let rows = try await connection.query(queryString)
            
            for row in rows {
                if let count = row.column("count")?.integer {
                    return Int(count)
                }
            }
            
            return 0
        } catch {
            throw DatabaseError.operationFailed("Failed to get document count: \(error.localizedDescription)")
        }
    }
    
    func findDocuments(in collectionName: String, filter: DatabaseDocument) async throws -> [QueryResult] {
        let result = try await findDocuments(in: collectionName, filter: filter, skip: 0, limit: 1000)
        return [result]
    }
    
    func findDocuments(in collectionName: String, filter: DatabaseDocument, skip: Int, limit: Int) async throws -> QueryResult {
        return try await findDocuments(in: collectionName, databaseSchema: nil, filter: filter, skip: skip, limit: limit, sortBy: nil, ascending: nil)
    }
    
    func findDocuments(in collectionName: String, databaseSchema: String?, filter: DatabaseDocument, skip: Int, limit: Int, sortBy: String?, ascending: Bool?) async throws -> QueryResult {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)
        
        do {
            let queryString: String
            
            // Check if filter contains a raw query
            if let rawQuery = filter["rawQuery"]?.stringValue, !rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Use the raw query, applying pagination when it's a plain SELECT without its own LIMIT
                var raw = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.hasSuffix(";") {
                    raw = String(raw.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let lowered = raw.lowercased()
                let isSelect = lowered.hasPrefix("select") || lowered.hasPrefix("with")
                let hasLimit = lowered.range(of: #"\blimit\b"#, options: .regularExpression) != nil

                if isSelect && !hasLimit {
                    raw += " LIMIT \(limit) OFFSET \(skip)"
                }
                queryString = raw
            } else {
                // Build standard query with optional WHERE clause and ORDER BY clause
                let whereClause = buildWhereClause(from: filter)
                let orderByClause = buildOrderByClause(sortBy: sortBy, ascending: ascending)
                
                var standardQuery = "SELECT * FROM \(sanitizedTableName)"
                
                if !whereClause.isEmpty {
                    standardQuery += " WHERE \(whereClause)"
                }
                
                if !orderByClause.isEmpty {
                    standardQuery += " \(orderByClause)"
                }
                
                standardQuery += " LIMIT \(limit) OFFSET \(skip)"
                queryString = standardQuery
            }
            
            let rows = try await connection.query(queryString)
            
            // Get column information from the first row
            var queryColumns: [QueryColumnInfo] = []
            var convertedRows: [[String: QueryRowInfo]] = []
            var rawRows: [DatabaseRawRow] = []
            
            // Get column information using PRAGMA table_info if this is the first call
            if queryColumns.isEmpty && !rows.isEmpty {
                // Get column info from PRAGMA table_info
                do {
                    let schemaRows = try await connection.query("PRAGMA table_info(\(sanitizedTableName))")
                    var columnInfoMap: [String: String] = [:]
                    
                    for schemaRow in schemaRows {
                        if let columnName = schemaRow.column("name")?.string,
                           let dataType = schemaRow.column("type")?.string {
                            columnInfoMap[columnName] = dataType
                        }
                    }
                    
                    // Build QueryColumnInfo from the first row's columns
                    if let firstRow = rows.first {
                        for (columnIndex, column) in firstRow.columns.enumerated() {
                            let dataType = columnInfoMap[column.name] ?? "TEXT"
                            queryColumns.append(QueryColumnInfo(
                                name: column.name,
                                dataType: dataType,
                                format: nil,
                                index: columnIndex
                            ))
                        }
                    }
                } catch {
                    // Fallback: create columns with unknown types
                    if let firstRow = rows.first {
                        for (columnIndex, column) in firstRow.columns.enumerated() {
                            queryColumns.append(QueryColumnInfo(
                                name: column.name,
                                dataType: "TEXT", // Default fallback
                                format: nil,
                                index: columnIndex
                            ))
                        }
                    }
                }
            }
            
            for (_, row) in rows.enumerated() {
                // Process row data
                var processedRowData: [String: QueryRowInfo] = [:]
                var rawRowData: DatabaseRawRow = [:]
                
                for column in queryColumns {
                    let columnName = column.name
                    let sqliteColumn = row.column(columnName)
                    
                    // Store raw value - use the appropriate accessor based on the column type
                    var rawValue: DatabaseValue? = .null
                    var processedValue: DatabaseValue? = .null
                    
                    if let sqliteColumn = sqliteColumn {
                        // SQLite NIO provides different accessors for different types
                        if let stringValue = sqliteColumn.string {
                            rawValue = .string(stringValue)
                            processedValue = rawValue
                        } else if let intValue = sqliteColumn.integer {
                            rawValue = .int(Int(intValue))
                            processedValue = rawValue
                        } else if let doubleValue = sqliteColumn.double {
                            rawValue = .double(doubleValue)
                            processedValue = rawValue
                        } else if let blobValue = sqliteColumn.blob {
                            let data = Data(blobValue.readableBytesView)
                            rawValue = .data(data)
                            processedValue = rawValue
                        } else {
                            // NULL value
                            rawValue = .null
                            processedValue = .null
                        }
                    }
                    
                    rawRowData[columnName] = rawValue
                    
                    // Convert to QueryRowInfo
                    processedRowData[columnName] = QueryRowInfo(
                        value: processedValue,
                        dataType: column.dataType,
                        format: nil
                    )
                }
                
                convertedRows.append(processedRowData)
                rawRows.append(rawRowData)
            }
            
            return QueryResult(
                columns: queryColumns,
                rows: convertedRows,
                totalCount: convertedRows.count,
                rawRows: rawRows
            )
        } catch {
            throw DatabaseError.operationFailed(error.localizedDescription)
        }
    }
    
    func createDocument(in collectionName: String, databaseSchema: String?, document: DatabaseDocument) async throws {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)
        
        guard !document.isEmpty else {
            throw DatabaseError.operationFailed("Cannot insert an empty document.")
        }
        
        do {
            let sortedKeys = document.keys.sorted()
            let columns = sortedKeys.map { escapeIdentifier($0) }.joined(separator: ", ")
            let placeholders = Array(repeating: "?", count: sortedKeys.count).joined(separator: ", ")
            
            let queryString = "INSERT INTO \(sanitizedTableName) (\(columns)) VALUES (\(placeholders))"
            
            var binds: [SQLiteData] = []
            for key in sortedKeys {
                binds.append(convertToSQLiteData(document[key] ?? .null))
            }
            
            let _ = try await connection.query(queryString, binds)
        } catch {
            throw DatabaseError.operationFailed("Failed to create document: \(error.localizedDescription)")
        }
    }
    
    func updateDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID, data: DatabaseDocument) async throws {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)
        
        guard !data.isEmpty else {
            throw DatabaseError.operationFailed("No changes detected to update")
        }
        
        do {
            let setClauses = data.keys.map { "\(escapeIdentifier($0)) = ?" }.joined(separator: ", ")
            let recordColumn = try validateAndSanitizeIdentifier(id.columnName)
            let queryString = "UPDATE \(sanitizedTableName) SET \(setClauses) WHERE \(recordColumn) = ?"
            
            var binds: [SQLiteData] = []
            for (_, value) in data {
                binds.append(convertToSQLiteData(value))
            }
            binds.append(convertToSQLiteData(id.value))
            
            let _ = try await connection.query(queryString, binds)
        } catch {
            throw DatabaseError.operationFailed(error.localizedDescription)
        }
    }
    
    func deleteDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID) async throws {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)
        
        do {
            let recordColumn = try validateAndSanitizeIdentifier(id.columnName)
            let queryString = "DELETE FROM \(sanitizedTableName) WHERE \(recordColumn) = ?"
            let binds = [convertToSQLiteData(id.value)]
            
            let _ = try await connection.query(queryString, binds)
        } catch {
            throw DatabaseError.operationFailed(error.localizedDescription)
        }
    }
    
    func executeRawQuery(_ query: String, databaseSchema: String?) async throws -> [QueryResult] {
        let connection = try await ensureConnected()
        let statements = splitSQLStatements(query)

        if statements.isEmpty {
            return [QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])]
        }

        var allResults: [QueryResult] = []

        for statement in statements {
            do {
                let rows = try await connection.query(statement)

                var queryColumns: [QueryColumnInfo] = []
                var convertedRows: [[String: QueryRowInfo]] = []
                var convertedRawRows: [DatabaseRawRow] = []

                if let firstRow = rows.first {
                    for (columnIndex, column) in firstRow.columns.enumerated() {
                        queryColumns.append(QueryColumnInfo(
                            name: column.name,
                            dataType: "TEXT",
                            format: nil,
                            index: columnIndex
                        ))
                    }
                }

                for (rowIndex, row) in rows.enumerated() {
                    if rowIndex >= Self.maxRawQueryRows {
                        break
                    }
                    if rowIndex % 1000 == 0, Task.isCancelled {
                        throw CancellationError()
                    }

                    var processedRowData: [String: QueryRowInfo] = [:]
                    var rawRowData: DatabaseRawRow = [:]

                    for column in queryColumns {
                        let columnName = column.name
                        let sqliteColumn = row.column(columnName)

                        var rawValue: DatabaseValue? = .null
                        var processedValue: DatabaseValue? = .null

                        if let sqliteColumn = sqliteColumn {
                            if let stringValue = sqliteColumn.string {
                                rawValue = .string(stringValue)
                                processedValue = rawValue
                            } else if let intValue = sqliteColumn.integer {
                                rawValue = .int(Int(intValue))
                                processedValue = rawValue
                            } else if let doubleValue = sqliteColumn.double {
                                rawValue = .double(doubleValue)
                                processedValue = rawValue
                            } else if let blobValue = sqliteColumn.blob {
                                let data = Data(blobValue.readableBytesView)
                                rawValue = .data(data)
                                processedValue = rawValue
                            }
                        }

                        rawRowData[columnName] = rawValue
                        processedRowData[columnName] = QueryRowInfo(
                            value: processedValue,
                            dataType: column.dataType,
                            format: nil
                        )
                    }

                    convertedRows.append(processedRowData)
                    convertedRawRows.append(rawRowData)
                }

                let result = QueryResult(
                    columns: queryColumns,
                    rows: convertedRows,
                    totalCount: convertedRows.count,
                    rawRows: convertedRawRows
                )

                allResults.append(result)

            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw DatabaseError.operationFailed("Failed to execute statement: \(error.localizedDescription)")
            }
        }

        return allResults.isEmpty ? [QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])] : allResults
    }

    private func splitSQLStatements(_ sql: String) -> [String] {
        var statements: [String] = []
        var currentStatement = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var i = sql.startIndex

        while i < sql.endIndex {
            let char = sql[i]

            if inSingleQuote {
                currentStatement.append(char)
                if char == "'" {
                    let nextIndex = sql.index(after: i)
                    if nextIndex < sql.endIndex && sql[nextIndex] == "'" {
                        currentStatement.append("'")
                        i = nextIndex
                    } else {
                        inSingleQuote = false
                    }
                }
            } else if inDoubleQuote {
                currentStatement.append(char)
                if char == "\"" {
                    inDoubleQuote = false
                }
            } else {
                switch char {
                case "'":
                    inSingleQuote = true
                    currentStatement.append(char)
                case "\"":
                    inDoubleQuote = true
                    currentStatement.append(char)
                case ";":
                    let trimmed = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        statements.append(trimmed)
                    }
                    currentStatement = ""
                default:
                    currentStatement.append(char)
                }
            }
            i = sql.index(after: i)
        }

        let trimmed = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            statements.append(trimmed)
        }

        return statements
    }
    
    func createCollection(named collectionName: String) async throws {
        throw DatabaseError.notImplemented("Support for creating tables not yet implemented")
        //        let connection = try await ensureConnected()
        //        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)
        //
        //        let query = """
        //            CREATE TABLE \(sanitizedTableName) (
        //                id INTEGER PRIMARY KEY AUTOINCREMENT,
        //                created_at TEXT DEFAULT (datetime('now')),
        //                updated_at TEXT DEFAULT (datetime('now'))
        //            )
        //        """
        //
        //        do {
        //            _ = try await connection.query(query)
        //        } catch {
        //            throw DatabaseError.operationFailed("Failed to create table: \(error.localizedDescription)")
        //        }
    }
    
    func renameCollection(databaseSchema: String?, from oldName: String, to newName: String) async throws {
        let connection = try await ensureConnected()
        let sanitizedOldName = try validateAndSanitizeIdentifier(oldName)
        let sanitizedNewName = try validateAndSanitizeIdentifier(newName)
        
        let query = "ALTER TABLE \(sanitizedOldName) RENAME TO \(sanitizedNewName)"
        
        do {
            _ = try await connection.query(query)
        } catch {
            throw DatabaseError.operationFailed("Failed to rename table: \(error.localizedDescription)")
        }
    }
    
    func deleteCollection(named collectionName: String, databaseSchema: String?) async throws {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)
        
        let query = "DROP TABLE \(sanitizedTableName)"
        
        do {
            _ = try await connection.query(query)
        } catch {
            throw DatabaseError.operationFailed("Failed to delete table: \(error.localizedDescription)")
        }
    }
    
    func getSchema(for collectionName: String, schema: String?) async throws -> DatabaseSchemaResult? {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)
        
        do {
            let rows = try await connection.query("PRAGMA table_info(\(sanitizedTableName))")
            
            // Fetch foreign key information
            let foreignKeyRows = try await connection.query("PRAGMA foreign_key_list(\(sanitizedTableName))")
            var foreignKeyMap: [String: String] = [:]
            var foreignKeyConstraints: [String: ConstraintInfo] = [:]
            
            for fkRow in foreignKeyRows {
                if let fromColumn = fkRow.column("from")?.string,
                   let toTable = fkRow.column("table")?.string,
                   let toColumn = fkRow.column("to")?.string {
                    foreignKeyMap[fromColumn] = "\(toTable)(\(toColumn))"
                    
                    // Create detailed constraint info for foreign key navigation
                    let constraintInfo = ConstraintInfo(
                        name: "FK_\(fromColumn)_\(toTable)_\(toColumn)",
                        type: .foreignKey,
                        columns: [fromColumn],
                        referencedTable: toTable,
                        referencedColumns: [toColumn]
                    )
                    foreignKeyConstraints[fromColumn] = constraintInfo
                }
            }
            
            var schemaInfo: [DatabaseSchemaInfo] = []
            
            for row in rows {
                guard let columnName = row.column("name")?.string,
                      let dataType = row.column("type")?.string,
                      let notNull = row.column("notnull")?.integer,
                      let primaryKey = row.column("pk")?.integer else {
                    continue
                }
                
                let isNullable = notNull == 0 ? "YES" : "NO"
                let defaultValue = row.column("dflt_value")?.string
                let foreignKey = foreignKeyMap[columnName] ?? ""
                
                var constraints: [ConstraintInfo] = []
                if primaryKey == 1 {
                    constraints.append(ConstraintInfo(name: "PRIMARY", type: .primaryKey))
                }
                if let fkConstraint = foreignKeyConstraints[columnName] {
                    constraints.append(fkConstraint)
                }
                
                let schema = DatabaseSchemaInfo(
                    ordinalPosition: Int(row.column("cid")?.integer ?? 0),
                    columnName: columnName,
                    dataType: dataType,
                    formatType: dataType,
                    typeOid: 0, // SQLite doesn't have type OIDs
                    numericPrecision: nil,
                    datetimePrecision: nil,
                    numericScale: nil,
                    dataLength: nil,
                    isNullable: isNullable,
                    check: "",
                    checkConstraint: "",
                    columnDefault: defaultValue,
                    foreignKey: foreignKey,
                    constraints: constraints,
                    comment: nil
                )
                
                schemaInfo.append(schema)
            }
            
            return DatabaseSchemaResult(
                tableName: collectionName,
                schemaName: "main",
                columns: schemaInfo,
                totalCount: schemaInfo.count
            )
        } catch {
            throw DatabaseError.operationFailed("Failed to get schema: \(error.localizedDescription)")
        }
    }

    func getIndexes(for collectionName: String, schema: String?) async throws -> [DatabaseIndexInfo] {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName)

        do {
            // Get list of indexes for the table
            let indexListRows = try await connection.query("PRAGMA index_list(\(sanitizedTableName))")
            var indexes: [DatabaseIndexInfo] = []

            for indexRow in indexListRows {
                guard let indexName = indexRow.column("name")?.string else {
                    continue
                }

                let unique = (indexRow.column("unique")?.integer ?? 0) == 1
                let origin = indexRow.column("origin")?.string ?? ""
                let isPrimaryKey = origin == "pk"

                // Get columns for this index
                let sanitizedIndexName = try validateAndSanitizeIdentifier(indexName)
                let indexInfoRows = try await connection.query("PRAGMA index_info(\(sanitizedIndexName))")
                var columns: [String] = []

                for infoRow in indexInfoRows {
                    if let columnName = infoRow.column("name")?.string {
                        columns.append(columnName)
                    }
                }

                let indexInfo = DatabaseIndexInfo(
                    name: indexName,
                    tableName: collectionName,
                    schemaName: "main",
                    columns: columns,
                    indexType: .btree, // SQLite primarily uses B-tree indexes
                    isUnique: unique,
                    isPrimaryKey: isPrimaryKey,
                    definition: nil,
                    condition: nil
                )
                indexes.append(indexInfo)
            }

            return indexes
        } catch {
            throw DatabaseError.operationFailed("Failed to get indexes: \(error.localizedDescription)")
        }
    }

    func buildAICommandPromptSystemPrompt(_ message: String) async throws -> String {
        let currentDate = Date().formatted(.iso8601)
        
        // Get all available tables/collections with error handling  
        var tablesList = ""
        do {
            let collections = try await listCollections(schema: nil)
            tablesList = collections.map { "- \($0.name) (\($0.type))" }.joined(separator: "\n")
        } catch {
            tablesList = "No tables available (connection error)"
        }
        
        return """
        You are a SQLite query assistant for a desktop database client's CMD+K quick action. Your output is inserted directly into a SQL editor, so respond with only the SQL query as plain text. Your output must be valid, executable SQLite.

        <available_tables>
        \(tablesList)
        </available_tables>

        <instructions>
        1. For new queries, start with a single-line SQL comment describing what the query does, then the query itself.
        2. For query modifications, return only the modified query. Preserve the original formatting style.
        3. For query fixes, return only the corrected query.
        4. Use table names from the available tables list. If a name seems misspelled, use the closest match.
        5. Always wrap table and column identifiers in double quotes (e.g., FROM "users", "users"."created_at"). This ensures names with special characters or reserved words work correctly.
        6. Default to SELECT * unless the user specifies columns.
        7. Use LIKE for case-insensitive string matching, GLOB for case-sensitive patterns.
        8. Use SQLite date/time functions (datetime(), date(), strftime(), etc.).
        9. Capitalize SQL keywords (SELECT, FROM, WHERE, ORDER BY, etc.).
        10. Use single quotes for string literals and terminate with a semicolon.
        11. Break multi-line queries at logical clauses for readability.
        12. If you need column-level detail for a table, call the get_table_schema tool.
        </instructions>

        <examples>
        <example>
        <input>Get all active users from the last month</input>
        <output>
        -- Retrieve all active users created in the last 30 days
        SELECT *
        FROM "users"
        WHERE "status" = 'active'
          AND "created_at" > datetime('now', '-30 days');
        </output>
        </example>

        <example>
        <input>Add ordering by name to this query: SELECT * FROM "products" WHERE "price" > 100;</input>
        <output>
        SELECT *
        FROM "products"
        WHERE "price" > 100
        ORDER BY "name" ASC;
        </output>
        </example>

        <example>
        <input>Fix this query: SELECT * FROM user WHERE age > 30 AND</input>
        <output>
        SELECT * FROM "users" WHERE "age" > 30;
        </output>
        </example>
        </examples>

        Current date: \(currentDate)
        """
    }
    
    func buildSystemPrompt(for collectionName: String, databaseSchema: String?) async throws -> String {
        let currentDate = Date().formatted(.iso8601)
        let schema = await buildSchemaPrompt(for: collectionName)
        
        return """
        You are a SQLite query assistant. Your primary task is to convert natural language user queries into valid SQLite SQL queries.
        
        Core Responsibilities: 
        - Convert the user query into a SQLite SQL query.
        - Return ONLY the SQL query without explanation.
        - Optimize the query for best performance.
        - Support all SQLite operators and query features.
        
        # Database Schema
        The current table schema is:
        \(schema)
        
        # Output Format
        Return ONLY the SQLite SQL query.
        Do not include any explanation, preamble, or commentary.
        Format the query for readability with proper indentation.
        One-line queries are acceptable for simple filters.
        
        # Examples
        
        **Example 1:**
        **Input:** Find all users where age is greater than 30
        **Output:**
        SELECT * FROM users WHERE age > 30;
        
        **Example 2:**
        **Input:** Get records where status is active and created date is in the last week
        **Output:**
        SELECT * FROM records 
        WHERE status = 'active' 
        AND created_at > datetime('now', '-7 days');
        
        **Example 3:**
        **Input:** Show me customers from New York or California with at least 5 orders
        **Output:**
        SELECT * FROM customers 
        WHERE (state = 'New York' OR state = 'California') 
        AND order_count >= 5;
        
        **Example 4:**
        **Input:** Get user with id 12345
        **Output:**
        SELECT * FROM users WHERE id = 12345;
        
        **Example 5:**
        **Input:** Find products containing 'laptop' in name, ordered by price descending
        **Output:**
        SELECT * FROM products 
        WHERE name LIKE '%laptop%' 
        ORDER BY price DESC;
        
        # Notes
        - NEVER provide explanations or ask clarifying questions.
        - NEVER describe what the query does.
        - Use the provided schema to understand available columns and data types.
        - When user input is ambiguous, refer to the schema for proper column names.
        - Use appropriate SQLite operators (=, >, <, IN, LIKE, GLOB, etc.) based on query requirements.
        - Use LIKE for pattern matching.
        - Use proper SQLite date/time functions (datetime(), date(), etc.).
        - Default to SELECT * unless specific columns are mentioned.
        - Include proper semicolon termination.
        - Return the SQL query as plain text only. Do NOT use code blocks, backticks, or any markdown formatting.
        - Only generate SELECT queries. Do not create UPDATE, DELETE, INSERT, or any data-modifying queries.
        
        Current Date: \(currentDate)
        """
    }
    
    // MARK: - Helper Methods
    
    private func parseConnectionString(_ connectionString: String) throws -> String {
        // Check if this is a security-scoped bookmark
        if let (bookmarkData, _) = BookmarkManager.shared.decodeBookmark(connectionString) {
            do {
                // Resolve the bookmark to get URL
                let url = try BookmarkManager.shared.resolveBookmark(bookmarkData)
                
                // Start accessing security-scoped resource immediately
                guard url.startAccessingSecurityScopedResource() else {
                    throw DatabaseError.configurationError("Failed to access security-scoped file. Please select the file again using the folder button (📁).")
                }
                
                // Store the URL for cleanup later
                self.securityScopedURL = url
                return url.path
            } catch let error as BookmarkError {
                switch error {
                case .staleBookmark, .accessDenied:
                    throw DatabaseError.configurationError("Cannot access the database file.\n\n→ Go to Edit Connection → Click \"Change\" → Select the file again")
                default:
                    throw DatabaseError.configurationError("File access error: \(error.localizedDescription)\n\n→ Go to Edit Connection → Click \"Change\" → Select the file again")
                }
            } catch {
                throw DatabaseError.configurationError("Cannot access the selected SQLite file.\n\n→ Go to Edit Connection → Click \"Change\" → Select the file again")
            }
        }
        
        // Handle other formats - these don't need security-scoped access
        if connectionString.hasPrefix("sqlite://") {
            let path = String(connectionString.dropFirst(9)) // Remove "sqlite://"
            return path.isEmpty ? ":memory:" : path
        } else if connectionString.hasPrefix("file:") {
            return String(connectionString.dropFirst(5)) // Remove "file:"
        } else {
            // Direct file path
            return connectionString
        }
    }
    
    /// Quotes an identifier, doubling any embedded double-quotes so they can't break out
    nonisolated func escapeIdentifier(_ identifier: String) -> String {
        return "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func validateAndSanitizeIdentifier(_ identifier: String) throws -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            throw DatabaseError.configurationError("Identifier cannot be empty")
        }

        return escapeIdentifier(trimmed)
    }
    
    private func buildWhereClause(from filter: DatabaseDocument) -> String {
        let filteredDict = filter.filter { key, _ in key != "rawQuery" }
        guard !filteredDict.isEmpty else { return "" }
        
        let conditions = filteredDict.map { key, value in
            let escapedKey = escapeIdentifier(key)
            switch value {
            case .string(let stringValue), .decimalString(let stringValue), .objectID(let stringValue):
                return "\(escapedKey) = '\(stringValue.replacing("'", with: "''"))'"
            case .int(let numberValue):
                return "\(escapedKey) = \(numberValue)"
            case .int64(let numberValue):
                return "\(escapedKey) = \(numberValue)"
            case .double(let numberValue):
                return "\(escapedKey) = \(numberValue)"
            case .bool(let boolValue):
                return "\(escapedKey) = \(boolValue ? 1 : 0)"
            case .null:
                return "\(escapedKey) IS NULL"
            default:
                return "\(escapedKey) = '\(value.description.replacing("'", with: "''"))'"
            }
        }
        
        return conditions.joined(separator: " AND ")
    }
    
    private func buildOrderByClause(sortBy: String?, ascending: Bool?) -> String {
        guard let sortBy = sortBy, !sortBy.isEmpty else { return "" }
        
        let direction = ascending == false ? "DESC" : "ASC"
        return "ORDER BY \(escapeIdentifier(sortBy)) \(direction)"
    }
    
    private func buildSchemaPrompt(for collectionName: String) async -> String {
        do {
            guard let schemaResult = try await getSchema(for: collectionName, schema: String?(nil)) else {
                return "No schema found for \(collectionName)\n"
            }
            let columnInfo = schemaResult.columns
                .map { column in
                    let nullable = column.isNullable == "YES" ? "NULL" : "NOT NULL"
                    let defaultValue = column.columnDefault.map { " DEFAULT \($0)" } ?? ""
                    return "\(column.columnName): \(column.dataType) \(nullable)\(defaultValue)"
                }
                .joined(separator: "\n")

            return """
            Table: \(schemaResult.tableName)
            Schema: \(schemaResult.schemaName)
            Columns:
            \(columnInfo)
            """
        } catch {
            return "No schema found for \(collectionName)\n"
        }
    }
    
    private func getPrimaryKeyColumn(for tableName: String) async throws -> String? {
        let connection = try await ensureConnected()
        let sanitizedTableName = try validateAndSanitizeIdentifier(tableName)
        
        do {
            let rows = try await connection.query("PRAGMA table_info(\(sanitizedTableName))")
            
            for row in rows {
                if let primaryKey = row.column("pk")?.integer,
                   primaryKey == 1,
                   let columnName = row.column("name")?.string {
                    return "\"\(columnName)\""
                }
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    private func convertToSQLiteData(_ value: DatabaseValue) -> SQLiteData {
        switch value {
        case .null:
            return .null
        case .int(let value):
            return .integer(value)
        case .int64(let value):
            return .integer(Int(clamping: value))
        case .double(let value):
            return .float(value)
        case .string(let value), .decimalString(let value), .objectID(let value):
            return .text(value)
        case .data(let value):
            let allocator = ByteBufferAllocator()
            var buffer = allocator.buffer(capacity: value.count)
            buffer.writeBytes(value)
            return .blob(buffer)
        case .bool(let value):
            return .integer(value ? 1 : 0)
        case .date(let value):
            return .text(value.ISO8601Format())
        case .uuid(let value):
            return .text(value.uuidString)
        case .array, .object:
            return .text(value.description)
        }
    }
    
    private func findFirstSQLiteFile(securityScopedURL: URL?) throws -> String? {
        let fileManager = FileManager.default
        
        // Always require security-scoped URL for proper access
        guard let securityScopedURL = securityScopedURL else {
            throw DatabaseError.configurationError("Security-scoped URL is required to access the selected folder. Please select the folder again using the folder button (📁).")
        }
        
        guard let contents = try? fileManager.contentsOfDirectory(at: securityScopedURL, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            throw DatabaseError.configurationError("Cannot access the contents of the selected folder. Please ensure you have permission to access this location.")
        }
        
        // Define SQLite file extensions to look for
        let sqliteExtensions = ["db", "sqlite", "sqlite3"]
        
        // First, look for files with standard SQLite extensions
        for fileURL in contents {
            let fileExtension = fileURL.pathExtension.lowercased()
            if sqliteExtensions.contains(fileExtension) {
                // Check if it's a file (not a directory)
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                   let isDirectory = resourceValues.isDirectory, !isDirectory {
                    // Basic SQLite file validation - check if file starts with "SQLite format 3"
                    if isSQLiteFile(at: fileURL.path) {
                        return fileURL.path
                    }
                }
            }
        }
        
        // If no files with standard extensions found, look for files without extensions that might be SQLite
        for fileURL in contents {
            let fileExtension = fileURL.pathExtension
            if fileExtension.isEmpty {
                // Check if it's a file (not a directory)
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                   let isDirectory = resourceValues.isDirectory, !isDirectory {
                    // Check if it's a SQLite file by examining its header
                    if isSQLiteFile(at: fileURL.path) {
                        return fileURL.path
                    }
                }
            }
        }
        
        return nil
    }
    
    private func isSQLiteFile(at path: String) -> Bool {
        // SQLite files start with "SQLite format 3\0" (16 bytes)
        let sqliteHeader = Data("SQLite format 3\0".utf8)

        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            return false
        }
        defer { try? fileHandle.close() }

        // Read only the header bytes so large database files aren't loaded into memory
        guard let headerData = try? fileHandle.read(upToCount: sqliteHeader.count) else {
            return false
        }

        return headerData == sqliteHeader
    }

    // MARK: - Schema Modification Methods

    func addColumn(
        to tableName: String,
        schema: String?,
        column: DatabaseSchemaInfo
    ) async throws {
        let connection = try await ensureConnected()
        let sanitizedTable = try validateAndSanitizeIdentifier(tableName)

        let dataType = column.formatType.isEmpty ? column.dataType : column.formatType

        var sql = "ALTER TABLE \(sanitizedTable) ADD COLUMN \"\(column.columnName)\" \(dataType)"

        // Handle NOT NULL constraint - SQLite requires DEFAULT for NOT NULL in ADD COLUMN
        if column.isNullable == "NO" {
            if let defaultValue = column.columnDefault, !defaultValue.trimmingCharacters(in: .whitespaces).isEmpty {
                sql += " NOT NULL DEFAULT \(defaultValue)"
            } else {
                // SQLite cannot add NOT NULL column without default, use a sensible default
                sql += " NOT NULL DEFAULT ''"
            }
        } else if let defaultValue = column.columnDefault, !defaultValue.trimmingCharacters(in: .whitespaces).isEmpty {
            sql += " DEFAULT \(defaultValue)"
        }

        do {
            _ = try await connection.query(sql)
            debugLog("Added column \(column.columnName) to table \(tableName)")
        } catch {
            throw DatabaseError.operationFailed(
                "Failed to add column '\(column.columnName)': \(error.localizedDescription)",
                query: sql
            )
        }
    }

    func modifyColumn(
        in tableName: String,
        schema: String?,
        columnName: String,
        newColumn: DatabaseSchemaInfo
    ) async throws {
        let connection = try await ensureConnected()
        let sanitizedTable = try validateAndSanitizeIdentifier(tableName)

        // SQLite has limited ALTER TABLE support
        // - RENAME COLUMN is supported in SQLite 3.25+ (2018)
        // - Changing type/constraints requires table rebuild

        do {
            // Step 1: Rename column if name changed
            if columnName != newColumn.columnName {
                let renameSQL = "ALTER TABLE \(sanitizedTable) RENAME COLUMN \"\(columnName)\" TO \"\(newColumn.columnName)\""
                _ = try await connection.query(renameSQL)
                debugLog("Renamed column \(columnName) to \(newColumn.columnName) in table \(tableName)")
            }

            // Note: SQLite doesn't support changing column type or constraints directly
            // A full table rebuild would be needed for type/constraint changes
            // For now, we only support renaming
            debugLog("Modified column \(newColumn.columnName) in table \(tableName)")
        } catch {
            throw DatabaseError.operationFailed(
                "Failed to modify column '\(columnName)': \(error.localizedDescription)"
            )
        }
    }

    func dropColumn(
        from tableName: String,
        schema: String?,
        columnName: String
    ) async throws {
        let connection = try await ensureConnected()
        let sanitizedTable = try validateAndSanitizeIdentifier(tableName)

        // DROP COLUMN is supported in SQLite 3.35+ (2021)
        let sql = "ALTER TABLE \(sanitizedTable) DROP COLUMN \"\(columnName)\""

        do {
            _ = try await connection.query(sql)
            debugLog("Dropped column \(columnName) from table \(tableName)")
        } catch {
            throw DatabaseError.operationFailed(
                "Failed to drop column '\(columnName)': \(error.localizedDescription). Note: DROP COLUMN requires SQLite 3.35+",
                query: sql
            )
        }
    }

    func createIndex(
        on tableName: String,
        schema: String?,
        index: DatabaseIndexInfo
    ) async throws {
        let connection = try await ensureConnected()
        let sanitizedTable = try validateAndSanitizeIdentifier(tableName)

        // Build column list
        let columnList = index.columns.map { "\"\($0)\"" }.joined(separator: ", ")

        guard !columnList.isEmpty else {
            throw DatabaseError.operationFailed("Cannot create index without columns")
        }

        var sql = "CREATE"

        // UNIQUE keyword
        if index.isUnique {
            sql += " UNIQUE"
        }

        sql += " INDEX \"\(index.name)\" ON \(sanitizedTable) (\(columnList))"

        // SQLite only supports BTREE indexes, no USING clause needed

        do {
            _ = try await connection.query(sql)
            debugLog("Created index \(index.name) on table \(tableName)")
        } catch {
            throw DatabaseError.operationFailed(
                "Failed to create index '\(index.name)': \(error.localizedDescription)",
                query: sql
            )
        }
    }

    func dropIndex(
        indexName: String,
        tableName: String,
        schema: String?
    ) async throws {
        let connection = try await ensureConnected()

        // SQLite doesn't require table name when dropping index
        let sql = "DROP INDEX \"\(indexName)\""

        do {
            _ = try await connection.query(sql)
            debugLog("Dropped index \(indexName)")
        } catch {
            throw DatabaseError.operationFailed(
                "Failed to drop index '\(indexName)': \(error.localizedDescription)",
                query: sql
            )
        }
    }
}
