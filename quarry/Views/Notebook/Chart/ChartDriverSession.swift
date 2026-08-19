import Foundation

actor ChartDriverSession {
    private var driver: (any DatabaseDriver)?
    private var connectedUri: String?
    private var databaseType: DatabaseType = .sqlite

    func connect(databaseType: DatabaseType, uri: String) async throws {
        if connectedUri == uri { return }
        await driver?.disconnect()
        let newDriver = DatabaseDriverFactory.createDriver(for: databaseType)
        _ = try await newDriver.connect(to: uri)
        driver = newDriver
        connectedUri = uri
        self.databaseType = databaseType
    }

    func switchDatabase(to name: String) async throws {
        guard let driver else { throw ChartBlockError.notConnected }
        try await driver.switchDatabase(to: name)
    }

    func listDatabases() async throws -> [any DatabaseWrapper] {
        guard let driver else { throw ChartBlockError.notConnected }
        return try await driver.listDatabases()
    }

    func listCollections(schema: String?) async throws -> [any CollectionWrapper] {
        guard let driver else { throw ChartBlockError.notConnected }
        return try await driver.listCollections(schema: schema)
    }

    func getSchema(tableName: String, schema: String?) async throws -> DatabaseSchemaResult? {
        guard let driver else { throw ChartBlockError.notConnected }
        return try await driver.getSchema(for: tableName, schema: schema)
    }

    func fetchTableData(tableName: String, schema: String?, limit: Int, filters: [ChartFilterCondition] = []) async throws -> QueryResult {
        guard let driver else { throw ChartBlockError.notConnected }

        let validFilters = filters.filter(\.isComplete)

        if databaseType == .convex {
            let filterDict = convexFilterDocument(from: validFilters, tableName: tableName)
            let convexSchema = (schema == "app") ? nil : schema
            let result = try await driver.findDocuments(
                in: tableName,
                databaseSchema: convexSchema,
                filter: filterDict,
                skip: 0,
                limit: limit,
                sortBy: nil,
                ascending: nil
            )
            return result
        }

        if validFilters.isEmpty {
            return try await driver.findDocuments(
                in: tableName,
                databaseSchema: schema,
                filter: [:],
                skip: 0,
                limit: limit,
                sortBy: nil,
                ascending: nil
            )
        }

        let whereClause = validFilters.map(\.sqlFragment).joined(separator: " AND ")
        let schemaPrefix = schema.map { "\"\($0)\"." } ?? ""
        let query = "SELECT * FROM \(schemaPrefix)\"\(tableName)\" WHERE \(whereClause) LIMIT \(limit)"
        let results = try await driver.executeRawQuery(query, databaseSchema: schema)
        return results.first ?? QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])
    }

    private static let convexAggregationFetchLimit = 100

    func fetchAggregatedData(
        tableName: String,
        schema: String?,
        dimensions: [String],
        measures: [(column: String, aggregation: AggregationFunction)],
        limit: Int,
        filters: [ChartFilterCondition] = []
    ) async throws -> QueryResult {
        guard let driver else { throw ChartBlockError.notConnected }

        let validFilters = filters.filter(\.isComplete)

        if databaseType == .convex {
            let filterDict = convexFilterDocument(from: validFilters, tableName: tableName)
            // Convex root "app" component does not need componentId — pass nil to avoid it
            let convexSchema = (schema == "app") ? nil : schema
            let raw = try await driver.findDocuments(
                in: tableName,
                databaseSchema: convexSchema,
                filter: filterDict,
                skip: 0,
                limit: Self.convexAggregationFetchLimit,
                sortBy: nil,
                ascending: nil
            )
            let aggregated = ConvexAggregator.aggregate(raw, dimensions: dimensions, measures: measures)
            return aggregated
        }

        let schemaPrefix = schema.map { "\"\($0)\"." } ?? ""

        var selectParts: [String] = dimensions.map { "\"\($0)\"" }
        for measure in measures {
            let expr = measure.aggregation.sqlExpression(for: measure.column)
            let alias = "\(measure.column)\(measure.aggregation.sqlAliasSuffix)"
            selectParts.append("\(expr) AS \"\(alias)\"")
        }

        var query = "SELECT \(selectParts.joined(separator: ", ")) FROM \(schemaPrefix)\"\(tableName)\""

        if !validFilters.isEmpty {
            let whereClause = validFilters.map(\.sqlFragment).joined(separator: " AND ")
            query += " WHERE \(whereClause)"
        }

        if !dimensions.isEmpty {
            let groupBy = dimensions.map { "\"\($0)\"" }.joined(separator: ", ")
            query += " GROUP BY \(groupBy) ORDER BY \(groupBy)"
        }

        query += " LIMIT \(limit)"

        let results = try await driver.executeRawQuery(query, databaseSchema: schema)
        return results.first ?? QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])
    }

    func fetchSingleValue(
        tableName: String,
        schema: String?,
        column: String,
        aggregation: AggregationFunction,
        filters: [ChartFilterCondition] = []
    ) async throws -> Double? {
        guard let driver else { throw ChartBlockError.notConnected }

        let validFilters = filters.filter(\.isComplete)

        if databaseType == .convex {
            let filterDict = convexFilterDocument(from: validFilters, tableName: tableName)
            let convexSchema = (schema == "app") ? nil : schema
            let raw = try await driver.findDocuments(
                in: tableName,
                databaseSchema: convexSchema,
                filter: filterDict,
                skip: 0,
                limit: Self.convexAggregationFetchLimit,
                sortBy: nil,
                ascending: nil
            )
            let value = ConvexAggregator.singleValue(raw, column: column, aggregation: aggregation)
            return value
        }

        let schemaPrefix = schema.map { "\"\($0)\"." } ?? ""
        let expr = aggregation.sqlExpression(for: column)
        var query = "SELECT \(expr) AS \"metric_value\" FROM \(schemaPrefix)\"\(tableName)\""

        if !validFilters.isEmpty {
            let whereClause = validFilters.map(\.sqlFragment).joined(separator: " AND ")
            query += " WHERE \(whereClause)"
        }

        let results = try await driver.executeRawQuery(query, databaseSchema: schema)
        guard let result = results.first,
              let row = result.rows.first,
              let info = row["metric_value"],
              let value = info.value else { return nil }

        switch value {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        case .int64(let value):
            return Double(value)
        case .string(let value), .decimalString(let value):
            return Double(value)
        default: return nil
        }
    }

    func executeRawQuery(_ query: String, schema: String?) async throws -> [QueryResult] {
        guard let driver else { throw ChartBlockError.notConnected }
        return try await driver.executeRawQuery(query, databaseSchema: schema)
    }

    func getInformationSchema() async throws -> [InformationSchema] {
        guard let driver else { throw ChartBlockError.notConnected }
        return try await driver.getInformationSchema()
    }

    func disconnect() async {
        await driver?.disconnect()
        driver = nil
        connectedUri = nil
        databaseType = .sqlite
    }

    // MARK: - Convex Filter Helpers

    private func convexFilterDocument(from filters: [ChartFilterCondition], tableName: String) -> DatabaseDocument {
        guard !filters.isEmpty else { return [:] }

        guard let convexDriver = driver as? ConvexDriver else { return [:] }

        let conditions = filters.map { filter -> FilterCondition in
            FilterCondition(
                conjunction: .and,
                field: filter.field,
                filterOperator: filter.filterOperator.toFilterOperator,
                value: filter.value
            )
        }

        let json = convexDriver.generateFilterQuery(from: conditions, tableName: tableName)
        guard !json.isEmpty else { return [:] }
        return ["rawQuery": .string(json)]
    }
}

extension ChartFilterCondition.ChartFilterOperator {
    var toFilterOperator: FilterOperator {
        switch self {
        case .equals: .equals
        case .notEquals: .notEquals
        case .greaterThan: .greaterThan
        case .greaterThanOrEquals: .greaterThanOrEquals
        case .lessThan: .lessThan
        case .lessThanOrEquals: .lessThanOrEquals
        case .like: .ilike
        case .isNull: .isNull
        case .isNotNull: .isNotNull
        }
    }
}

enum ChartBlockError: LocalizedError {
    case notConnected
    case invalidDatabaseType
    case noAxesConfigured

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to database"
        case .invalidDatabaseType: "Unsupported database type"
        case .noAxesConfigured: "Select X and Y axes to render chart"
        }
    }
}
