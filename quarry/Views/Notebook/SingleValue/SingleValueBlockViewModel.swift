import Foundation

@Observable
@MainActor
final class SingleValueBlockViewModel {
    let block: NotebookBlock
    private weak var dataController: NotebookDataController?
    let session = ChartDriverSession()

    var config: SingleValueBlockConfig?

    // Table picker state
    var isShowingTablePicker = false
    var availableCollections: [any CollectionWrapper] = []
    var availableSchemas: [InformationSchema] = []
    var selectedPickerSchema: String?

    // Environment/deployment state (Convex)
    var availableEnvironments: [String] = []
    var selectedEnvironment: String?

    var schemaResult: DatabaseSchemaResult?

    // Single value state
    var singleValueResult: Double?
    var isLoadingSingleValue = false
    var singleValueError: String?

    // Connection state
    var isConnecting = false
    var connectionError: String?

    private(set) var hasStartedLoading = false

    init(block: NotebookBlock, dataController: NotebookDataController) {
        self.block = block
        self.dataController = dataController
        self.config = block.singleValueConfig()
    }

    func loadDataIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true

        if dataController?.isDashboardPublished == true,
           let cached = block.cachedSingleValue() {
            singleValueResult = cached.value
            return
        }

        guard let cfg = config, !cfg.connectionKeychainId.isEmpty else { return }
        Task {
            await reconnectAndLoad(cfg)
        }
    }

    // MARK: - Connection

    private func resolveConnectionUri(_ cfg: SingleValueBlockConfig) -> String? {
        dataController?.connections.first(where: { $0.keychainId == cfg.connectionKeychainId })?.connectionUri
    }

    func reconnectAndRefresh() async {
        guard let cfg = config else { return }
        if cfg.sourceQueryBlockId != nil {
            await fetchSingleValue()
        } else if !cfg.connectionKeychainId.isEmpty {
            await reconnectAndLoad(cfg)
        }
    }

    private func reconnectAndLoad(_ cfg: SingleValueBlockConfig) async {
        guard let dbType = DatabaseType(rawValue: cfg.databaseType),
              let uri = resolveConnectionUri(cfg) else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await session.connect(databaseType: dbType, uri: uri)

            if Self.environmentCapableTypes.contains(dbType) {
                let databases = try await session.listDatabases()
                availableEnvironments = databases.map(\.name)
                if !cfg.databaseName.isEmpty {
                    selectedEnvironment = cfg.databaseName
                }
            }

            if !cfg.databaseName.isEmpty {
                try await session.switchDatabase(to: cfg.databaseName)
            }

            try await loadSchemasAndCollections(databaseType: dbType, preferredSchema: cfg.schemaName)

            guard !cfg.tableName.isEmpty else { return }

            schemaResult = try await session.getSchema(tableName: cfg.tableName, schema: cfg.schemaName)

            guard cfg.column != nil else { return }

            await fetchSingleValue()
        } catch {
            singleValueError = error.localizedDescription
        }
    }

    private static let environmentCapableTypes: Set<DatabaseType> = [.convex]

    func connectToQuerySource(blockId: UUID, outputName: String) {
        guard let result = dataController?.queryResult(for: blockId) else {
            singleValueError = "Run the source query block first"
            return
        }

        let cfg = SingleValueBlockConfig(
            connectionKeychainId: "",
            connectionName: outputName,
            databaseType: "",
            databaseName: "",
            tableName: outputName,
            sourceQueryBlockId: blockId.uuidString
        )
        config = cfg

        schemaResult = DatabaseSchemaResult(
            tableName: outputName,
            schemaName: "",
            columns: result.columns.map { col in
                DatabaseSchemaInfo(
                    columnName: col.name,
                    dataType: col.dataType,
                    formatType: col.format ?? col.dataType,
                    typeOid: 0
                )
            },
            totalCount: result.columns.count
        )

        persistConfig()
    }

    func connectToSource(_ connection: Connection) async {
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        let uri = connection.connectionUri
        guard let dbType = DatabaseType(rawValue: connection.databaseType.rawValue) else {
            connectionError = "Unsupported database type"
            return
        }

        let draft = SingleValueBlockConfig(
            connectionKeychainId: connection.keychainId,
            connectionName: connection.name,
            databaseType: connection.databaseType.rawValue,
            databaseName: connection.defaultDatabase ?? "",
            tableName: ""
        )

        do {
            try await session.connect(databaseType: dbType, uri: uri)

            if Self.environmentCapableTypes.contains(dbType) {
                let databases = try await session.listDatabases()
                availableEnvironments = databases.map(\.name)

                let defaultDb = connection.defaultDatabase ?? ""
                let envToSelect = availableEnvironments.first(where: { $0 == defaultDb })
                    ?? availableEnvironments.first

                config = draft

                if let env = envToSelect {
                    try await session.switchDatabase(to: env)
                    selectedEnvironment = env
                    config?.databaseName = env

                    try await loadSchemasAndCollections(databaseType: dbType, preferredSchema: nil)
                }
            } else {
                if let defaultDb = connection.defaultDatabase, !defaultDb.isEmpty {
                    try? await session.switchDatabase(to: defaultDb)
                }

                try await loadSchemasAndCollections(databaseType: dbType, preferredSchema: nil)

                config = draft
            }

            persistConfig()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func switchEnvironment(_ environmentName: String) async {
        selectedEnvironment = environmentName
        availableCollections = []
        availableSchemas = []
        selectedPickerSchema = nil
        schemaResult = nil
        singleValueResult = nil
        singleValueError = nil

        if var cfg = config {
            cfg.databaseName = environmentName
            cfg.tableName = ""
            cfg.schemaName = nil
            cfg.column = nil
            config = cfg
            persistConfig()
        }

        do {
            try await session.switchDatabase(to: environmentName)
            let dbType = config.flatMap { DatabaseType(rawValue: $0.databaseType) } ?? .convex
            try await loadSchemasAndCollections(databaseType: dbType, preferredSchema: nil)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private static let schemaCapableTypes: Set<DatabaseType> = [.postgres, .supabase, .convex, .mysql]

    private func loadSchemasAndCollections(databaseType: DatabaseType, preferredSchema: String?) async throws {
        if Self.schemaCapableTypes.contains(databaseType) {
            let schemas = try await session.getInformationSchema()
            availableSchemas = schemas
            let schema = preferredSchema ?? schemas.first(where: { $0.name == "public" })?.name ?? schemas.first?.name
            selectedPickerSchema = schema
            availableCollections = try await session.listCollections(schema: schema)
        } else {
            availableSchemas = []
            selectedPickerSchema = nil
            availableCollections = try await session.listCollections(schema: nil)
        }
    }

    func loadCollections(schema: String?) async {
        selectedPickerSchema = schema
        schemaResult = nil
        singleValueResult = nil
        singleValueError = nil
        if var cfg = config {
            cfg.tableName = ""
            cfg.schemaName = schema
            cfg.column = nil
            config = cfg
            persistConfig()
        }
        do {
            availableCollections = try await session.listCollections(schema: schema)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func confirmTableSelection(tableName: String) {
        guard var cfg = config else { return }
        cfg.tableName = tableName
        cfg.schemaName = selectedPickerSchema
        cfg.column = nil
        config = cfg
        schemaResult = nil
        singleValueResult = nil
        singleValueError = nil
        persistConfig()
        Task { await loadSchemaForConfig() }
    }

    // MARK: - Schema

    private func loadSchemaForConfig() async {
        guard let cfg = config, !cfg.tableName.isEmpty else { return }
        do {
            schemaResult = try await session.getSchema(tableName: cfg.tableName, schema: cfg.schemaName)
        } catch {
            singleValueError = error.localizedDescription
        }
    }

    // MARK: - Column & Aggregation

    func setColumn(_ column: String) {
        config?.column = column
        if let dataType = schemaResult?.columns.first(where: { $0.columnName == column })?.dataType {
            config?.aggregation = AggregationFunction.defaultAggregation(for: dataType)
        }
        persistConfig()
        triggerFetchIfReady()
    }

    func setAggregation(_ agg: AggregationFunction) {
        config?.aggregation = agg
        persistConfig()
        triggerFetchIfReady()
    }

    func setLabel(_ label: String) {
        config?.label = label.isEmpty ? nil : label
        persistConfig()
    }

    private func triggerFetchIfReady() {
        guard config?.column != nil else { return }
        Task { await fetchSingleValue() }
    }

    // MARK: - Filters

    func addFilter(_ filter: ChartFilterCondition) {
        config?.filters.append(filter)
        persistConfig()
        triggerFetchIfReady()
    }

    func updateFilter(_ filter: ChartFilterCondition) {
        guard let index = config?.filters.firstIndex(where: { $0.id == filter.id }) else { return }
        config?.filters[index] = filter
        persistConfig()
        triggerFetchIfReady()
    }

    func removeFilter(id: UUID) {
        config?.filters.removeAll { $0.id == id }
        persistConfig()
        triggerFetchIfReady()
    }

    func removeAllFilters() {
        config?.filters.removeAll()
        persistConfig()
        triggerFetchIfReady()
    }

    var validColumnNames: Set<String> {
        Set(schemaResult?.columns.map(\.columnName) ?? [])
    }

    func isFilterFieldValid(_ filter: ChartFilterCondition) -> Bool {
        validColumnNames.contains(filter.field)
    }

    // MARK: - Data Fetching

    func fetchSingleValue() async {
        guard let cfg = config,
              let column = cfg.column else {
            singleValueError = "Select a column to display"
            return
        }

        // If sourced from a query block, compute aggregation from in-memory result
        if let queryBlockIdStr = cfg.sourceQueryBlockId,
           let queryBlockId = UUID(uuidString: queryBlockIdStr) {
            isLoadingSingleValue = true
            singleValueError = nil
            defer { isLoadingSingleValue = false }

            guard let result = dataController?.queryResult(for: queryBlockId) else {
                singleValueError = "Run the source query block first"
                return
            }

            let values: [Double] = result.rows.compactMap { row -> Double? in
                guard let info = row[column], let value = info.value else { return nil }
                switch value {
                case .double(let value):
                    return value
                case .int(let value):
                    return Double(value)
                case .int64(let value):
                    return Double(value)
                case .string(let value), .decimalString(let value):
                    return Double(value)
                default:
                    return nil
                }
            }

            switch cfg.aggregation {
            case .count: singleValueResult = Double(values.count)
            case .countDistinct: singleValueResult = Double(Set(values).count)
            case .sum: singleValueResult = values.reduce(0, +)
            case .average: singleValueResult = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            case .min: singleValueResult = values.min()
            case .max: singleValueResult = values.max()
            case .none: singleValueResult = values.first
            }
            saveSingleValueCache()
            return
        }

        isLoadingSingleValue = true
        singleValueError = nil
        defer { isLoadingSingleValue = false }
        do {
            let validFilters = cfg.filters.filter { $0.isComplete && isFilterFieldValid($0) }
            singleValueResult = try await session.fetchSingleValue(
                tableName: cfg.tableName,
                schema: cfg.schemaName,
                column: column,
                aggregation: cfg.aggregation,
                filters: validFilters
            )
            saveSingleValueCache()
        } catch {
            singleValueError = error.localizedDescription
        }
    }

    private func saveSingleValueCache() {
        guard let value = singleValueResult else { return }
        block.saveCachedResult(CachedSingleValue(value: value))
        dataController?.saveContext()
    }

    func reloadConfig() {
        config = block.singleValueConfig()
        if let cfg = config, !cfg.tableName.isEmpty {
            Task { await reconnectAndLoad(cfg) }
        }
    }

    func resetConfig() {
        config = nil
        availableCollections = []
        availableSchemas = []
        selectedPickerSchema = nil
        availableEnvironments = []
        selectedEnvironment = nil
        schemaResult = nil
        singleValueResult = nil
        singleValueError = nil
        connectionError = nil
        block.configJSON = ""
        dataController?.updateBlock(block)
        Task { await session.disconnect() }
    }

    // MARK: - Persistence

    private func persistConfig() {
        guard let cfg = config else { return }
        block.saveSingleValueConfig(cfg)
        dataController?.updateBlock(block)
    }

    // MARK: - Cleanup

    func cleanup() async {
        await session.disconnect()
    }
}
