import Foundation

// MARK: - Redis Wrappers

struct RedisDatabaseWrapper: DatabaseWrapper {
    let name: String
    let size: String?
    let tableCount: Int?
}

struct RedisCollectionWrapper: CollectionWrapper {
    var schema: String?
    var id: ObjectIdentifier
    let name: String
    let type: String
}

// MARK: - Redis Driver

/// Key-value browsing driver. The keyspace is exposed as a single "Keys"
/// collection whose rows are (key, type, ttl, value); raw queries run
/// arbitrary Redis commands, one per line.
actor RedisDriver: DatabaseDriver {
    typealias Database = RedisDatabaseWrapper
    typealias Collection = RedisCollectionWrapper

    static let keysCollectionName = "Keys"
    /// Elements shown for list/set/zset/hash values in the browser
    private static let valuePreviewElements = 50
    /// Upper bound on keys walked per SCAN-based listing
    private static let maxScannedKeys = 10_000

    private var client: RedisClient?
    private var endpoint: RedisClient.Endpoint?
    private var connectionUri: String?
    private var currentDatabaseIndex = 0

    // MARK: - Connection

    func connect(to connectionUri: String) async throws -> RedisDatabaseWrapper {
        let endpoint = try Self.parseConnectionString(connectionUri)
        self.connectionUri = connectionUri
        self.endpoint = endpoint
        self.currentDatabaseIndex = endpoint.database

        let client = RedisClient(endpoint: endpoint)
        try await client.connect()
        self.client = client

        let keyCount = (try? await client.command(["DBSIZE"]).intValue) ?? nil
        return RedisDatabaseWrapper(
            name: "db\(endpoint.database)",
            size: nil,
            tableCount: keyCount.map { _ in 1 }
        )
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
    }

    func reconnect() async throws {
        guard let connectionUri else {
            throw DatabaseError.notConnected("No previous Redis connection to restore")
        }
        _ = try await connect(to: connectionUri)
        if currentDatabaseIndex != endpoint?.database {
            try await ensureClient().command(["SELECT", String(currentDatabaseIndex)])
        }
    }

    func ping(to connectionUri: String) async throws {
        let endpoint = try Self.parseConnectionString(connectionUri)
        let client = RedisClient(endpoint: endpoint)
        try await client.connect()
        try await client.command(["PING"])
        await client.disconnect()
    }

    func getBuildInfo() async throws -> BuildInfo {
        let info = try await infoSection("server")
        let version = info["redis_version"] ?? "unknown"
        return BuildInfo(version: version, databaseType: .redis)
    }

    func switchDatabase(to databaseName: String) async throws {
        let index = Self.databaseIndex(from: databaseName)
        try await ensureClient().command(["SELECT", String(index)])
        currentDatabaseIndex = index
    }

    // MARK: - Databases

    func listDatabases() async throws -> [RedisDatabaseWrapper] {
        let client = try ensureClient()

        var databaseCount = 16
        if let reply = try? await client.command(["CONFIG", "GET", "databases"]),
           let values = reply.arrayValue, values.count == 2,
           let parsed = values[1].stringValue.flatMap({ Int($0) }) {
            databaseCount = parsed
        }

        var keyCounts: [Int: Int] = [:]
        if let keyspace = try? await infoSection("keyspace") {
            for (key, value) in keyspace where key.hasPrefix("db") {
                guard let index = Int(key.dropFirst(2)) else { continue }
                // Format: keys=123,expires=4,avg_ttl=0
                let keysField = value.split(separator: ",").first { $0.hasPrefix("keys=") }
                keyCounts[index] = keysField.flatMap { Int($0.dropFirst(5)) } ?? 0
            }
        }

        return (0..<databaseCount).map { index in
            RedisDatabaseWrapper(
                name: "db\(index)",
                size: keyCounts[index].map { "\($0) keys" },
                tableCount: 1
            )
        }
    }

    func getDatabaseMetadata() async throws -> [RedisDatabaseWrapper] {
        try await listDatabases()
    }

    func listCollections(schema: String?) async throws -> [RedisCollectionWrapper] {
        [RedisCollectionWrapper(
            schema: nil,
            id: ObjectIdentifier(NSString(string: Self.keysCollectionName)),
            name: Self.keysCollectionName,
            type: "keys"
        )]
    }

    // MARK: - Key Browsing

    func getDocumentCount(for collectionName: String, filter: DatabaseDocument) async throws -> Int {
        let client = try ensureClient()
        if let pattern = Self.matchPattern(from: filter) {
            return try await scanKeys(matching: pattern, limit: Self.maxScannedKeys).count
        }
        return Int(try await client.command(["DBSIZE"]).intValue ?? 0)
    }

    func findDocuments(in collectionName: String, filter: DatabaseDocument) async throws -> [QueryResult] {
        [try await findDocuments(in: collectionName, filter: filter, skip: 0, limit: 100)]
    }

    func findDocuments(in collectionName: String, filter: DatabaseDocument, skip: Int, limit: Int) async throws -> QueryResult {
        try await findDocuments(in: collectionName, databaseSchema: nil, filter: filter, skip: skip, limit: limit, sortBy: nil, ascending: nil)
    }

    func findDocuments(in collectionName: String, databaseSchema: String?, filter: DatabaseDocument, skip: Int, limit: Int, sortBy: String?, ascending: Bool?) async throws -> QueryResult {
        let pattern = Self.matchPattern(from: filter) ?? "*"
        var keys = try await scanKeys(matching: pattern, limit: min(skip + limit, Self.maxScannedKeys))
        keys.sort()
        if let sortBy, sortBy == "key", ascending == false {
            keys.reverse()
        }

        let page = Array(keys.dropFirst(skip).prefix(limit))
        let rows = try await buildKeyRows(for: page)

        return QueryResult(
            columns: Self.keyColumns,
            rows: rows.map(\.row),
            totalCount: rows.count,
            rawRows: rows.map(\.rawRow)
        )
    }

    private func scanKeys(matching pattern: String, limit: Int) async throws -> [String] {
        let client = try ensureClient()
        var keys: [String] = []
        var cursor = "0"
        repeat {
            let reply = try await client.command(["SCAN", cursor, "MATCH", pattern, "COUNT", "500"])
            guard let parts = reply.arrayValue, parts.count == 2,
                  let nextCursor = parts[0].stringValue,
                  let batch = parts[1].arrayValue else {
                throw DatabaseError.operationFailed("Unexpected SCAN reply from Redis")
            }
            keys.append(contentsOf: batch.compactMap(\.stringValue))
            cursor = nextCursor
        } while cursor != "0" && keys.count < limit
        return keys
    }

    private func buildKeyRows(for keys: [String]) async throws -> [(row: [String: QueryRowInfo], rawRow: DatabaseRawRow)] {
        guard !keys.isEmpty else { return [] }
        let client = try ensureClient()

        var commands: [[String]] = []
        for key in keys {
            commands.append(["TYPE", key])
            commands.append(["TTL", key])
        }
        let metadata = try await client.pipeline(commands)

        var results: [(row: [String: QueryRowInfo], rawRow: DatabaseRawRow)] = []
        for (index, key) in keys.enumerated() {
            let type = metadata[index * 2].stringValue ?? "unknown"
            let ttl = metadata[index * 2 + 1].intValue ?? -1
            let value = try await valuePreview(for: key, type: type)

            let row: [String: QueryRowInfo] = [
                "key": QueryRowInfo(value: DatabaseValue.string(key), dataType: "text", format: nil),
                "type": QueryRowInfo(value: DatabaseValue.string(type), dataType: "text", format: nil),
                "ttl": QueryRowInfo(value: DatabaseValue.int64(ttl), dataType: "integer", format: nil),
                "value": QueryRowInfo(value: DatabaseValue.string(value), dataType: "text", format: nil),
            ]
            let rawRow: DatabaseRawRow = [
                "key": .string(key),
                "type": .string(type),
                "ttl": .int64(ttl),
                "value": .string(value),
            ]
            results.append((row, rawRow))
        }
        return results
    }

    private func valuePreview(for key: String, type: String) async throws -> String {
        let client = try ensureClient()
        let count = String(Self.valuePreviewElements)

        switch type {
        case "string":
            return try await client.command(["GET", key]).stringValue ?? ""
        case "list":
            let values = try await client.command(["LRANGE", key, "0", String(Self.valuePreviewElements - 1)])
            return Self.formatElements(values.arrayValue?.compactMap(\.stringValue) ?? [])
        case "set":
            let reply = try await client.command(["SSCAN", key, "0", "COUNT", count])
            let values = reply.arrayValue?.last?.arrayValue?.compactMap(\.stringValue) ?? []
            return Self.formatElements(values)
        case "zset":
            let reply = try await client.command(["ZRANGE", key, "0", String(Self.valuePreviewElements - 1), "WITHSCORES"])
            let flat = reply.arrayValue?.compactMap(\.stringValue) ?? []
            let pairs = stride(from: 0, to: flat.count - 1, by: 2).map { "\(flat[$0]): \(flat[$0 + 1])" }
            return Self.formatElements(pairs)
        case "hash":
            let reply = try await client.command(["HSCAN", key, "0", "COUNT", count])
            let flat = reply.arrayValue?.last?.arrayValue?.compactMap(\.stringValue) ?? []
            let pairs = stride(from: 0, to: flat.count - 1, by: 2).map { "\(flat[$0]): \(flat[$0 + 1])" }
            return "{\(pairs.joined(separator: ", "))}"
        case "stream":
            let length = try await client.command(["XLEN", key]).intValue ?? 0
            return "stream (\(length) entries)"
        default:
            return ""
        }
    }

    private static func formatElements(_ elements: [String]) -> String {
        "[\(elements.joined(separator: ", "))]"
    }

    // MARK: - Mutations

    func createDocument(in collectionName: String, databaseSchema: String?, document: DatabaseDocument) async throws {
        guard let key = document["key"]?.stringValue, !key.isEmpty else {
            throw DatabaseError.operationFailed("A key name is required")
        }
        let value = document["value"]?.stringValue ?? ""
        try await ensureClient().command(["SET", key, value])
    }

    func updateDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID, data: DatabaseDocument) async throws {
        guard let key = id.value.stringValue else {
            throw DatabaseError.operationFailed("Missing key for update")
        }
        let client = try ensureClient()

        if let newKey = data["key"]?.stringValue, newKey != key {
            try await client.command(["RENAME", key, newKey])
            try await applyUpdates(to: newKey, data: data, client: client)
            return
        }
        try await applyUpdates(to: key, data: data, client: client)
    }

    private func applyUpdates(to key: String, data: DatabaseDocument, client: RedisClient) async throws {
        if let value = data["value"]?.stringValue {
            let type = try await client.command(["TYPE", key]).stringValue ?? "string"
            guard type == "string" || type == "none" else {
                throw DatabaseError.notImplemented("Editing \(type) values is not supported yet — use a raw command instead")
            }
            try await client.command(["SET", key, value])
        }
        if let ttl = data["ttl"]?.int64Value {
            if ttl < 0 {
                try await client.command(["PERSIST", key])
            } else {
                try await client.command(["EXPIRE", key, String(ttl)])
            }
        }
    }

    func deleteDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID) async throws {
        guard let key = id.value.stringValue else {
            throw DatabaseError.operationFailed("Missing key for delete")
        }
        try await ensureClient().command(["DEL", key])
    }

    // MARK: - Raw Commands

    @discardableResult
    func executeRawQuery(_ query: String, databaseSchema: String?) async throws -> [QueryResult] {
        let client = try ensureClient()
        let commands = query
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
            .map(Self.tokenize)

        guard !commands.isEmpty else { return [] }

        var results: [QueryResult] = []
        for arguments in commands {
            let reply = try await client.send(arguments)
            if case .error(let message) = reply {
                throw DatabaseError.operationFailed(message, query: arguments.joined(separator: " "))
            }
            results.append(Self.queryResult(from: reply))
        }
        return results
    }

    /// Splits a command line into arguments, honoring single/double quotes.
    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for character in line {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func queryResult(from reply: RedisValue) -> QueryResult {
        let column = QueryColumnInfo(name: "result", dataType: "text", format: nil, index: 0)

        func rows(for values: [String]) -> QueryResult {
            let queryRows = values.map { value in
                ["result": QueryRowInfo(value: DatabaseValue.string(value), dataType: "text", format: nil)]
            }
            let rawRows: [DatabaseRawRow] = values.map { ["result": .string($0)] }
            return QueryResult(columns: [column], rows: queryRows, totalCount: values.count, rawRows: rawRows)
        }

        switch reply {
        case .array(let values):
            return rows(for: (values ?? []).map { $0.stringValue ?? "(nil)" })
        case .bulkString(nil):
            return rows(for: ["(nil)"])
        default:
            return rows(for: [reply.stringValue ?? "(nil)"])
        }
    }

    // MARK: - Schema

    private static let keyColumns: [QueryColumnInfo] = [
        QueryColumnInfo(name: "key", dataType: "text", format: nil, index: 0),
        QueryColumnInfo(name: "type", dataType: "text", format: nil, index: 1),
        QueryColumnInfo(name: "ttl", dataType: "integer", format: nil, index: 2),
        QueryColumnInfo(name: "value", dataType: "text", format: nil, index: 3),
    ]

    func getSchema(for collectionName: String, schema: String?) async throws -> DatabaseSchemaResult? {
        let columns = [
            DatabaseSchemaInfo(
                ordinalPosition: 1,
                columnName: "key",
                dataType: "text",
                formatType: "text",
                typeOid: 0,
                isNullable: "NO",
                constraints: [ConstraintInfo(name: "key_pkey", type: .primaryKey, columns: ["key"])]
            ),
            DatabaseSchemaInfo(ordinalPosition: 2, columnName: "type", dataType: "text", formatType: "text", typeOid: 0, isReadOnly: true),
            DatabaseSchemaInfo(ordinalPosition: 3, columnName: "ttl", dataType: "integer", formatType: "integer", typeOid: 0),
            DatabaseSchemaInfo(ordinalPosition: 4, columnName: "value", dataType: "text", formatType: "text", typeOid: 0),
        ]
        return DatabaseSchemaResult(
            tableName: collectionName,
            schemaName: "db\(currentDatabaseIndex)",
            columns: columns,
            totalCount: columns.count
        )
    }

    func getInformationSchema() async throws -> [InformationSchema] {
        []
    }

    func getIndexes(for collectionName: String, schema: String?) async throws -> [DatabaseIndexInfo] {
        []
    }

    // MARK: - Collection Management (not applicable to Redis)

    func createCollection(named collectionName: String) async throws {
        throw DatabaseError.notImplemented("Redis has a single keyspace per database — create keys instead")
    }

    func renameCollection(databaseSchema: String?, from oldName: String, to newName: String) async throws {
        throw DatabaseError.notImplemented("Redis has a single keyspace per database")
    }

    func deleteCollection(named collectionName: String, databaseSchema: String?) async throws {
        throw DatabaseError.notImplemented("Redis has a single keyspace per database — delete keys instead")
    }

    // MARK: - AI

    func buildSystemPrompt(for collectionName: String, databaseSchema: String?) async throws -> String {
        let version = (try? await getBuildInfo().version) ?? "unknown"
        return """
        You are assisting with a Redis database (server version \(version), database db\(currentDatabaseIndex)).
        Queries are raw Redis commands, one per line (e.g. GET key, SCAN 0 MATCH user:* COUNT 100, HGETALL key).
        Only suggest commands valid for Redis. Prefer SCAN over KEYS for key listing.
        """
    }

    func buildAICommandPromptSystemPrompt(_ message: String) async throws -> String {
        """
        You translate natural language into Redis commands. Reply with the command(s) only, one per line, no explanation.
        Request: \(message)
        """
    }

    // MARK: - Helpers

    private func ensureClient() throws -> RedisClient {
        guard let client else {
            throw DatabaseError.notConnected("Not connected to Redis")
        }
        return client
    }

    private func infoSection(_ section: String) async throws -> [String: String] {
        let reply = try await ensureClient().command(["INFO", section])
        guard let text = reply.stringValue else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                values[String(parts[0])] = String(parts[1])
            }
        }
        return values
    }

    private static func matchPattern(from filter: DatabaseDocument) -> String? {
        if let raw = filter["rawQuery"]?.stringValue, !raw.isEmpty {
            return raw
        }
        if let key = filter["key"]?.stringValue, !key.isEmpty {
            return key.contains("*") ? key : "*\(key)*"
        }
        return nil
    }

    private static func databaseIndex(from name: String) -> Int {
        if name.hasPrefix("db"), let index = Int(name.dropFirst(2)) {
            return index
        }
        return Int(name) ?? 0
    }

    static func parseConnectionString(_ connectionUri: String) throws -> RedisClient.Endpoint {
        guard let components = URLComponents(string: connectionUri),
              let scheme = components.scheme?.lowercased(),
              scheme == "redis" || scheme == "rediss" else {
            throw DatabaseError.invalidConnectionString("Expected a redis:// or rediss:// URI")
        }
        guard let host = components.host, !host.isEmpty else {
            throw DatabaseError.invalidConnectionString("Missing Redis host")
        }

        var database = 0
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty {
            guard let index = Int(path) else {
                throw DatabaseError.invalidConnectionString("Redis database must be a number, got \"\(path)\"")
            }
            database = index
        }

        return RedisClient.Endpoint(
            host: host,
            port: components.port ?? 6379,
            username: components.user?.removingPercentEncoding,
            password: components.password?.removingPercentEncoding,
            database: database,
            useTLS: scheme == "rediss"
        )
    }
}
