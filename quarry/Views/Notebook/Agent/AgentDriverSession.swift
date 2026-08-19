import Foundation

actor AgentDriverSession {
    private var driver: (any DatabaseDriver)?
    private var connectedKeychainId: String?
    private var connectedDatabaseName: String?

    func connect(databaseType: DatabaseType, uri: String, keychainId: String, databaseName: String) async throws {
        // A SQLite connection is a single file — its "database name" is just
        // the file's display name. Switching to it would tear down the
        // connection (dropping security-scoped file access) and try to reopen
        // the bare name as a path, silently leaving the driver disconnected.
        let effectiveDatabaseName = databaseType == .sqlite ? "" : databaseName

        let cacheKey = "\(keychainId)|\(effectiveDatabaseName)"
        let currentKey = connectedKeychainId.map { "\($0)|\(connectedDatabaseName ?? "")" }
        if cacheKey == currentKey { return }

        let newDriver = DatabaseDriverFactory.createDriver(for: databaseType)
        _ = try await newDriver.connect(to: uri)
        if !effectiveDatabaseName.isEmpty {
            try? await newDriver.switchDatabase(to: effectiveDatabaseName)
        }

        await driver?.disconnect()
        driver = newDriver
        connectedKeychainId = keychainId
        connectedDatabaseName = effectiveDatabaseName
    }

    func listCollections(schema: String?) async throws -> [any CollectionWrapper] {
        guard let driver else { throw AgentSessionError.notConnected }
        return try await driver.listCollections(schema: schema)
    }

    func getSchema(tableName: String, schema: String?) async throws -> DatabaseSchemaResult? {
        guard let driver else { throw AgentSessionError.notConnected }
        return try await driver.getSchema(for: tableName, schema: schema)
    }

    func getInformationSchema() async throws -> [InformationSchema] {
        guard let driver else { throw AgentSessionError.notConnected }
        return try await driver.getInformationSchema()
    }

    func listDatabases() async throws -> [any DatabaseWrapper] {
        guard let driver else { throw AgentSessionError.notConnected }
        return try await driver.listDatabases()
    }

    func executeRawQuery(_ query: String, schema: String?) async throws -> [QueryResult] {
        guard let driver else { throw AgentSessionError.notConnected }
        return try await driver.executeRawQuery(query, databaseSchema: schema)
    }

    func disconnect() async {
        await driver?.disconnect()
        driver = nil
        connectedKeychainId = nil
        connectedDatabaseName = nil
    }
}

enum AgentSessionError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected: "Agent not connected to database"
        }
    }
}
