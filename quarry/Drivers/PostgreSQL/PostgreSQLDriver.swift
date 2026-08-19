import Foundation
import Logging
import PostgresNIO
import NIOCore
import NIOSSL

// MARK: - PostgreSQL Wrappers
struct PostgreSQLDatabaseWrapper: DatabaseWrapper {
    let name: String
    let size: String?
    let tableCount: Int?
}

struct PostgreSQLCollectionWrapper: CollectionWrapper {
    var id: ObjectIdentifier
    let name: String
    let oid: String
    let type: String
    let schema: String?
}

struct PostgreSQLColumnInfo {
    let name: String
    let dataType: PostgresDataType
    let format: PostgresFormat
    let index: Int
}

struct PostgreSQLQueryResult {
    let columns: [PostgreSQLColumnInfo]
    let rows: [PostgresRandomAccessRow]
    let totalCount: Int
    let rawRows: [PostgresRandomAccessRow]

    // Convenience computed properties
    var columnNames: [String] {
        return columns.map { $0.name }
    }

    var columnCount: Int {
        return columns.count
    }

    var rowCount: Int {
        return rows.count
    }

    // Get specific column info by name
    func column(named name: String) -> PostgreSQLColumnInfo? {
        return columns.first { $0.name == name }
    }

    // Get column info by index
    func column(at index: Int) -> PostgreSQLColumnInfo? {
        guard index >= 0 && index < columns.count else { return nil }
        return columns[index]
    }

    func rawCell(row: Int, column: String) -> PostgresCell? {
        guard row < rawRows.count else { return nil }
        let randomAccessRow = rawRows[row]
        guard randomAccessRow.contains(column) else { return nil }
        return randomAccessRow[column]
    }

    // For compatibility - decode on demand
    func value(row: Int, column: String) -> Any? {
        guard let cell = rawCell(row: row, column: column) else { return nil }
        do {
            return try decodeValue(from: cell)
        } catch {
            debugLog("PostgreSQLQueryResult decode error for column '\(column)': \(String(reflecting: error))")
            return nil
        }
    }

    private func decodeValue(from cell: PostgresCell) throws -> Any? {
        guard cell.bytes != nil else { return nil }

        switch cell.dataType {
        case .bool: return try cell.decode(Bool.self)
        case .int2: return try cell.decode(Int16.self)
        case .int4: return try cell.decode(Int32.self)
        case .int8: return try cell.decode(Int64.self)
        case .float4: return try cell.decode(Float.self)
        case .float8: return try cell.decode(Double.self)
        case .text, .varchar, .char: return try cell.decode(String.self)
        case .timestamp, .timestamptz, .date: return try cell.decode(Date.self)
        case .uuid: return try cell.decode(UUID.self)
        case .json, .jsonb: return try cell.decode(String.self)
        case .bytea: return try cell.decode(Data.self)
        case .numeric: return try cell.decode(String.self)
        default: return try cell.decode(String.self)
        }
    }
}

// MARK: - PostgreSQL Driver
actor PostgreSQLDriver: DatabaseDriver {
    func findDocuments(in collectionName: String, filter: DatabaseDocument) async throws -> [QueryResult] {
        let result = try await findDocuments(
            in: collectionName,
            databaseSchema: nil,
            filter: filter,
            skip: 0,
            limit: 100,
            sortBy: nil,
            ascending: nil
        )
        return [result]
    }

    typealias Database = PostgreSQLDatabaseWrapper
    typealias Collection = PostgreSQLCollectionWrapper

    private var client: PostgresClient?
    private var clientTask: Task<Void, Never>?
    private var directConnection: PostgresConnection?
    private var directEventLoopGroup: MultiThreadedEventLoopGroup?
    private var isConnected = false
    private var connectionUri: String?

    // Connection configuration
    private var clientConfiguration: PostgresClient.Configuration?
    private var databases: [PostgreSQLDatabaseWrapper] = []
    private var schema: [PostgreSQLDatabaseWrapper] = []
    private var collections: [PostgreSQLCollectionWrapper] = []

    /// Upper bound on rows materialized from a raw query, to keep memory in check.
    private static let maxRawQueryRows = 100_000

    private func splitSQLStatements(_ sql: String) -> [String] {
        var statements: [String] = []
        var currentStatement = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var inDollarQuote = false
        var dollarTag = ""
        var i = sql.startIndex

        while i < sql.endIndex {
            let char = sql[i]

            if inDollarQuote {
                currentStatement.append(char)
                if char == "$" {
                    let remaining = sql[i...]
                    if remaining.hasPrefix(dollarTag) {
                        let endIndex = sql.index(i, offsetBy: dollarTag.count)
                        currentStatement.append(contentsOf: sql[sql.index(after: i)..<endIndex])
                        i = endIndex
                        inDollarQuote = false
                        dollarTag = ""
                        continue
                    }
                }
            } else if inSingleQuote {
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
                case "$":
                    var tag = "$"
                    var j = sql.index(after: i)
                    while j < sql.endIndex {
                        let c = sql[j]
                        if c == "$" {
                            tag.append(c)
                            break
                        } else if c.isLetter || c.isNumber || c == "_" {
                            tag.append(c)
                        } else {
                            break
                        }
                        j = sql.index(after: j)
                    }
                    if tag.count > 1 && tag.hasSuffix("$") {
                        inDollarQuote = true
                        dollarTag = tag
                        currentStatement.append(contentsOf: tag)
                        i = j
                        continue
                    } else {
                        currentStatement.append(char)
                    }
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

    deinit {
        clientTask?.cancel()
        if let directConnection, let directEventLoopGroup {
            Task.detached {
                try? await directConnection.close()
                try? await directEventLoopGroup.shutdownGracefully()
            }
        } else if let directEventLoopGroup {
            Task.detached { try? await directEventLoopGroup.shutdownGracefully() }
        }
    }

    func connect(to connectionUri: String) async throws -> PostgreSQLDatabaseWrapper {
        self.connectionUri = connectionUri
        let config = try PostgreSQLConnectionStringParser.parseClientConfiguration(connectionUri)
        return try await establishConnection(with: config, fallbackConnectionUri: connectionUri)
    }

    private func establishConnection(
        with config: PostgresClient.Configuration,
        fallbackConnectionUri: String?
    ) async throws -> PostgreSQLDatabaseWrapper {
        self.clientConfiguration = config

        var poolConfig = config
        poolConfig.options.minimumConnections = 1
        poolConfig.options.maximumConnections = 5
        poolConfig.options.keepAliveBehavior = nil
        poolConfig.options.additionalStartupParameters = [("application_name", "Quarry")]

        let client = PostgresClient(configuration: poolConfig)
        self.client = client

        self.clientTask = Task {
            await client.run()
        }

        // Verify connectivity eagerly so connection errors surface at connect time
        do {
            try await withPoolTimeout {
                let rows = try await client.query("SELECT 1", logger: Logger(label: "postgres"))
                for try await _ in rows {}
            }
        } catch let error as PSQLError {
            closePoolClient()
            throw mapPSQLError(error)
        } catch let error as DatabaseError {
            closePoolClient()
            if let fallbackConnectionUri {
                return try await establishDirectConnection(connectionUri: fallbackConnectionUri)
            }
            throw error
        } catch {
            closePoolClient()
            throw DatabaseError.connectionFailed("Failed to establish PostgreSQL connection: \(error.localizedDescription)")
        }

        self.isConnected = true
        return PostgreSQLDatabaseWrapper(name: config.database ?? "postgres", size: nil, tableCount: nil)
    }

    private func closePoolClient() {
        clientTask?.cancel()
        clientTask = nil
        client = nil
    }

    private func establishDirectConnection(connectionUri: String) async throws -> PostgreSQLDatabaseWrapper {
        let config = try PostgreSQLConnectionStringParser.parseConfiguration(connectionUri)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        do {
            let connection = try await withPoolTimeout {
                try await PostgresConnection.connect(
                    on: eventLoopGroup.next(),
                    configuration: config,
                    id: 1,
                    logger: Logger(label: "postgres-direct-fallback")
                )
            }

            try await withPoolTimeout {
                let rows = try await connection.query("SELECT 1", logger: Logger(label: "postgres-direct-fallback"))
                for try await _ in rows {}
            }

            self.directConnection = connection
            self.directEventLoopGroup = eventLoopGroup
            self.isConnected = true
            return PostgreSQLDatabaseWrapper(name: config.database ?? "postgres", size: nil, tableCount: nil)
        } catch let error as PSQLError {
            try? await eventLoopGroup.shutdownGracefully()
            throw mapPSQLError(error)
        } catch {
            try? await eventLoopGroup.shutdownGracefully()
            throw DatabaseError.connectionFailed("Failed to establish PostgreSQL connection: \(error.localizedDescription)")
        }
    }

    func disconnect() async {
        closePoolClient()
        if let directConnection {
            try? await directConnection.close()
        }
        directConnection = nil
        if let directEventLoopGroup {
            try? await directEventLoopGroup.shutdownGracefully()
        }
        directEventLoopGroup = nil

        await databaseSchema.removeAll()
        primaryKeyCache.removeAll()

        self.isConnected = false
    }

    /// Runs an async operation with a timeout. Throws if the operation doesn't
    /// complete within `seconds`. Used to prevent pool lease hangs when the
    /// server is unreachable.
    private func withPoolTimeout<T: Sendable>(
        seconds: Double = 15,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw DatabaseError.connectionFailed("Unable to reach the database server within \(Int(seconds)) seconds")
            }
            guard let result = try await group.next() else {
                throw DatabaseError.connectionFailed("Unable to reach the database server within \(Int(seconds)) seconds")
            }
            group.cancelAll()
            return result
        }
    }

    /// Executes a query through the pool with a connection timeout guard.
    @discardableResult
    private func poolQuery(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        if let client {
            return try await withPoolTimeout {
                try await client.query(query, logger: Logger(label: "postgres"))
            }
        }

        if let directConnection {
            return try await withPoolTimeout {
                try await directConnection.query(query, logger: Logger(label: "postgres-direct-fallback"))
            }
        }

        throw DatabaseError.connectionFailed("No active connection")
    }

    func reconnect() async throws {
        try await poolQuery("SELECT 1")
    }

    func ping(to connectionUri: String) async throws {
        let config = try PostgreSQLConnectionStringParser.parseConfiguration(connectionUri)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let temp = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: config,
                id: 9999,
                logger: Logger(label: "postgres-ping")
            )
            try await temp.close()
            try await eventLoopGroup.shutdownGracefully()
        } catch let error as PSQLError {
            try? await eventLoopGroup.shutdownGracefully()
            throw mapPSQLError(error)
        } catch {
            try? await eventLoopGroup.shutdownGracefully()
            throw DatabaseError.connectionFailed("Ping failed: \(error.localizedDescription)")
        }
    }

    func switchDatabase(to databaseName: String) async throws {
        guard var config = self.clientConfiguration else {
            throw DatabaseError.configurationError("No active connection configuration")
        }

        config.database = databaseName

        await disconnect()

        let fallbackUri = connectionUriForDatabase(databaseName)
        _ = try await establishConnection(with: config, fallbackConnectionUri: fallbackUri)
    }

    private func connectionUriForDatabase(_ databaseName: String) -> String? {
        guard let connectionUri, var components = URLComponents(string: connectionUri) else {
            return nil
        }

        components.path = "/\(databaseName)"
        return components.url?.absoluteString
    }

    func getBuildInfo() async throws -> BuildInfo {
        do {
            let rows = try await poolQuery("SELECT version()")

            var fullVersionString = "Unknown"

            for try await (versionString) in rows.decode((String).self) {
                fullVersionString = versionString
            }

            guard let version = extractVersionNumber(from: fullVersionString) else {
                throw DatabaseError.operationFailed("Failed to extract build version")
            }

            let buildInfo = BuildInfo(
                version: version,
                databaseType: DatabaseType.postgres
            )
            return buildInfo
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to get build info: \(error.localizedDescription)")
        }
    }

    func listDatabases() async throws -> [PostgreSQLDatabaseWrapper] {
        do {
            let rows = try await poolQuery(
                "SELECT datname FROM pg_database WHERE datistemplate = false"
            )

            var databases: [PostgreSQLDatabaseWrapper] = []

            for try await (name) in rows.decode((String).self) {
                databases.append(PostgreSQLDatabaseWrapper(name: name, size: nil, tableCount: nil))
            }

            return databases
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to list databases: \(error.localizedDescription)")
        }
    }

    func listCollections(schema: String? = "public") async throws -> [PostgreSQLCollectionWrapper] {
        do {
            let effectiveSchema = schema ?? "public"
            var collections = try await loadTableCollections(in: effectiveSchema)

            let funcRows = try await poolQuery("""
                SELECT
                    p.oid::bigint AS oid,
                    p.proname || '(' || COALESCE(pg_get_function_identity_arguments(p.oid), '') || ')' AS func_name,
                    CASE p.prokind
                        WHEN 'f' THEN 'function'
                        WHEN 'p' THEN 'procedure'
                        ELSE 'function'
                    END AS type
                FROM pg_proc p
                JOIN pg_namespace n ON p.pronamespace = n.oid
                WHERE n.nspname = \(unescaped: quoteStringLiteral(effectiveSchema))
                    AND p.prokind IN ('f', 'p')
                ORDER BY p.proname
                """
            )

            for try await (oid, funcName, type) in funcRows.decode((Int64, String, String).self) {
                collections.append(PostgreSQLCollectionWrapper(
                    id: ObjectIdentifier(NSString(string: "func_\(oid)")),
                    name: funcName,
                    oid: oid.description,
                    type: type,
                    schema: effectiveSchema
                ))
            }

            return collections
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to list tables: \(error.localizedDescription)")
        }
    }

    private func loadTableCollections(in schema: String) async throws -> [PostgreSQLCollectionWrapper] {
        let rows = try await poolQuery("""
            SELECT
                c.oid::bigint AS oid,
                t.table_name,
                t.table_schema,
                CASE
                    WHEN c.relkind IN ('v', 'm') THEN 'view'
                    ELSE 'table'
                END AS type
            FROM information_schema.tables t
            JOIN pg_catalog.pg_namespace n
                ON n.nspname = t.table_schema
            JOIN pg_catalog.pg_class c
                ON c.relnamespace = n.oid
                AND c.relname = t.table_name
            WHERE t.table_schema = \(unescaped: quoteStringLiteral(schema))
                AND t.table_type IN ('BASE TABLE', 'VIEW')
                AND c.relkind IN ('r', 'p', 'v', 'm')
            ORDER BY t.table_name
            """
        )

        var collections: [PostgreSQLCollectionWrapper] = []
        for try await (oid, tableName, _, type) in rows.decode((Int64, String, String, String).self) {
            collections.append(PostgreSQLCollectionWrapper(
                id: ObjectIdentifier(NSString(string: tableName)),
                name: tableName,
                oid: oid.description,
                type: type,
                schema: schema
            ))
        }

        if !collections.isEmpty {
            return collections
        }

        let fallbackRows = try await poolQuery("""
            SELECT
                c.oid::bigint AS oid,
                c.relname AS table_name,
                n.nspname AS table_schema,
                CASE
                    WHEN c.relkind IN ('v', 'm') THEN 'view'
                    ELSE 'table'
                END AS type
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = \(unescaped: quoteStringLiteral(schema))
                AND c.relkind IN ('r', 'p', 'v', 'm')
            ORDER BY c.relname
            """
        )

        for try await (oid, tableName, _, type) in fallbackRows.decode((Int64, String, String, String).self) {
            collections.append(PostgreSQLCollectionWrapper(
                id: ObjectIdentifier(NSString(string: tableName)),
                name: tableName,
                oid: oid.description,
                type: type,
                schema: schema
            ))
        }

        return collections
    }

    func getFunctionDefinition(oid: String) async throws -> String {
        do {
            let rows = try await poolQuery(
                "SELECT pg_get_functiondef(\(unescaped: oid)::oid)"
            )

            for try await (definition,) in rows.decode((String).self) {
                return definition
            }
            throw DatabaseError.operationFailed("Function definition not found")
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to get function definition: \(error.localizedDescription)")
        }
    }

    func getDocumentCount(for collectionName: String, filter: DatabaseDocument) async throws -> Int {
        return 0
    }

    func findDocuments(in collectionName: String, filter: DatabaseDocument, skip: Int, limit: Int) async throws -> QueryResult {
        return try await findDocuments(in: collectionName, databaseSchema: nil, filter: filter, skip: skip, limit: limit, sortBy: nil, ascending: nil)
    }


    func findDocuments(in collectionName: String, databaseSchema: String?, filter: DatabaseDocument, skip: Int, limit: Int, sortBy: String?, ascending: Bool?) async throws -> QueryResult {
        let sanitizedCollectionName = try validateAndSanitizeIdentifier(collectionName, databaseSchema: databaseSchema)

        do {
            let query: PostgresQuery

            if let rawQuery = filter["rawQuery"]?.stringValue, !rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let pagedQuery = pageFilterQuery(rawQuery, skip: skip, limit: limit, sortBy: sortBy, ascending: ascending)
                let results = try await executeRawQuery(pagedQuery, databaseSchema: databaseSchema)
                return results.first ?? QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])
            } else {
                // Build standard query with optional WHERE clause and ORDER BY clause
                let whereClause = buildWhereClause(from: filter)

                // Pass the raw (unquoted) names through. The previous
                // `sanitizedCollectionName.dropFirst().dropLast()` trick
                // assumed the sanitized form was `"table"` and produced
                // `public"."address` for qualified names — which then matched
                // nothing and the query silently returned no PK, breaking
                // default ORDER BY.
                let primaryKey = try await getPrimaryKeyColumn(for: collectionName, in: databaseSchema ?? "public")
                let orderByClause = buildOrderByClause(sortBy: sortBy, ascending: ascending, primaryKey: primaryKey)

                var queryString = "SELECT * FROM \(sanitizedCollectionName)"

                if !whereClause.isEmpty {
                    queryString += " WHERE \(whereClause)"
                }

                if !orderByClause.isEmpty {
                    queryString += " \(orderByClause)"
                }

                queryString += " LIMIT \(limit) OFFSET \(skip)"

                query = PostgresQuery(stringLiteral: queryString)
            }

            let results = try await poolQuery(query)

            // Single-pass processing: build everything in one loop
            var queryColumns: [QueryColumnInfo] = []
            var convertedRows: [[String: QueryRowInfo]] = []
            var convertedRawRows: [DatabaseRawRow] = []
            var columnsInitialized = false

            for try await row in results {
                // Extract and convert column info only once
                if !columnsInitialized {
                    var columnIndex = 0
                    for cell in row {
                        queryColumns.append(QueryColumnInfo(
                            name: cell.columnName,
                            dataType: String(describing: cell.dataType),
                            format: String(describing: cell.format),
                            index: columnIndex
                        ))
                        columnIndex += 1
                    }
                    columnsInitialized = true
                }

                let randomAccessRow = row.makeRandomAccess()
                var processedRowData: [String: QueryRowInfo] = [:]
                var rawRowData: DatabaseRawRow = [:]

                for column in queryColumns {
                    let columnName = column.name
                        if randomAccessRow.contains(columnName) {
                            let cell = randomAccessRow[columnName]
                            do {
                                let decoded = try decode(from: cell)
                                processedRowData[columnName] = decoded
                                rawRowData[columnName] = decoded.value
                            } catch {
                                debugLog("findDocuments decode error for column '\(columnName)': \(String(reflecting: error))")
                                processedRowData[columnName] = nil
                                rawRowData[columnName] = nil
                            }
                        } else {
                            processedRowData[columnName] = nil
                        rawRowData[columnName] = nil
                    }
                }

                convertedRows.append(processedRowData)
                convertedRawRows.append(rawRowData)
            }

            return QueryResult(
                columns: queryColumns,
                rows: convertedRows,
                totalCount: convertedRows.count,
                rawRows: convertedRawRows
            )
        } catch let error as PSQLError {
            debugLog(String(reflecting: error))
            throw mapPSQLError(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DatabaseError.operationFailed("Failed to find documents: \(error.localizedDescription)")
        }
    }

    func createDocument(in collectionName: String, databaseSchema: String?, document: DatabaseDocument) async throws {
        let sanitizedCollectionName = try validateAndSanitizeIdentifier(collectionName, databaseSchema: databaseSchema)

        guard !document.isEmpty else {
            throw DatabaseError.operationFailed("Cannot insert an empty document.")
        }

        do {
            // Get the schema to determine correct data types
            let schema = try await getSchema(for: collectionName, in: databaseSchema ?? "public")
            let columnTypes = Dictionary(uniqueKeysWithValues: schema.columns.map { ($0.columnName, $0.typeOid) })
            let columnTypeNames = Dictionary(uniqueKeysWithValues: schema.columns.map { ($0.columnName, $0.dataType) })

            // Sort keys for consistent parameter order
            let sortedKeys = document.keys.sorted()

            let columns = sortedKeys.map { "\"\($0)\"" }.joined(separator: ", ")

            // Build value placeholders with proper casting for special column types
            var valuePlaceholders: [String] = []
            var values: [PostgresEncodable?] = []
            var parameterIndex = 1

            for key in sortedKeys {
                let columnTypeString = columnTypes[key] ?? 0
                let columnType = PostgresDataType(UInt32(columnTypeString))
                let columnTypeName = columnTypeNames[key]

                // For user-defined types (enums), pass the actual type name
                let enumTypeName = columnType.isUserDefined ? columnTypeName : nil

                // Use buildSetClause to get the type casting, but extract just the casting part
                let setClause = buildSetClause(for: key, parameterIndex: parameterIndex, columnType: columnType, enumTypeName: enumTypeName)
                // Extract just the parameter placeholder with casting from the SET clause
                if let castingPart = setClause.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) {
                    valuePlaceholders.append(castingPart)
                } else {
                    valuePlaceholders.append("$\(parameterIndex)")
                }

                // Convert and add value
                let value = document[key] ?? .null
                let convertedValue = try encode(value, columnName: key, columnType: columnType)
                values.append(convertedValue)

                parameterIndex += 1
            }

            let queryString = "INSERT INTO \(sanitizedCollectionName) (\(columns)) VALUES (\(valuePlaceholders.joined(separator: ", ")))"

            var bindings = PostgresBindings(capacity: values.count)

            for value in values {
                if let value = value {
                    try bindings.append(value)
                } else {
                    bindings.appendNull()
                }
            }

            let query = PostgresQuery(unsafeSQL: queryString, binds: bindings)
            try await poolQuery(query)

        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.operationFailed("Failed to create document: \(error.localizedDescription)")
        }
    }

    func updateDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID, data: DatabaseDocument) async throws {
        let sanitizedCollectionName = try validateAndSanitizeIdentifier(collectionName, databaseSchema: databaseSchema)

        guard !data.isEmpty else {
            throw DatabaseError.operationFailed("No changes detected to update")
        }

        do {
            let (setClause, values) = try await buildParameterizedSetClause(dataToUpdate: data, for: collectionName, in: databaseSchema ?? "public")
            let schema = try await getSchema(for: collectionName, in: databaseSchema ?? "public")
            let columnTypes = Dictionary(uniqueKeysWithValues: schema.columns.map { ($0.columnName, $0.typeOid) })
            let idColumnType = PostgresDataType(UInt32(columnTypes[id.columnName] ?? 0))
            let encodedID = try encode(id.value, columnName: id.columnName, columnType: idColumnType)
            let sanitizedIDColumn = try validateAndSanitizeColumnName(id.columnName)
            let idCast = idColumnType == .uuid ? "::uuid" : ""

            // Build the UPDATE query with parameter binding
            let queryString = """
                UPDATE \(sanitizedCollectionName)
                SET \(setClause)
                WHERE \(sanitizedIDColumn) = $\(values.count + 1)\(idCast)
            """

            var bindings = PostgresBindings(capacity: values.count + 1)

            for value in values {
                switch value {
                case .none:
                    bindings.appendNull()
                case let .some(value):
                    try bindings.append(value)
                }
            }

            if let encodedID {
                try bindings.append(encodedID)
            } else {
                bindings.appendNull()
            }

            // Execute the update query with parameter binding
            let query = PostgresQuery(unsafeSQL: queryString, binds: bindings)
            try await poolQuery(query)
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.operationFailed("Failed to update document: \(error.localizedDescription)")
        }
    }

    func decodePostgresTime(from cell: PostgresCell) -> (hour: Int, minute: Int, second: Int, microsecond: Int)? {
        guard cell.dataType == .time, var value = cell.bytes else { return nil }
        // TIME is sent as Int64 microseconds since midnight
        guard let microseconds = value.readInteger(as: Int64.self) else { return nil }
        let totalSeconds = microseconds / 1_000_000
        let hour = Int(totalSeconds / 3600)
        let minute = Int((totalSeconds % 3600) / 60)
        let second = Int(totalSeconds % 60)
        let microsecond = Int(microseconds % 1_000_000)
        return (hour, minute, second, microsecond)
    }

    func deleteDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID) async throws {
        let sanitizedCollectionName = try validateAndSanitizeIdentifier(collectionName, databaseSchema: databaseSchema)

        do {
            let schema = try await getSchema(for: collectionName, in: databaseSchema ?? "public")
            let columnTypes = Dictionary(uniqueKeysWithValues: schema.columns.map { ($0.columnName, $0.typeOid) })
            let idColumnType = PostgresDataType(UInt32(columnTypes[id.columnName] ?? 0))
            let encodedID = try encode(id.value, columnName: id.columnName, columnType: idColumnType)
            let sanitizedIDColumn = try validateAndSanitizeColumnName(id.columnName)
            let idCast = idColumnType == .uuid ? "::uuid" : ""
            // Build the DELETE query with parameter binding
            let queryString = """
                DELETE FROM \(sanitizedCollectionName)
                WHERE \(sanitizedIDColumn) = $1\(idCast)
            """

            // Create PostgresBindings and append the primary key value
            var bindings = PostgresBindings(capacity: 1)

            if let encodedID {
                try bindings.append(encodedID)
            } else {
                bindings.appendNull()
            }

            // Execute the delete query with parameter binding
            let query = PostgresQuery(unsafeSQL: queryString, binds: bindings)
            try await poolQuery(query)
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to delete document: \(error.localizedDescription)")
        }
    }

    func executeRawQuery(_ query: String, databaseSchema: String?) async throws -> [QueryResult] {
        let statements = splitSQLStatements(query)

        if statements.isEmpty {
            return [QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])]
        }

        var results: [QueryResult] = []

        for statement in statements {
            do {
                let result = try await executeRawStatement(statement)
                results.append(result)

            } catch let error as PSQLError {
                throw mapPSQLError(error, query: statement)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw DatabaseError.operationFailed("Failed to execute statement: \(error.localizedDescription)")
            }
        }

        return results.isEmpty ? [QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])] : results
    }

    private func executeRawStatement(_ statement: String) async throws -> QueryResult {
        let query = PostgresQuery(stringLiteral: statement)
        let queryResults = try await poolQuery(query)
        return try await processRawQueryRows(queryResults)
    }

    private func processRawQueryRows(_ queryResults: PostgresRowSequence) async throws -> QueryResult {
        var queryColumns: [QueryColumnInfo] = []
        var convertedRows: [[String: QueryRowInfo]] = []
        var convertedRawRows: [DatabaseRawRow] = []
        var columnsInitialized = false

        for try await row in queryResults {
            if convertedRows.count % 1_000 == 0, Task.isCancelled {
                throw CancellationError()
            }

            if !columnsInitialized {
                var columnIndex = 0
                for cell in row {
                    queryColumns.append(QueryColumnInfo(
                        name: cell.columnName,
                        dataType: String(describing: cell.dataType),
                        format: String(describing: cell.format),
                        index: columnIndex
                    ))
                    columnIndex += 1
                }
                columnsInitialized = true
            }

            let randomAccessRow = row.makeRandomAccess()
            var processedRowData: [String: QueryRowInfo] = [:]
            var rawRowData: DatabaseRawRow = [:]

            for column in queryColumns {
                let columnName = column.name
                if randomAccessRow.contains(columnName) {
                    let cell = randomAccessRow[columnName]
                    do {
                        let decoded = try decode(from: cell)
                        processedRowData[columnName] = decoded
                        rawRowData[columnName] = decoded.value
                    } catch {
                        debugLog("executeRawQuery decode error for column '\(columnName)': \(String(reflecting: error))")
                        processedRowData[columnName] = nil
                        rawRowData[columnName] = nil
                    }
                } else {
                    processedRowData[columnName] = nil
                    rawRowData[columnName] = nil
                }
            }

            convertedRows.append(processedRowData)
            convertedRawRows.append(rawRowData)

            if convertedRows.count >= Self.maxRawQueryRows {
                debugLog("executeRawQuery: result truncated at \(Self.maxRawQueryRows) rows")
                break
            }
        }

        return QueryResult(
            columns: queryColumns,
            rows: convertedRows,
            totalCount: convertedRows.count,
            rawRows: convertedRawRows
        )
    }

    func createCollection(named collectionName: String) async throws {
        throw DatabaseError.notImplemented("Support for creating tables not yet implemented")
    }

    func renameCollection(databaseSchema: String?, from oldName: String, to newName: String) async throws {
        let sanitizedOldName = try validateAndSanitizeIdentifier(oldName, databaseSchema: databaseSchema)
        let sanitizedNewName = try validateAndSanitizeIdentifier(newName, databaseSchema: nil)

        let query = PostgresQuery("ALTER TABLE \(unescaped: sanitizedOldName) RENAME TO \(unescaped: sanitizedNewName)")

        do {
            try await poolQuery(query)
            // Clear schema cache for both old and new names
            await clearSchemaCache(for: oldName)
            await clearSchemaCache(for: newName)
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed(error.localizedDescription)
        }
    }

    func deleteCollection(named collectionName: String, databaseSchema: String?) async throws {
        let sanitizedTableName = try validateAndSanitizeIdentifier(collectionName, databaseSchema: databaseSchema)

        let query = PostgresQuery("DROP TABLE \(unescaped: sanitizedTableName)")

        do {
            try await poolQuery(query)
            // Clear schema cache since we deleted the table
            await clearSchemaCache(for: collectionName)
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed(error.localizedDescription)
        }
    }

    func getSchema(for collectionName: String, schema: String?) async throws -> DatabaseSchemaResult? {
        return try await getSchema(for: collectionName, in: schema ?? "public")
    }

    func getInformationSchema() async throws -> [InformationSchema] {
        do {
            let query = PostgresQuery("""
            SELECT schema_name
                FROM information_schema.schemata
                WHERE schema_name NOT IN ('information_schema', 'pg_catalog')
                  AND schema_name NOT LIKE 'pg_temp_%'
                  AND schema_name NOT LIKE 'pg_toast%'
                  AND schema_name NOT LIKE 'pg_%'
                ORDER BY schema_name;
            """)

            let results = try await poolQuery(query)
            var schemas: [InformationSchema] = []

            for try await (schemaName) in results.decode((String).self) {
                schemas.append(InformationSchema(name: schemaName))
            }

            return schemas.isEmpty ? [InformationSchema(name: "public")] : schemas
        } catch let error as PSQLError {
            debugLog("Error fetching schemas: \(error)")
            throw mapPSQLError(error)
        } catch {
            debugLog("Error fetching schemas: \(error)")
            throw DatabaseError.operationFailed("Failed to fetch schemas: \(error.localizedDescription)")
        }
    }

    func buildAICommandPromptSystemPrompt(_ message: String) async throws -> String {
        let currentDate = Date().formatted(.iso8601)

        // Get all available tables/collections
        let collections = try await listCollections(schema: "public")
        let tablesList = collections.map { "- \($0.name) (\($0.type))" }.joined(separator: "\n")

        return """
        You are a PostgreSQL query assistant for a desktop database client's CMD+K quick action. Your output is inserted directly into a SQL editor, so respond with only the SQL query as plain text. Your output must be valid, executable PostgreSQL.

        <available_tables>
        \(tablesList)
        </available_tables>

        <instructions>
        1. For new queries, start with a single-line SQL comment describing what the query does, then the query itself.
        2. For query modifications, return only the modified query. Preserve the original formatting style.
        3. For query fixes, return only the corrected query.
        4. Use table names from the available tables list. If a name seems misspelled, use the closest match.
        5. Always wrap table and column identifiers in double quotes (e.g., FROM "users", "users"."created_at"). This is required for case-sensitive or mixed-case names in PostgreSQL.
        6. Default to SELECT * unless the user specifies columns.
        7. Use ILIKE for case-insensitive string matching.
        8. Use PostgreSQL date/time functions (CURRENT_DATE, INTERVAL, etc.).
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
          AND "created_at" >= CURRENT_DATE - INTERVAL '30 days';
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
        let schema = await buildSchemaPrompt(for: collectionName, databaseSchema: databaseSchema)

        return """
        You are a PostgreSQL query assistant. Your primary task is to convert natural language user queries into valid PostgreSQL SQL queries.

        Core Responsibilities:
        - Convert the user query into a PostgreSQL SQL query.
        - Return ONLY the SQL query without explanation.
        - Optimize the query for best performance.
        - Support all PostgreSQL operators and query features.

        # Database Schema
        The current table schema is:
        \(schema)

        # Output Format
        Return ONLY the PostgreSQL SQL query.
        Do not include any explanation, preamble, or commentary.
        Format the query for readability with proper indentation.
        One-line queries are acceptable for simple filters.

        # Examples

        **Example 1:**
        **Input:** Find all users where age is greater than 30
        **Output:**
        SELECT * FROM "users" WHERE "age" > 30;

        **Example 2:**
        **Input:** Get records where status is active and created date is in the last week
        **Output:**
        SELECT * FROM "records"
        WHERE "status" = 'active'
        AND "created_at" > CURRENT_DATE - INTERVAL '7 days';

        **Example 3:**
        **Input:** Show me customers from New York or California with at least 5 orders
        **Output:**
        SELECT * FROM "customers"
        WHERE ("state" = 'New York' OR "state" = 'California')
        AND "order_count" >= 5;

        **Example 4:**
        **Input:** Get user with id 12345
        **Output:**
        SELECT * FROM "users" WHERE "id" = 12345;

        **Example 5:**
        **Input:** Find products containing 'laptop' in name, ordered by price descending
        **Output:**
        SELECT * FROM "products"
        WHERE "name" ILIKE '%laptop%'
        ORDER BY "price" DESC;

        # Notes
        - NEVER provide explanations or ask clarifying questions.
        - NEVER describe what the query does.
        - Use the provided schema to understand available columns and data types.
        - When user input is ambiguous, refer to the schema for proper column names.
        - Use appropriate PostgreSQL operators (=, >, <, IN, LIKE, ILIKE, etc.) based on query requirements.
        - Use ILIKE for case-insensitive string matching.
        - Use proper PostgreSQL date/time functions (CURRENT_DATE, INTERVAL, etc.).
        - Default to SELECT * unless specific columns are mentioned.
        - Always wrap table and column identifiers in double quotes (e.g., FROM "users", "users"."created_at"). This is required for case-sensitive or mixed-case names in PostgreSQL.
        - Include proper semicolon termination.
        - Return the SQL query as plain text only. Do NOT use code blocks, backticks, or any markdown formatting.
        - Only generate SELECT queries. Do not create UPDATE, DELETE, INSERT, or any data-modifying queries.

        Current Date: \(currentDate)
        """
    }

    private func buildSchemaPrompt(for collectionName: String, databaseSchema: String?) async -> String {
        do {
            let schemaResult = try await getSchema(for: collectionName)
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


    // MARK: - Schema Cache

    /// Efficient composite key for schema caching
    private struct SchemaKey: Hashable {
        let schemaName: String
        let tableName: String

        init(_ schemaName: String, _ tableName: String) {
            self.schemaName = schemaName
            self.tableName = tableName
        }
    }

    /// Thread-safe schema cache with size limits
    private actor SchemaCache {
        private var cache: [SchemaKey: DatabaseSchemaResult] = [:]
        private let maxSize: Int
        private var accessOrder: [SchemaKey] = [] // For LRU eviction

        init(maxSize: Int = 100) {
            self.maxSize = maxSize
        }

        func get(_ key: SchemaKey) -> DatabaseSchemaResult? {
            guard let result = cache[key] else { return nil }

            // Update access order for LRU
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(key)

            return result
        }

        func set(_ key: SchemaKey, value: DatabaseSchemaResult) {
            // Remove if already exists to update access order
            if cache[key] != nil {
                if let index = accessOrder.firstIndex(of: key) {
                    accessOrder.remove(at: index)
                }
            }

            cache[key] = value
            accessOrder.append(key)

            // Enforce size limit with LRU eviction
            if cache.count > maxSize {
                let oldestKey = accessOrder.removeFirst()
                cache.removeValue(forKey: oldestKey)
            }
        }

        func remove(_ key: SchemaKey) {
            cache.removeValue(forKey: key)
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        func removeAll() {
            cache.removeAll()
            accessOrder.removeAll()
        }

        var count: Int {
            cache.count
        }
    }

    func getDatabaseMetadata() async throws -> [Database] {
        guard let uri = self.connectionUri else {
            throw DatabaseError.connectionFailed("No configuration available")
        }

        do {
            let databaseQuery = PostgresQuery("""
                SELECT
                    datname AS database_name,
                    pg_size_pretty(pg_database_size(datname)) AS database_size,
                    datallowconn AS allow_connections
                FROM pg_database
                WHERE datistemplate = false
            """)

            let results = try await poolQuery(databaseQuery)
            var databaseList: [(name: String, size: String, allowConn: Bool)] = []

            for try await (name, size, allowConn) in results.decode((String, String, Bool).self) {
                databaseList.append((name: name, size: size, allowConn: allowConn))
            }

            // Reuse a single event loop group and query the databases serially
            // instead of spawning a group + connection per database.
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            var databases: [Database] = []

            for dbInfo in databaseList {
                let tableCount = await getTableCountForDatabase(
                    name: dbInfo.name,
                    connectionUri: uri,
                    allowConnections: dbInfo.allowConn,
                    on: eventLoopGroup
                )

                databases.append(Database(
                    name: dbInfo.name,
                    size: dbInfo.size,
                    tableCount: tableCount
                ))
            }

            try? await eventLoopGroup.shutdownGracefully()

            return databases.sorted { $0.name < $1.name }
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to get database metadata: \(error.localizedDescription)")
        }
    }

    /// Returns the table count for a database, or nil if the count could not
    /// be determined, so genuine failures aren't reported as empty databases.
    private func getTableCountForDatabase(name: String, connectionUri: String, allowConnections: Bool, on eventLoopGroup: EventLoopGroup) async -> Int? {
        guard allowConnections else {
            return 0
        }

        var tempConnection: PostgresConnection?

        do {
            var tempConfig = try PostgreSQLConnectionStringParser.parseConfiguration(connectionUri)
            tempConfig.database = name

            tempConnection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: tempConfig,
                id: Int.random(in: 1000...9999),
                logger: Logger(label: "postgres-metadata"),
            )

            let countQuery = try await tempConnection!.query("""
                SELECT COUNT(*)::int as table_count
                FROM information_schema.tables
                WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
                AND table_type = 'BASE TABLE'
            """, logger: Logger(label: "postgres-metadata"))

            var tableCount = 0
            for try await (count) in countQuery.decode((Int32).self) {
                tableCount = Int(count)
                break
            }

            try await tempConnection!.close()
            return tableCount

        } catch {
            if let conn = tempConnection, !conn.isClosed {
                try? await conn.close()
            }
            debugLog("Warning: Could not get table count for database '\(name)': \(error.localizedDescription)")
            return nil
        }
    }

    // Cache for database schemas with performance optimizations
    private let databaseSchema = SchemaCache()

    // Cache for primary key columns, keyed by (schema, table). The stored
    // value is Optional so "table has no primary key" is cached too.
    // Invalidated alongside the schema cache.
    private var primaryKeyCache: [SchemaKey: String?] = [:]

    func getSchema(for tableName: String, in schemaName: String = "public", forceFetch: Bool = false) async throws -> DatabaseSchemaResult {
        let cacheKey = SchemaKey(schemaName, tableName)

        if !forceFetch, let cachedSchema = await databaseSchema.get(cacheKey) {
            return cachedSchema
        }

        if forceFetch {
            primaryKeyCache.removeValue(forKey: cacheKey)
        }

        do {
            // Combined query to get both column schema and constraint information in one query
            let combinedQuery = PostgresQuery("""
                SELECT
                    c.ordinal_position,
                    c.column_name,
                    c.udt_name AS data_type,
                    COALESCE(t.oid, 0)::bigint AS pg_type_oid,
                    t.typname AS pg_type_name,
                    t.typtype,
                    CASE
                        WHEN t.typtype = 'e' THEN 'enum'
                        WHEN t.typtype = 'c' THEN 'composite'
                        WHEN t.typtype = 'd' THEN 'domain'
                        WHEN c.data_type = 'ARRAY' THEN 'array'
                        ELSE 'base'
                    END AS type_category,
                    CASE
                        WHEN t.typtype = 'e' THEN (
                            SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
                            FROM pg_enum e
                            WHERE e.enumtypid = t.oid
                        )
                        ELSE NULL
                    END AS enum_values,
                    COALESCE(c.numeric_precision, 0) AS numeric_precision,
                    COALESCE(c.datetime_precision, 0) AS datetime_precision,
                    COALESCE(c.numeric_scale, 0) AS numeric_scale,
                    COALESCE(c.character_maximum_length, 0) AS data_length,
                    c.is_nullable,
                    '' AS check_col,
                    '' AS check_constraint,
                    COALESCE(c.column_default, '') AS column_default,
                    '' AS comment,
                    -- Foreign key constraint information
                    fk.constraint_name,
                    fk.parent_schema,
                    fk.parent_table,
                    fk.parent_column,
                    fk.on_update,
                    fk.on_delete
                FROM
                    information_schema.columns c
                LEFT JOIN pg_type t ON t.typname = c.udt_name
                LEFT JOIN (
                    SELECT DISTINCT
                        con.conname AS constraint_name,
                        att.attname AS child_column,
                        ref_ns.nspname AS parent_schema,
                        ref_cl.relname AS parent_table,
                        ref_att.attname AS parent_column,
                        CASE con.confupdtype
                            WHEN 'r' THEN 'restrict'
                            WHEN 'c' THEN 'cascade'
                            WHEN 'n' THEN 'set null'
                            WHEN 'd' THEN 'set default'
                            WHEN 'a' THEN 'no action'
                            ELSE NULL
                        END AS on_update,
                        CASE con.confdeltype
                            WHEN 'r' THEN 'restrict'
                            WHEN 'c' THEN 'cascade'
                            WHEN 'n' THEN 'set null'
                            WHEN 'd' THEN 'set default'
                            WHEN 'a' THEN 'no action'
                            ELSE NULL
                        END AS on_delete
                    FROM pg_constraint con
                    JOIN pg_class cl ON cl.oid = con.conrelid
                    JOIN pg_namespace ns ON ns.oid = cl.relnamespace
                    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
                    JOIN pg_class ref_cl ON ref_cl.oid = con.confrelid
                    JOIN pg_namespace ref_ns ON ref_ns.oid = ref_cl.relnamespace
                    JOIN pg_attribute ref_att ON ref_att.attrelid = con.confrelid AND ref_att.attnum = ANY(con.confkey)
                    WHERE con.contype = 'f'
                        AND cl.relname = \(unescaped: quoteStringLiteral(tableName))
                        AND ns.nspname = \(unescaped: quoteStringLiteral(schemaName))
                ) fk ON fk.child_column = c.column_name
                WHERE
                    c.table_name = \(unescaped: quoteStringLiteral(tableName))
                    AND c.table_schema = \(unescaped: quoteStringLiteral(schemaName))
                ORDER BY c.ordinal_position;
            """)

            let results = try await poolQuery(combinedQuery)
            var databaseSchemaInfo: [DatabaseSchemaInfo] = []

            for try await (ordinalPosition, columnName, dataType, pgTypeOid, _, _, _, enumValuesStr, numericPrecision, datetimePrecision, numericScale, dataLength, isNullable, check, checkConstraint, columnDefault, comment, constraintName, parentSchema, parentTable, parentColumn, onUpdate, onDelete) in results.decode((
                Int, String, String, Int64, String?, String?, String, String?, Int, Int, Int, Int, String, String, String, String, String, String?, String?, String?, String?, String?, String?).self) {

                // Build constraint info if foreign key data exists
                var columnConstraints: [ConstraintInfo] = []
                var foreignKey = ""

                if let constraintName = constraintName,
                   let parentSchema = parentSchema,
                   let parentTable = parentTable,
                   let parentColumn = parentColumn {

                    let constraintInfo = ConstraintInfo(
                        oid: 0,
                        name: constraintName,
                        type: .foreignKey,
                        columns: [columnName],
                        isDeferrable: false,
                        isDeferred: false,
                        definition: nil,
                        description: nil,
                        referencedSchema: parentSchema,
                        referencedTable: parentTable,
                        referencedColumns: [parentColumn],
                        onUpdate: onUpdate ?? "no action",
                        onDelete: onDelete ?? "no action",
                        extensionName: nil
                    )

                    columnConstraints.append(constraintInfo)
                    foreignKey = constraintName
                }

                let format = PostgresDataType(UInt32(pgTypeOid))
                let enumValues: [String]? = enumValuesStr?.split(separator: ",").map { String($0) }
                let schemaInfo = DatabaseSchemaInfo(
                    ordinalPosition: ordinalPosition,
                    columnName: columnName,
                    dataType: dataType,
                    formatType: format.description,
                    typeOid: Int(format.rawValue),
                    numericPrecision: numericPrecision,
                    datetimePrecision: datetimePrecision,
                    numericScale: numericScale,
                    dataLength: dataLength,
                    isNullable: isNullable,
                    check: check,
                    checkConstraint: checkConstraint,
                    columnDefault: columnDefault,
                    foreignKey: foreignKey,
                    constraints: columnConstraints,
                    comment: comment,
                    enumValues: enumValues
                )

                databaseSchemaInfo.append(schemaInfo)
            }

            let schemaResult = DatabaseSchemaResult(
                tableName: tableName,
                schemaName: schemaName,
                columns: databaseSchemaInfo,
                totalCount: databaseSchemaInfo.count
            )

            // Cache the result for future use
            await databaseSchema.set(cacheKey, value: schemaResult)

            return schemaResult
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to get schema: \(error.localizedDescription)")
        }
    }

    /// Clear the schema cache - useful when schema changes are expected
    func clearSchemaCache() async {
        await databaseSchema.removeAll()
        primaryKeyCache.removeAll()
    }

    /// Clear schema cache for a specific table
    func clearSchemaCache(for tableName: String, in schemaName: String = "public") async {
        let cacheKey = SchemaKey(schemaName, tableName)
        await databaseSchema.remove(cacheKey)
        primaryKeyCache.removeValue(forKey: cacheKey)
    }

    /// Clear schema cache for a specific table (protocol conformance)
    func clearSchemaCache(for tableName: String, schema: String?) async {
        let schemaName = schema ?? "public"
        let cacheKey = SchemaKey(schemaName, tableName)
        await databaseSchema.remove(cacheKey)
        primaryKeyCache.removeValue(forKey: cacheKey)
    }

    /// Get current cache statistics
    func getSchemaCacheStats() async -> (count: Int, maxSize: Int) {
        let count = await databaseSchema.count
        return (count: count, maxSize: 100)
    }

    func getIndexes(for tableName: String, schema: String?) async throws -> [DatabaseIndexInfo] {
        let schemaName = schema ?? "public"

        do {
            let query = PostgresQuery("""
                SELECT
                    ix.relname as index_name,
                    UPPER(am.amname) AS index_algorithm,
                    indisunique as is_unique,
                    indisprimary as is_primary,
                    pg_get_indexdef(indexrelid) as index_definition,
                    replace(
                        regexp_replace(
                            regexp_replace(
                                regexp_replace(pg_get_indexdef(indexrelid), ' WHERE .+|INCLUDE .+', ''),
                                ' WITH .+', ''
                            ),
                            '.*\\((.*)\\)', '\\1'
                        ),
                        ' ', ''
                    ) AS column_name,
                    CASE
                        WHEN position(' WHERE ' in pg_get_indexdef(indexrelid)) > 0
                        THEN regexp_replace(pg_get_indexdef(indexrelid), '.+WHERE ', '')
                        ELSE ''
                    END AS condition,
                    CASE
                        WHEN position(' INCLUDE ' in pg_get_indexdef(indexrelid)) > 0
                        THEN replace(
                            regexp_replace(
                                regexp_replace(pg_get_indexdef(indexrelid), '.+INCLUDE \\((.*)\\).*', '\\1'),
                                ' ', ''
                            ),
                            ' ', ''
                        )
                        ELSE ''
                    END AS include,
                    pg_catalog.obj_description(i.indexrelid, 'pg_class') as comment
                FROM pg_index i
                JOIN pg_class t ON t.oid = i.indrelid
                JOIN pg_class ix ON ix.oid = i.indexrelid
                JOIN pg_namespace n ON t.relnamespace = n.oid
                JOIN pg_am as am ON ix.relam = am.oid
                WHERE t.relname = \(tableName) AND n.nspname = \(schemaName)
                ORDER BY ix.relname;
            """)

            let results = try await poolQuery(query)
            var indexes: [DatabaseIndexInfo] = []

            for try await (indexName, idxAlgorithm, isUnique, isPrimary, definition, columnName, condition, include, comment) in results.decode(
                (String, String, Bool, Bool, String, String, String, String, String?).self
            ) {
                let indexType: IndexType
                switch idxAlgorithm.lowercased() {
                case "btree": indexType = .btree
                case "hash": indexType = .hash
                case "gin": indexType = .gin
                case "gist": indexType = .gist
                case "spgist": indexType = .spgist
                case "brin": indexType = .brin
                default: indexType = .other
                }

                // Parse columns from comma-separated string
                let columns = columnName.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

                // Parse include columns if present
                var includeColumns: [String]? = nil
                if !include.isEmpty {
                    includeColumns = include.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                }

                // Clean up condition
                let finalCondition = condition.isEmpty ? nil : condition

                let indexInfo = DatabaseIndexInfo(
                    name: indexName,
                    tableName: tableName,
                    schemaName: schemaName,
                    columns: columns,
                    indexType: indexType,
                    isUnique: isUnique,
                    isPrimaryKey: isPrimary,
                    definition: definition,
                    condition: finalCondition,
                    includeColumns: includeColumns,
                    comment: comment
                )
                indexes.append(indexInfo)
            }

            return indexes
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to get indexes: \(error.localizedDescription)")
        }
    }

    /// Quotes a SQL identifier, doubling any embedded double quotes.
    /// Internal (not private) so the filter builder extension can use it too.
    nonisolated func quoteIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Quotes a value as a SQL string literal, doubling any embedded single quotes.
    private nonisolated func quoteStringLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func validateAndSanitizeIdentifier(_ identifier: String, databaseSchema: String? = "public") throws -> String {
        // Remove whitespace and validate the identifier
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the identifier is empty
        if trimmed.isEmpty {
            throw DatabaseError.configurationError("Identifier cannot be empty")
        }

        // PostgreSQL identifier rules:
        // - Must start with a letter or underscore
        // - Can contain letters, digits, underscores, and dollar signs
        // - Maximum length is 63 characters

        if trimmed.count > 63 {
            throw DatabaseError.configurationError("Identifier too long (max 63 characters)")
        }

        // Check if it starts with letter or underscore
        guard let firstChar = trimmed.first,
              firstChar.isLetter || firstChar == "_" else {
            throw DatabaseError.configurationError("Identifier must start with letter or underscore")
        }

        // Check for valid characters
        let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))
        for char in trimmed.unicodeScalars {
            if !validCharacters.contains(char) {
                throw DatabaseError.configurationError("Identifier contains invalid characters")
            }
        }

        if let schema = databaseSchema {
            return "\"\(schema)\".\"\(trimmed)\""
        }
        // Return properly quoted identifier for PostgreSQL
        // Use double quotes to preserve case and handle reserved words
        return "\"\(trimmed)\""
    }

    private func buildWhereClause(from filter: DatabaseDocument) -> String {
        // Filter out the rawQuery key as it's not meant for WHERE clause building
        let filteredDict = filter.filter { key, _ in key != "rawQuery" }

        guard !filteredDict.isEmpty else { return "" }

        let conditions = filteredDict.map { key, value in
            let column = quoteIdentifier(key)
            switch value {
            case .string(let stringValue), .decimalString(let stringValue), .objectID(let stringValue):
                return "\(column) = '\(stringValue.replacing("'", with: "''"))'"
            case .int(let value):
                return "\(column) = \(value)"
            case .int64(let value):
                return "\(column) = \(value)"
            case .double(let value):
                return "\(column) = \(value)"
            case .bool(let value):
                return "\(column) = \(value)"
            case .null:
                return "\(column) IS NULL"
            default:
                return "\(column) = '\(value.description.replacing("'", with: "''"))'"
            }
        }

        return conditions.joined(separator: " AND ")
    }

    /// Wraps a filter query in a subselect so filtered browsing respects
    /// paging and sorting. Anything that isn't a single SELECT statement is
    /// returned untouched.
    private func pageFilterQuery(_ rawQuery: String, skip: Int, limit: Int, sortBy: String?, ascending: Bool?) -> String {
        var trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(";") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lowercased = trimmed.lowercased()
        guard splitSQLStatements(trimmed).count == 1,
              lowercased.hasPrefix("select") || lowercased.hasPrefix("with") else {
            return rawQuery
        }

        var sql = "SELECT * FROM (\(trimmed)) AS quarry_filtered"

        let orderByClause = buildOrderByClause(sortBy: sortBy, ascending: ascending, primaryKey: nil)
        if !orderByClause.isEmpty {
            sql += " \(orderByClause)"
        }

        sql += " LIMIT \(limit) OFFSET \(skip)"
        return sql
    }

    private func buildOrderByClause(sortBy: String?, ascending: Bool?, primaryKey: String?) -> String {
        // If sortBy is provided, use it
        if let sortBy = sortBy, !sortBy.isEmpty {
            // Validate column name to prevent SQL injection
            do {
                let sanitizedColumn = try validateAndSanitizeColumnName(sortBy)
                let direction = ascending == false ? "DESC" : "ASC"
                return "ORDER BY \(sanitizedColumn) \(direction)"
            } catch {
                // If column validation fails, fall back to primary key if it exists
                if let primaryKey = primaryKey {
                    return "ORDER BY \(primaryKey) ASC"
                }
                return ""
            }
        } else {
            // No sorting provided, use primary key ASC as default if it exists
            if let primaryKey = primaryKey {
                return "ORDER BY \(primaryKey) ASC"
            }
            return ""
        }
    }

    private func buildParameterizedSetClause(dataToUpdate: DatabaseDocument, for tableName: String, in schemaName: String = "public") async throws -> (String, [PostgresEncodable?]) {
        var setClauses: [String] = []
        var values: [PostgresEncodable?] = []
        var parameterIndex = 1

        // Get the schema to determine correct data types
        let schema = try await getSchema(for: tableName, in: schemaName)
        let columnTypes = Dictionary(uniqueKeysWithValues: schema.columns.map { ($0.columnName, $0.typeOid) })
        let columnTypeNames = Dictionary(uniqueKeysWithValues: schema.columns.map { ($0.columnName, $0.dataType) })

        for (columnName, value) in dataToUpdate {
            let columnTypeString = columnTypes[columnName] ?? 0
            let columnType = PostgresDataType(UInt32(columnTypeString))
            let columnTypeName = columnTypeNames[columnName]

            // Use the new buildSetClause function for proper type casting
            // For user-defined types (enums), pass the actual type name
            let enumTypeName = columnType.isUserDefined ? columnTypeName : nil
            let setClause = buildSetClause(for: columnName, parameterIndex: parameterIndex, columnType: columnType, enumTypeName: enumTypeName)
            setClauses.append(setClause)

            let convertedValue = try encode(value, columnName: columnName, columnType: columnType)
            values.append(convertedValue)

            parameterIndex += 1
        }

        return (setClauses.joined(separator: ", "), values)
    }

    private func validateAndSanitizeColumnName(_ columnName: String) throws -> String {
        let trimmed = columnName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the column name is empty
        if trimmed.isEmpty {
            throw DatabaseError.configurationError("Column name cannot be empty")
        }

        // PostgreSQL column name rules (similar to identifier rules)
        if trimmed.count > 63 {
            throw DatabaseError.configurationError("Column name too long (max 63 characters)")
        }

        // Check if it starts with letter or underscore
        guard let firstChar = trimmed.first,
              firstChar.isLetter || firstChar == "_" else {
            throw DatabaseError.configurationError("Column name must start with letter or underscore")
        }

        // Check for valid characters
        let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))
        for char in trimmed.unicodeScalars {
            if !validCharacters.contains(char) {
                throw DatabaseError.configurationError("Column name contains invalid characters")
            }
        }

        // Return properly quoted column name for PostgreSQL
        return "\"\(trimmed)\""
    }

    private func mapPSQLError(_ error: PSQLError, query: String? = nil) -> DatabaseError {
        // Check the specific error code first
        switch error.code {
        case .authMechanismRequiresPassword:
            return DatabaseError.authenticationFailed("Password required for authentication")
        case .unsupportedAuthMechanism:
            return DatabaseError.authenticationFailed("Unsupported authentication mechanism")
        case .saslError:
            return DatabaseError.authenticationFailed("SASL authentication failed")
        case .connectionError:
            return DatabaseError.connectionFailed("Cannot connect to PostgreSQL server")
        case .serverClosedConnection:
            return DatabaseError.connectionFailed("Server closed the connection")
        case .clientClosedConnection:
            return DatabaseError.connectionFailed("Client connection was closed")
        case .server:
            // For server errors, check the server info for more specific error details
            if let serverInfo = error.serverInfo {
                // Check SQL state for authentication errors
                if let sqlState = serverInfo[.sqlState] {
                    switch sqlState {
                    case "28000", "28P01": // Invalid authorization specification / Invalid password
                        return DatabaseError.authenticationFailed("Invalid username or password")
                    case "3D000": // Invalid catalog name (database does not exist)
                        return DatabaseError.databaseNotFound("Database does not exist")
                    case "42501": // Insufficient privilege
                        return DatabaseError.authenticationFailed("Insufficient database privileges")
                    default:
                        break
                    }
                }

                // Use the error message from the server
                if let message = serverInfo[.message] {
                    let position = serverInfo[.position].flatMap { Int($0) }
                    let hint = serverInfo[.hint]
                    let detail = serverInfo[.detail]

                    return DatabaseError(
                        code: .operationFailed,
                        message: message,
                        details: detail,
                        position: position,
                        hint: hint,
                        query: query
                    )
                }
            }
            return DatabaseError.operationFailed("PostgreSQL server error")
        default:
            // For debugging, you can use: String(reflecting: error) to see full error details
            return DatabaseError.operationFailed("PostgreSQL error: \(error.code)")
        }
    }

    private func extractVersionNumber(from fullVersion: String) -> String? {
        let pattern = #"PostgreSQL\s+(\d+(?:\.\d+)*)"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = fullVersion as NSString
            let results = regex.matches(in: fullVersion, options: [], range: NSRange(location: 0, length: nsString.length))

            if let match = results.first,
               match.numberOfRanges > 1 {
                let versionRange = match.range(at: 1)
                return nsString.substring(with: versionRange)
            }
        } catch {
            debugLog("Regex failed for version extraction: \(error)")
        }

        return nil
    }


    // MARK: - Helper methods for foreign keys
    private func getTableOid(schema: String, table: String) async throws -> Int64? {
        let query = PostgresQuery("""
            SELECT oid FROM pg_class
            WHERE relname = \(unescaped: quoteStringLiteral(table))
            AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = \(unescaped: quoteStringLiteral(schema)))
        """)

        let results = try await poolQuery(query)

        for try await (oid) in results.decode((Int64).self) {
            return oid
        }

        return nil
    }

    private func mapConstraintAction(_ action: String?) -> String {
        guard let action = action else { return "no action" }

        switch action {
        case "r": return "restrict"
        case "c": return "cascade"
        case "n": return "set null"
        case "d": return "set default"
        case "a": return "no action"
        default: return "no action"
        }
    }

    // MARK: - Helper method to get primary key column
    private func getPrimaryKeyColumn(for tableName: String, in schemaName: String = "public") async throws -> String? {
        let cacheKey = SchemaKey(schemaName, tableName)
        if let cached = primaryKeyCache[cacheKey] {
            return cached
        }

        do {
            // Avoid `::regclass` and `to_regclass($1)` entirely — both attempt
            // to *parse* the qualified name from a string, which breaks if
            // `tableName` already contains a schema prefix or special chars.
            // Joining pg_class + pg_namespace by name is parameter-safe and
            // can't be confused into thinking `public.public.address` is a
            // 3-part `database.schema.table` qualifier.
            let queryString = """
                   SELECT a.attname
                   FROM pg_index i
                   JOIN pg_class c ON c.oid = i.indrelid
                   JOIN pg_namespace n ON n.oid = c.relnamespace
                   JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                   WHERE c.relname = $1 AND n.nspname = $2 AND i.indisprimary
                   ORDER BY a.attnum
                   LIMIT 1
               """
            var bindings = PostgresBindings()
            bindings.append(tableName)
            bindings.append(schemaName)
            let parameterized = PostgresQuery(unsafeSQL: queryString, binds: bindings)

            let results = try await poolQuery(parameterized)

            for try await (columnName) in results.decode((String).self) {
                let quoted = quoteIdentifier(columnName)
                primaryKeyCache[cacheKey] = quoted
                return quoted
            }

            // If no primary key is found, cache and return nil
            primaryKeyCache.updateValue(nil, forKey: cacheKey)
            return nil

        } catch {
            // If the query fails for any reason (e.g., table not found, permissions),
            // return nil without caching so transient failures don't stick
            return nil
        }
    }

    // MARK: - Schema Modification Methods

    func addColumn(
        to tableName: String,
        schema: String?,
        column: DatabaseSchemaInfo
    ) async throws {
        let schemaName = schema ?? "public"

        // Build the ADD COLUMN SQL statement
        var sql = "ALTER TABLE \(try validateAndSanitizeIdentifier(tableName, databaseSchema: schemaName)) ADD COLUMN \"\(column.columnName)\" \(column.formatType)"

        // Add NOT NULL constraint if applicable
        if column.isNullable == "NO" {
            sql += " NOT NULL"
        }

        // Add DEFAULT value if specified and not empty
        if let defaultValue = column.columnDefault, !defaultValue.trimmingCharacters(in: .whitespaces).isEmpty {
            sql += " DEFAULT \(defaultValue)"
        }

        do {
            _ = try await poolQuery(PostgresQuery(stringLiteral: sql))
            debugLog("✓ Added column \(column.columnName) to table \(tableName)")
        } catch let error as PSQLError {
            throw mapPSQLError(error, query: sql)
        } catch {
            throw DatabaseError.operationFailed("Failed to add column: \(error.localizedDescription)", query: sql)
        }
    }

    func modifyColumn(
        in tableName: String,
        schema: String?,
        columnName: String,
        newColumn: DatabaseSchemaInfo
    ) async throws {
        let schemaName = schema ?? "public"
        let qualifiedTableName = try validateAndSanitizeIdentifier(tableName, databaseSchema: schemaName)

        do {
            // PostgreSQL requires separate ALTER COLUMN statements for different modifications

            // Track the current column name (may change after rename)
            var currentColumnName = columnName

            // 0. Rename column if name changed (must be done first)
            if newColumn.columnName != columnName {
                let renameSQL = "ALTER TABLE \(qualifiedTableName) RENAME COLUMN \"\(columnName)\" TO \"\(newColumn.columnName)\""
                _ = try await poolQuery(PostgresQuery(stringLiteral: renameSQL))
                currentColumnName = newColumn.columnName
                debugLog("✓ Renamed column \(columnName) to \(newColumn.columnName) in table \(tableName)")
            }

            // 1. Change data type if different
            let changeTypeSQL = "ALTER TABLE \(qualifiedTableName) ALTER COLUMN \"\(currentColumnName)\" TYPE \(newColumn.dataType)"
            _ = try await poolQuery(PostgresQuery(stringLiteral: changeTypeSQL))

            // 2. Set or drop NOT NULL constraint
            if newColumn.isNullable == "NO" {
                let setNotNullSQL = "ALTER TABLE \(qualifiedTableName) ALTER COLUMN \"\(currentColumnName)\" SET NOT NULL"
                _ = try await poolQuery(PostgresQuery(stringLiteral: setNotNullSQL))
            } else {
                let dropNotNullSQL = "ALTER TABLE \(qualifiedTableName) ALTER COLUMN \"\(currentColumnName)\" DROP NOT NULL"
                _ = try await poolQuery(PostgresQuery(stringLiteral: dropNotNullSQL))
            }

            // 3. Set or drop DEFAULT value
            if let defaultValue = newColumn.columnDefault, !defaultValue.trimmingCharacters(in: .whitespaces).isEmpty {
                let setDefaultSQL = "ALTER TABLE \(qualifiedTableName) ALTER COLUMN \"\(currentColumnName)\" SET DEFAULT \(defaultValue)"
                _ = try await poolQuery(PostgresQuery(stringLiteral: setDefaultSQL))
            } else {
                let dropDefaultSQL = "ALTER TABLE \(qualifiedTableName) ALTER COLUMN \"\(currentColumnName)\" DROP DEFAULT"
                _ = try await poolQuery(PostgresQuery(stringLiteral: dropDefaultSQL))
            }

            debugLog("✓ Modified column \(currentColumnName) in table \(tableName)")
        } catch let error as PSQLError {
            throw mapPSQLError(error)
        } catch {
            throw DatabaseError.operationFailed("Failed to modify column: \(error.localizedDescription)")
        }
    }

    func dropColumn(
        from tableName: String,
        schema: String?,
        columnName: String
    ) async throws {
        let schemaName = schema ?? "public"

        let sql = "ALTER TABLE \(try validateAndSanitizeIdentifier(tableName, databaseSchema: schemaName)) DROP COLUMN \"\(columnName)\""

        do {
            _ = try await poolQuery(PostgresQuery(stringLiteral: sql))
            debugLog("✓ Dropped column \(columnName) from table \(tableName)")
        } catch let error as PSQLError {
            throw mapPSQLError(error, query: sql)
        } catch {
            throw DatabaseError.operationFailed("Failed to drop column: \(error.localizedDescription)", query: sql)
        }
    }

    func createIndex(
        on tableName: String,
        schema: String?,
        index: DatabaseIndexInfo
    ) async throws {
        let schemaName = schema ?? "public"

        // Build CREATE INDEX statement
        var sql = "CREATE"

        if index.isUnique {
            sql += " UNIQUE"
        }

        sql += " INDEX \"\(index.name)\" ON \(try validateAndSanitizeIdentifier(tableName, databaseSchema: schemaName))"

        // Add index type/method
        let indexMethod = index.indexType.rawValue.uppercased()
        sql += " USING \(indexMethod)"

        // Add columns
        let columnList = index.columns.map { "\"\($0)\"" }.joined(separator: ", ")
        sql += " (\(columnList))"

        // Add INCLUDE columns if present
        if let includeColumns = index.includeColumns, !includeColumns.isEmpty {
            let includeList = includeColumns.map { "\"\($0)\"" }.joined(separator: ", ")
            sql += " INCLUDE (\(includeList))"
        }

        // Add WHERE condition if present
        if let condition = index.condition, !condition.isEmpty {
            sql += " WHERE \(condition)"
        }

        do {
            _ = try await poolQuery(PostgresQuery(stringLiteral: sql))
            debugLog("✓ Created index \(index.name) on table \(tableName)")
        } catch let error as PSQLError {
            throw mapPSQLError(error, query: sql)
        } catch {
            throw DatabaseError.operationFailed("Failed to create index: \(error.localizedDescription)", query: sql)
        }
    }

    func dropIndex(
        indexName: String,
        tableName: String,
        schema: String?
    ) async throws {
        let schemaName = schema ?? "public"

        let sql = "DROP INDEX IF EXISTS \"\(schemaName)\".\"\(indexName)\""

        do {
            _ = try await poolQuery(PostgresQuery(stringLiteral: sql))
            debugLog("✓ Dropped index \(indexName)")
        } catch let error as PSQLError {
            throw mapPSQLError(error, query: sql)
        } catch {
            throw DatabaseError.operationFailed("Failed to drop index: \(error.localizedDescription)", query: sql)
        }
    }

    // MARK: - Database Management

    func createDatabase(named databaseName: String, options: CreateDatabaseOptions) async throws {
        let sanitizedName = databaseName.replacing("\"", with: "\"\"")
        var sql = "CREATE DATABASE \"\(sanitizedName)\""

        if let encoding = options.encoding, !encoding.isEmpty {
            sql += " ENCODING '\(encoding)'"
        }

        do {
            _ = try await poolQuery(PostgresQuery(stringLiteral: sql))
            debugLog("✓ Created database \(databaseName)")
        } catch let error as PSQLError {
            throw mapPSQLError(error, query: sql)
        } catch {
            throw DatabaseError.operationFailed("Failed to create database: \(error.localizedDescription)", query: sql)
        }
    }

    func createSchema(named schemaName: String, options: CreateSchemaOptions) async throws {
        let sanitizedName = schemaName.replacing("\"", with: "\"\"")
        let sql = "CREATE SCHEMA \"\(sanitizedName)\""

        do {
            _ = try await poolQuery(PostgresQuery(stringLiteral: sql))
            debugLog("✓ Created schema \(schemaName)")
        } catch let error as PSQLError {
            throw mapPSQLError(error, query: sql)
        } catch {
            throw DatabaseError.operationFailed("Failed to create schema: \(error.localizedDescription)", query: sql)
        }
    }
}

// MARK: - Database Error
struct DatabaseError: Error, LocalizedError {
    enum Code: String, CaseIterable {
        case notImplemented = "NOT_IMPLEMENTED"
        case connectionFailed = "CONNECTION_FAILED"
        case operationFailed = "OPERATION_FAILED"
        case authenticationFailed = "AUTHENTICATION_FAILED"
        case configurationError = "CONFIGURATION_ERROR"
        case databaseNotFound = "DATABASE_NOT_FOUND"
        case databaseNotSelected = "DATABASE_NOT_SELECTED"
        case notConnected = "NOT_CONNECTED"
        case invalidConnectionString = "INVALID_CONNECTION_STRING"
        case noDatabaseSelected = "NO_DATABASE_SELECTED"
    }

    let code: Code
    let message: String
    let details: String?
    let position: Int?
    let hint: String?
    let query: String?
    let underlyingError: Error?

    init(
        code: Code,
        message: String,
        details: String? = nil,
        position: Int? = nil,
        hint: String? = nil,
        query: String? = nil,
        underlyingError: Error? = nil
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.position = position
        self.hint = hint
        self.query = query
        self.underlyingError = underlyingError
    }

    var errorDescription: String? {
        switch code {
        case .authenticationFailed:
            return "Authentication failed: \(message)"
        case .databaseNotFound:
            return "Database: \(message)"
        case .databaseNotSelected:
            return "Database not selected"
        case .notConnected:
            return "Not connected: \(message)"
        case .invalidConnectionString:
            return "Invalid connection string: \(message)"
        case .noDatabaseSelected:
            return "No database selected: \(message)"
        default:
            return message
        }
    }

    var errorDetails: String? {
        return details
    }

    // MARK: - Static convenience methods for backward compatibility
    static func notImplemented(_ message: String, details: String? = nil, position: Int? = nil) -> DatabaseError {
        return DatabaseError(code: .notImplemented, message: message, details: details, position: position)
    }

    static func connectionFailed(_ message: String, details: String? = nil, position: Int? = nil) -> DatabaseError {
        return DatabaseError(code: .connectionFailed, message: message, details: details, position: position)
    }

    static func operationFailed(_ message: String, details: String? = nil, position: Int? = nil, hint: String? = nil, query: String? = nil) -> DatabaseError {
        return DatabaseError(code: .operationFailed, message: message, details: details, position: position, hint: hint, query: query)
    }

    static func authenticationFailed(_ message: String, details: String? = nil, position: Int? = nil) -> DatabaseError {
        return DatabaseError(code: .authenticationFailed, message: message, details: details, position: position)
    }

    static func configurationError(_ message: String, details: String? = nil, position: Int? = nil) -> DatabaseError {
        return DatabaseError(code: .configurationError, message: message, details: details, position: position)
    }

    static func databaseNotFound(_ message: String, details: String? = nil, position: Int? = nil) -> DatabaseError {
        return DatabaseError(code: .databaseNotFound, message: message, details: details, position: position)
    }

    static let databaseNotSelected = DatabaseError(code: .databaseNotSelected, message: "Database not selected")

    static func notConnected(_ message: String, details: String? = nil, position: Int? = nil) -> DatabaseError {
        return DatabaseError(code: .notConnected, message: message, details: details, position: position)
    }

    static func invalidConnectionString(_ message: String, details: String? = nil, position: Int? = nil) -> DatabaseError {
        return DatabaseError(code: .invalidConnectionString, message: message, details: details, position: position)
    }

    static func noDatabaseSelected(_ message: String, details: String? = nil, position: Int? = nil) -> DatabaseError {
        return DatabaseError(code: .noDatabaseSelected, message: message, details: details, position: position)
    }
}
