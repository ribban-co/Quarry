import Foundation

@Observable
@MainActor
final class QueryBlockViewModel {
    let block: NotebookBlock
    private weak var dataController: NotebookDataController?

    let session = ChartDriverSession()

    var config: QueryBlockConfig?

    // Query state
    var queryResult: QueryResult?
    var isExecutingQuery = false
    var queryError: String?
    var executionTime: TimeInterval?

    // Connection state
    var isConnecting = false
    var connectionError: String?

    private(set) var hasStartedLoading = false

    init(block: NotebookBlock, dataController: NotebookDataController) {
        self.block = block
        self.dataController = dataController
        self.config = block.queryBlockConfig()
    }

    func loadDataIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true

        if dataController?.isDashboardPublished == true,
           let cached = block.cachedQueryData() {
            queryResult = cached.toQueryResult()
            return
        }

        guard let cfg = config, !cfg.connectionKeychainId.isEmpty else { return }
        Task {
            await reconnectAndLoad(cfg)
        }
    }

    // MARK: - Connection

    private func resolveConnectionUri(_ cfg: QueryBlockConfig) -> String? {
        dataController?.connections.first(where: { $0.keychainId == cfg.connectionKeychainId })?.connectionUri
    }

    func reconnectAndRefresh() async {
        guard let cfg = config, !cfg.connectionKeychainId.isEmpty else { return }
        await reconnectAndLoad(cfg)
    }

    private func reconnectAndLoad(_ cfg: QueryBlockConfig) async {
        guard let dbType = DatabaseType(rawValue: cfg.databaseType),
              let uri = resolveConnectionUri(cfg) else { return }
        do {
            try await session.connect(databaseType: dbType, uri: uri)
            if !cfg.databaseName.isEmpty {
                try? await session.switchDatabase(to: cfg.databaseName)
            }

            if !cfg.queryText.isEmpty {
                await executeQuery()
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func connectToSource(_ connection: Connection) async {
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        guard let dbType = DatabaseType(rawValue: connection.databaseType.rawValue) else {
            connectionError = "Unsupported database type"
            return
        }

        let uri = connection.connectionUri
        let databaseName = connection.defaultDatabase ?? ""

        let draft = QueryBlockConfig(
            connectionKeychainId: connection.keychainId,
            connectionName: connection.name,
            databaseType: connection.databaseType.rawValue,
            databaseName: databaseName
        )

        do {
            try await session.connect(databaseType: dbType, uri: uri)
            if !databaseName.isEmpty {
                try? await session.switchDatabase(to: databaseName)
            }
            config = draft
            persistConfig()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    // MARK: - Query Execution

    private static let blockedPrefixes = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "TRUNCATE", "CREATE"]

    func executeQuery() async {
        guard let cfg = config,
              !cfg.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            queryError = "Enter a query to execute"
            return
        }

        let trimmedQuery = cfg.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cfg.databaseType != DatabaseType.convex.rawValue {
            let trimmedUpper = trimmedQuery.uppercased()
            if Self.blockedPrefixes.contains(where: { trimmedUpper.hasPrefix($0) }) {
                queryError = "Only read-only queries are supported"
                return
            }
        }

        isExecutingQuery = true
        queryError = nil
        let startTime = Date()
        defer {
            isExecutingQuery = false
            executionTime = Date().timeIntervalSince(startTime)
        }

        do {
            let results = try await session.executeRawQuery(trimmedQuery, schema: cfg.schemaName)
            queryResult = results.first
            saveQueryCache()
            dataController?.queryBlockDidUpdate(blockId: block.id)
        } catch {
            queryError = error.localizedDescription
            queryResult = nil
        }
    }

    private func saveQueryCache() {
        guard let result = queryResult else { return }
        block.saveCachedResult(CachedQueryData(from: result))
        dataController?.saveContext()
    }

    // MARK: - Config Updates

    func setQueryText(_ text: String) {
        config?.queryText = text
        persistConfig()
    }

    func setOutputName(_ name: String) {
        config?.outputName = name
        persistConfig()
    }

    func reloadConfig() {
        config = block.queryBlockConfig()
        if let cfg = config, !cfg.connectionKeychainId.isEmpty {
            Task { await reconnectAndLoad(cfg) }
        }
    }

    // MARK: - Persistence

    func persistConfig() {
        guard let cfg = config else { return }
        block.saveQueryBlockConfig(cfg)
        dataController?.updateBlock(block)
    }

    // MARK: - Cleanup

    func cleanup() async {
        await session.disconnect()
    }
}
