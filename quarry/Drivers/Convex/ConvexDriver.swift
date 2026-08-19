import Foundation
@preconcurrency import ConvexMobile
import Combine
import Synchronization

// MARK: - Convex Wrappers
struct ConvexDatabaseWrapper: DatabaseWrapper {
    let name: String
    let size: String? = nil
    let tableCount: Int? = nil
    let deploymentType: String
    let projectId: Int64
    let deploymentUrl: String
    
    init(name: String, deploymentType: String, projectId: Int64, deploymentId: String) {
        self.name = name
        self.deploymentType = deploymentType
        self.projectId = projectId
        self.deploymentUrl = "https://\(deploymentId).convex.cloud"
    }
}

struct ConvexCollectionWrapper: CollectionWrapper {
    var schema: String?
    var id: ObjectIdentifier
    let name: String
    let type: String = "table"

    init(name: String, schema: String? = nil) {
        self.name = name
        self.schema = schema
        self.id = ObjectIdentifier(NSString(string: name))
    }
}

// MARK: - Convex Driver
actor ConvexDriver: DatabaseDriver {
    nonisolated static func isJavaScriptQuery(_ query: String?) -> Bool {
        guard let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return false
        }

        if let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           parsed["clauses"] != nil || parsed["table"] != nil {
            return false
        }

        return trimmed.contains("export default query")
            || trimmed.contains("ctx.db.query(")
            || trimmed.contains("ctx.db.get(")
            || trimmed.contains("import { query }")
    }

    nonisolated static func isExecutableRawQuery(_ query: String?) -> Bool {
        guard let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return false
        }

        if let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           parsed["table"] != nil {
            return true
        }

        return isJavaScriptQuery(trimmed)
    }

    func ping(to connectionUri: String) async throws {
        throw DatabaseError.notImplemented("Driver does not support this")
    }
    
    private static let convexRawQueryFetchLimit = 500

    func executeRawQuery(_ query: String, databaseSchema: String?) async throws -> [QueryResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try existing JSON format first (has a "table" key)
        if let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           parsed["table"] != nil {
            return try await executeJSONQuery(trimmed, parsed: parsed, databaseSchema: databaseSchema)
        }

        // Otherwise treat as JavaScript for run_test_function
        let convexSchema = (databaseSchema == "app") ? nil : databaseSchema
        return try await executeJSQuery(trimmed, databaseSchema: convexSchema)
    }

    private func executeJSONQuery(_ trimmed: String, parsed: [String: Any], databaseSchema: String?) async throws -> [QueryResult] {
        guard let tableName = parsed["table"] as? String else {
            throw DatabaseError.operationFailed("Convex JSON query requires a 'table' field.")
        }

        let convexSchema = (databaseSchema == "app") ? nil : databaseSchema
        let hasAggregate = parsed["aggregate"] as? [String: Any]
        let fetchLimit = hasAggregate != nil ? Self.convexRawQueryFetchLimit : 100

        // Strip client-only keys before sending to backend
        var filterPayload = parsed
        filterPayload.removeValue(forKey: "join")
        filterPayload.removeValue(forKey: "aggregate")
        let filterJSON = try JSONSerialization.data(withJSONObject: filterPayload, options: [.withoutEscapingSlashes, .sortedKeys])
        let filterDict: DatabaseDocument = ["rawQuery": .string(String(data: filterJSON, encoding: .utf8) ?? trimmed)]
        let result = try await findDocuments(in: tableName, databaseSchema: convexSchema, filter: filterDict, skip: 0, limit: fetchLimit, sortBy: nil, ascending: nil)

        // Apply join if specified
        let joinedResult: QueryResult
        if let joinSpec = parsed["join"] as? [String: Any] {
            joinedResult = try await applyConvexJoin(result: result, joinSpec: joinSpec, databaseSchema: convexSchema)
        } else {
            joinedResult = result
        }

        guard let aggregateSpec = hasAggregate else {
            return [joinedResult]
        }

        let dimensions = aggregateSpec["groupBy"] as? [String] ?? []
        let measuresRaw = aggregateSpec["measures"] as? [[String: String]] ?? []

        let measures: [(column: String, aggregation: AggregationFunction)] = measuresRaw.compactMap { m in
            guard let column = m["column"],
                  let funcRaw = m["function"],
                  let agg = AggregationFunction(rawValue: funcRaw) else { return nil }
            return (column: column, aggregation: agg)
        }

        guard !measures.isEmpty else {
            return [joinedResult]
        }

        let aggregated = ConvexAggregator.aggregate(joinedResult, dimensions: dimensions, measures: measures)
        return [aggregated]
    }

    // MARK: - JavaScript Query Execution (run_test_function)

    private func executeJSQuery(_ jsSource: String, databaseSchema: String?) async throws -> [QueryResult] {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex")
        }

        let preamble = #"import { query } from "convex:/_system/repl/wrappers.js";"#
        let fullSource = jsSource.contains("_system/repl/wrappers") ? jsSource : preamble + "\n" + jsSource

        let componentId: String? = if let databaseSchema {
            getComponentId(for: databaseSchema)
        } else {
            nil
        }

        do {
            let resultJson = try await mobileClient.runTestFunction(
                source: fullSource,
                args: "{}",
                componentId: componentId
            )

            // Parse the JSON result string into a usable value
            guard let data = resultJson.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) else {
                return [convertArbitraryToQueryResult(resultJson)]
            }
            return [convertArbitraryToQueryResult(value)]
        } catch let error as ClientError {
            throw DatabaseError.operationFailed(extractConvexErrorMessage(from: error))
        }
    }

    private func convertArbitraryToQueryResult(_ value: Any?) -> QueryResult {
        // Case 1: Array of objects (most common — table-like data)
        if let array = value as? [[String: Any]] {
            guard !array.isEmpty else {
                return QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])
            }

            // Collect all unique keys across all objects, preserving insertion order
            var columnNames: [String] = []
            var seen = Set<String>()
            for obj in array {
                for key in obj.keys.sorted() where !seen.contains(key) {
                    columnNames.append(key)
                    seen.insert(key)
                }
            }

            // Reorder: put _id first, _creationTime second if present
            let priorityFields = ["_id", "_creationTime"]
            let prioritized = priorityFields.filter { columnNames.contains($0) }
            let rest = columnNames.filter { !priorityFields.contains($0) }
            columnNames = prioritized + rest

            let columns = columnNames.enumerated().map { index, name in
                let sampleValue = array.first { $0[name] != nil }?[name]
                return ConvexValue.createQueryColumnInfo(name: name, value: sampleValue, index: index)
            }

            var rows: [[String: QueryRowInfo]] = []
            var rawRows: [DatabaseRawRow] = []
            for obj in array {
                var row: [String: QueryRowInfo] = [:]
                var rawRow: DatabaseRawRow = [:]
                for col in columns {
                    let val = obj[col.name]
                    row[col.name] = ConvexValue.createQueryRowInfo(value: val, fieldName: col.name)
                    rawRow[col.name] = makeDatabaseValue(from: val)
                }
                rows.append(row)
                rawRows.append(rawRow)
            }

            return QueryResult(columns: columns, rows: rows, totalCount: array.count, rawRows: rawRows)
        }

        // Case 2: Single object → single-row table
        if let obj = value as? [String: Any] {
            return convertArbitraryToQueryResult([obj])
        }

        // Case 3: Array of primitives → single column "value"
        if let array = value as? [Any] {
            let columns = [QueryColumnInfo(name: "value", dataType: "text", format: nil, index: 0)]
            var rows: [[String: QueryRowInfo]] = []
            var rawRows: [DatabaseRawRow] = []
            for item in array {
                rows.append(["value": ConvexValue.createQueryRowInfo(value: item)])
                rawRows.append(["value": makeDatabaseValue(from: item)])
            }
            return QueryResult(columns: columns, rows: rows, totalCount: array.count, rawRows: rawRows)
        }

        // Case 4: Scalar → single cell
        if let val = value {
            let columns = [QueryColumnInfo(name: "value", dataType: "text", format: nil, index: 0)]
            let rows: [[String: QueryRowInfo]] = [["value": ConvexValue.createQueryRowInfo(value: val)]]
            let rawRows: [DatabaseRawRow] = [["value": makeDatabaseValue(from: val)]]
            return QueryResult(columns: columns, rows: rows, totalCount: 1, rawRows: rawRows)
        }

        // Case 5: null/nil → empty result
        return QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])
    }

    private func applyConvexJoin(result: QueryResult, joinSpec: [String: Any], databaseSchema: String?) async throws -> QueryResult {
        guard let joinField = joinSpec["field"] as? String,
              let referencedTable = joinSpec["referencedTable"] as? String else {
            throw DatabaseError.operationFailed("Convex join requires 'field' and 'referencedTable' in the join spec.")
        }
        guard let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex")
        }

        let includeFields = joinSpec["includeFields"] as? [String]

        // Extract unique IDs from the join field
        var uniqueIds: [String] = []
        var seenIds: Set<String> = []
        for row in result.rawRows {
            if let idValue = (row[joinField] ?? nil)?.stringValue, !seenIds.contains(idValue) {
                seenIds.insert(idValue)
                uniqueIds.append(idValue)
            }
        }

        guard !uniqueIds.isEmpty else { return result }

        // Batch fetch via listById
        let idArgs: [ConvexEncodable?] = uniqueIds.map { id -> ConvexEncodable? in
            let entry: [String: ConvexEncodable?] = ["id": id, "tableName": referencedTable]
            return entry
        }

        var args: [String: ConvexEncodable?] = ["ids": idArgs]
        if let databaseSchema, let componentId = getComponentId(for: databaseSchema) {
            args["componentId"] = componentId
        }

        let response: ConvexMobile.ConvexValue = try await mobileClient.query(name: "_system/frontend/listById", with: args)

        // Parse response — listById returns an array in the same order as requested
        let referencedDocs: [[String: Any]?]
        if let valueArray = (response["value"] ?? response).arrayValue {
            referencedDocs = valueArray.map { $0.anyValue as? [String: Any] }
        } else {
            return result
        }

        // Build lookup: id → document
        var docLookup: [String: [String: Any]] = [:]
        for (index, id) in uniqueIds.enumerated() {
            if index < referencedDocs.count, let doc = referencedDocs[index] {
                docLookup[id] = doc
            }
        }

        // Determine which fields to include from referenced docs
        let fieldsToInclude: [String]
        if let specified = includeFields {
            fieldsToInclude = specified
        } else if let firstDoc = docLookup.values.first {
            fieldsToInclude = firstDoc.keys.filter { $0 != "_id" && $0 != "_creationTime" }.sorted()
        } else {
            return result
        }

        // Build new columns: original + joined fields prefixed with referenced table
        var newColumns = result.columns
        let startIdx = newColumns.count
        for (i, field) in fieldsToInclude.enumerated() {
            let columnName = "\(referencedTable).\(field)"
            newColumns.append(QueryColumnInfo(name: columnName, dataType: "text", format: nil, index: startIdx + i))
        }

        // Merge rows
        var newRows: [[String: QueryRowInfo]] = []
        var newRawRows: [DatabaseRawRow] = []

        for (rowIdx, row) in result.rows.enumerated() {
            var mergedRow = row
            let rawRow = rowIdx < result.rawRows.count ? result.rawRows[rowIdx] : DatabaseRawRow()
            var mergedRawRow = rawRow

            let refId = (rawRow[joinField] ?? nil)?.stringValue
            let refDoc = refId.flatMap { docLookup[$0] }

            for field in fieldsToInclude {
                let columnName = "\(referencedTable).\(field)"
                let value: Any? = refDoc?[field] ?? nil
                let displayValue = value.map { ConvexValue.formatValueForDisplay(value: $0, fieldName: field, dataType: "text") }
                mergedRow[columnName] = QueryRowInfo(value: displayValue as Any?, dataType: "text", format: nil)
                mergedRawRow[columnName] = makeDatabaseValue(from: value)
            }

            newRows.append(mergedRow)
            newRawRows.append(mergedRawRow)
        }

        return QueryResult(columns: newColumns, rows: newRows, totalCount: result.totalCount, rawRows: newRawRows)
    }

    func buildAICommandPromptSystemPrompt(_ message: String) async throws -> String {
        let currentDate = Date().formatted(.iso8601)

        let collections = try await listCollections(schema: nil)
        let tablesList = collections.map { "- \($0.name)" }.joined(separator: "\n")

        return """
        You are a Convex query assistant for a desktop database client's CMD+K quick action. Your output is inserted directly into a query editor and executed as-is via Convex's run_test_function, so respond with only the JavaScript query as plain text. Never include explanations, markdown formatting, or code fences.

        <available_tables>
        \(tablesList)
        </available_tables>

        <instructions>
        1. All queries must use this exact JavaScript format:
           export default query({
             handler: async (ctx) => {
               // query logic here
               return await ctx.db.query("tableName").collect();
             },
           })
        2. Queries are read-only. Only use query exports, never mutations or actions.
        3. Use the Convex ctx.db API: ctx.db.query("table"), ctx.db.get(id), .filter(), .order("asc"/"desc"), .collect(), .take(n), .first().
        4. Use table names from the available tables list. If a name seems misspelled, use the closest match.
        5. For new queries, output only the JavaScript code. No preamble or explanation.
        6. For query modifications, return only the modified query.
        7. For query fixes, return only the corrected query.
        8. Return arrays of objects for best tabular display in the results view.
        9. If you need column-level detail for a table, call the get_table_schema tool.
        </instructions>

        <examples>
        <example>
        <input>Get all users</input>
        <output>
        export default query({
          handler: async (ctx) => {
            return await ctx.db.query("users").collect();
          },
        })
        </output>
        </example>

        <example>
        <input>Get the 10 most recent orders</input>
        <output>
        export default query({
          handler: async (ctx) => {
            return await ctx.db.query("orders").order("desc").take(10);
          },
        })
        </output>
        </example>

        <example>
        <input>Show orders with customer names</input>
        <output>
        export default query({
          handler: async (ctx) => {
            const orders = await ctx.db.query("orders").collect();
            return Promise.all(orders.map(async (o) => {
              const customer = await ctx.db.get(o.customerId);
              return { ...o, customerName: customer?.name };
            }));
          },
        })
        </output>
        </example>

        <example>
        <input>Count orders by status</input>
        <output>
        export default query({
          handler: async (ctx) => {
            const orders = await ctx.db.query("orders").collect();
            const byStatus = {};
            for (const o of orders) {
              byStatus[o.status] = (byStatus[o.status] || 0) + 1;
            }
            return Object.entries(byStatus).map(([status, count]) => ({ status, count }));
          },
        })
        </output>
        </example>

        <example>
        <input>Add a limit of 5 to this query:
        export default query({
          handler: async (ctx) => {
            return await ctx.db.query("users").collect();
          },
        })</input>
        <output>
        export default query({
          handler: async (ctx) => {
            return await ctx.db.query("users").take(5);
          },
        })
        </output>
        </example>
        </examples>

        Current date: \(currentDate)
        """
    }
    
    typealias Database = ConvexDatabaseWrapper
    typealias Collection = ConvexCollectionWrapper
    
    // Connection state
    private var accessToken: String?
    private var projectName: String?
    private var teamName: String?
    private var projectId: Int64?
    private var deployments: [ConvexDatabaseWrapper] = []
    private var selectedDeployment: ConvexDatabaseWrapper?
    private var isConnected = false
    
    // Convex clients
    private var convexMobileClient: ConvexMobile.ConvexClient?
    
    private struct CachedSchemas: @unchecked Sendable {
        let payload: [String: Any]
        let cacheTime: Date
    }

    private struct SchemaCache: @unchecked Sendable {
        var entries: [String: CachedSchemas] = [:]
    }
    private let schemaCache = Mutex(SchemaCache())
    private let schemaCacheTimeout: TimeInterval = 300 // 5 minutes
    
    // Pagination cursor storage (per table, per filter signature, per page number)
    private var tablePageCursors: [String: [String: [Int: String?]]] = [:]

    // Component ID mapping (schema name -> component ID)
    private var _componentIdMapping: [String: String] = [:]

    // Dedup for getInformationSchema — multiple table-open call sites would
    // otherwise each fire their own components:list query before the prefetch
    // lands. Cleared by disconnect() / switchDatabase().
    private var componentsLoaded = false
    private var componentsFetchTask: Task<Void, Never>?

    // Subscription payload deduplication (per table)
    private var lastSubscriptionPayloadHash: [String: String] = [:]

    private var componentIdMapping: [String: String] {
        get {
            _componentIdMapping
        }
        set {
            _componentIdMapping = newValue
        }
    }

    private func setComponentId(_ componentId: String, for schema: String) {
        _componentIdMapping[schema] = componentId
    }

    private func getComponentId(for schema: String) -> String? {
        // The root component ("app") must not be sent as a componentId —
        // paginatedTableDocuments hangs indefinitely when a componentId is
        // passed for the root. The Convex dashboard omits componentId for root.
        guard schema != "app" else { return nil }
        let componentId = _componentIdMapping[schema]
        return (componentId?.isEmpty == false) ? componentId : nil
    }

    private func normalizedSchemaName(_ schema: String?) -> String {
        guard let schema, !schema.isEmpty else {
            return "app"
        }
        return schema
    }

    private func cachedSchemas(for schema: String?) -> [String: Any]? {
        let cacheKey = normalizedSchemaName(schema)
        return schemaCache.withLock { cache in
            guard let entry = cache.entries[cacheKey],
                  Date().timeIntervalSince(entry.cacheTime) < schemaCacheTimeout else {
                return nil
            }
            return entry.payload
        }
    }

    private func setCachedSchemas(_ schemas: [String: Any], for schema: String?) {
        let cacheKey = normalizedSchemaName(schema)
        schemaCache.withLock {
            $0.entries[cacheKey] = CachedSchemas(payload: schemas, cacheTime: Date())
        }
    }

    private func clearCachedSchemas(for schema: String?) {
        let cacheKey = normalizedSchemaName(schema)
        _ = schemaCache.withLock {
            $0.entries.removeValue(forKey: cacheKey)
        }
    }
    
    // MARK: - Connection Management
    
    func connect(to connectionUri: String) async throws -> ConvexDatabaseWrapper {
        // Input validation
        guard !connectionUri.isEmpty else {
            throw DatabaseError.configurationError("Access token is required for Convex connection")
        }

        // Parse target database from URI fragment if present
        let targetDatabase = parseTargetDatabase(from: connectionUri)
        let cleanConnectionUri = connectionUri.components(separatedBy: "#").first ?? connectionUri

        // Parse token and optional embedded metadata
        let parsed = parseDeployKeyAndMeta(from: cleanConnectionUri)

        self.accessToken = parsed.deployKey

        guard let meta = parsed.meta else {
            throw DatabaseError.configurationError("Embedded Convex token metadata missing. Please re-authorize and try again.")
        }
        self.projectId = meta.projectId
        self.teamName = meta.teamName
        self.projectName = meta.projectName
        try await fetchDeployments(projectId: meta.projectId, embeddedDeployments: meta.deployments)

        // Select deployment based on target database or use first as default
        let deploymentToUse: ConvexDatabaseWrapper
        if let targetDatabaseName = targetDatabase,
           let targetDeployment = deployments.first(where: { $0.name == targetDatabaseName }) {
            deploymentToUse = targetDeployment
        } else {
            guard let firstDeployment = deployments.first else {
                throw DatabaseError.connectionFailed("No deployments found")
            }
            deploymentToUse = firstDeployment
        }

        selectedDeployment = deploymentToUse

        guard let deployKey = self.accessToken else {
            throw DatabaseError.configurationError("Missing deploy key after parsing token")
        }
        convexMobileClient = ConvexMobile.ConvexClient(deploymentUrl: deploymentToUse.deploymentUrl)
        try await convexMobileClient?.setAdminAuth(deployKey: deployKey)
        self.isConnected = true

        // Warm component mapping + root schema cache during the user's click-delay
        // so the first table open doesn't pay those round-trips serially.
        Task { await self.prefetchAfterConnect() }

        return deploymentToUse
    }
    
    func disconnect() async {
        self.accessToken = nil
        self.projectName = nil
        self.teamName = nil
        self.projectId = nil
        self.deployments = []
        self.selectedDeployment = nil
        self.convexMobileClient = nil
        self.schemaCache.withLock { $0 = SchemaCache() }
        self.lastSubscriptionPayloadHash.removeAll()
        self._componentIdMapping.removeAll()
        self.componentsLoaded = false
        self.componentsFetchTask?.cancel()
        self.componentsFetchTask = nil
        self.isConnected = false
    }
    
    func reconnect() async throws {
        guard let token = accessToken else {
            throw DatabaseError.configurationError("No access token available for reconnection")
        }
        
        await disconnect()
        _ = try await connect(to: token)
    }
    
    func getBuildInfo() async throws -> BuildInfo {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }

        let versionNumber: String = try await mobileClient.query(name: "_system/frontend/getVersion", with: [:])

        // Check if response is empty
        guard !versionNumber.isEmpty && versionNumber != "null" else {
            throw DatabaseError.operationFailed("Empty or null response from _system/cli/tables")
        }

        let cleanVersion = versionNumber.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return BuildInfo(version: cleanVersion, databaseType: .convex)
    }

    // MARK: - Convex-specific Info

    /// Get the deployment URL for the currently connected environment
    func getCurrentDeploymentUrl() async -> String? {
        return selectedDeployment?.deploymentUrl
    }

    /// Fetch fresh deployments from the Convex management API
    func refreshDeploymentsFromAPI() async throws -> [ConvexDatabaseWrapper] {
        guard let accessToken = self.accessToken else {
            throw DatabaseError.configurationError("No access token available")
        }
        guard let projectId = self.projectId else {
            throw DatabaseError.configurationError("No project ID available")
        }

        let client = ConvexClient(accessToken: accessToken, deploymentUrl: "")
        let deploymentsArray: [ConvexDeployment] = try await client.listDeployments(projectId: projectId)
        let sortedDeployments = deploymentsArray.sorted { lhs, rhs in
            lhs.deploymentType.localizedCaseInsensitiveCompare(rhs.deploymentType) == .orderedAscending
        }
        let fresh = sortedDeployments.map { deployment in
            let label = Self.getDeploymentLabel(deployment: deployment, whoseName: teamName)
            return ConvexDatabaseWrapper(
                name: label,
                deploymentType: deployment.deploymentType,
                projectId: deployment.projectId,
                deploymentId: deployment.name,
            )
        }
        self.deployments = fresh
        return fresh
    }
    
    func switchDatabase(to databaseName: String) async throws {
        guard isConnected else {
            throw DatabaseError.connectionFailed("Not connected to Convex")
        }
        
        // Find the deployment with the matching name
        guard let deployment = deployments.first(where: { $0.name == databaseName }) else {
            throw DatabaseError.configurationError("Deployment '\(databaseName)' not found")
        }
        
        selectedDeployment = deployment
        
        if let token = accessToken {
            let newMobileClient = ConvexMobile.ConvexClient(deploymentUrl: deployment.deploymentUrl)
            try await newMobileClient.setAdminAuth(deployKey: token)
            convexMobileClient = newMobileClient
            // Previous deployment's caches are stale for the new URL.
            schemaCache.withLock { $0 = SchemaCache() }
            _componentIdMapping.removeAll()
            componentsLoaded = false
            componentsFetchTask?.cancel()
            componentsFetchTask = nil
            Task { await self.prefetchAfterConnect() }
        }
    }
    
    // MARK: - Private Helper Methods

    private func fetchDeployments(projectId: Int64, embeddedDeployments: [EmbeddedDeployment]? = nil) async throws {
        // Use embedded deployments from OAuth metadata (instant, no network)
        if let embedded = embeddedDeployments, !embedded.isEmpty {
            let sortedEmbedded = embedded.sorted { lhs, rhs in
                lhs.deploymentType.localizedCaseInsensitiveCompare(rhs.deploymentType) == .orderedAscending
            }
            self.deployments = sortedEmbedded.map { dep in
                ConvexDatabaseWrapper(
                    name: dep.name,
                    deploymentType: dep.deploymentType,
                    projectId: dep.projectId,
                    deploymentId: dep.deploymentId,
                )
            }
            return
        }
        guard let accessToken = self.accessToken else {
            throw DatabaseError.configurationError("No access token available")
        }

        do {
            let client = ConvexClient(accessToken: accessToken, deploymentUrl: "")
            let deploymentsArray: [ConvexDeployment] = try await client.listDeployments(projectId: projectId)
            let sortedDeployments = deploymentsArray.sorted { lhs, rhs in
                lhs.deploymentType.localizedCaseInsensitiveCompare(rhs.deploymentType) == .orderedAscending
            }
            self.deployments = sortedDeployments.map { deployment in
                let label = Self.getDeploymentLabel(deployment: deployment, whoseName: teamName)
                return ConvexDatabaseWrapper(
                    name: label,
                    deploymentType: deployment.deploymentType,
                    projectId: deployment.projectId,
                    deploymentId: deployment.name,
                )
            }
        } catch let convexError as ConvexError {
            throw convexError.asDatabaseError
        }
    }

    // MARK: - Deployment Label Helper
    static func getDeploymentLabel(deployment: ConvexDeployment, whoseName: String?) -> String {
        switch deployment.deploymentType {
        case "prod":
            return "Production"
        case "preview":
            let preview = deployment.previewIdentifier?.isEmpty == false ? deployment.previewIdentifier! : "Unknown"
            return "Preview: \(preview)"
        case "dev":
            return "Development (Cloud)"
        default:
            return ""
        }
    }
    
    // MARK: - Database Operations
    
    func listDatabases() async throws -> [ConvexDatabaseWrapper] {
        guard isConnected else {
            throw DatabaseError.connectionFailed("Not connected to Convex")
        }
        
        return deployments
    }
    
    func getDatabaseMetadata() async throws -> [ConvexDatabaseWrapper] {
        return try await listDatabases()
    }
    
    func listCollections(schema: String?) async throws -> [ConvexCollectionWrapper] {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }
        let effectiveSchema = normalizedSchemaName(schema)

        return try await wrapConvexError("query") {
            if effectiveSchema != "app", getComponentId(for: effectiveSchema) == nil {
                await ensureComponentsLoaded()
            }
            // Extract a Sendable String? so the arg dict (which contains the
            // non-Sendable ConvexEncodable existential) can be rebuilt inside
            // each child task rather than sent across them.
            let componentId: String? = (effectiveSchema == "app") ? nil : getComponentId(for: effectiveSchema)

            // Skip the getSchemas round-trip when the cache is already warm
            // (connect-time prefetch or a prior call). On a miss, fire both
            // queries in parallel so the hot path is bound by max(RTT), not sum.
            let tableMappingJson: ConvexMobile.ConvexValue
            if cachedSchemas(for: effectiveSchema) == nil {
                async let tableMappingTask: ConvexMobile.ConvexValue = mobileClient.query(
                    name: "_system/frontend/getTableMapping",
                    with: Self.schemaQueryArgs(componentId: componentId)
                )
                async let schemasTask: ConvexMobile.ConvexValue = mobileClient.query(
                    name: "_system/frontend/getSchemas",
                    with: Self.schemaQueryArgs(componentId: componentId)
                )
                let (fetchedMapping, schemasJson) = try await (tableMappingTask, schemasTask)
                tableMappingJson = fetchedMapping
                if let schemasDict = schemasJson.anyValue as? [String: Any], !schemasDict.isEmpty {
                    self.setCachedSchemas(schemasDict, for: effectiveSchema)
                }
            } else {
                tableMappingJson = try await mobileClient.query(
                    name: "_system/frontend/getTableMapping",
                    with: Self.schemaQueryArgs(componentId: componentId)
                )
            }

            guard let tableMappingDict = tableMappingJson.objectValue, !tableMappingDict.isEmpty else {
                throw DatabaseError.operationFailed("Empty response from _system/frontend/getTableMapping")
            }

            return tableMappingDict.compactMapValues { $0.stringValue }
                .values
                .filter { !$0.hasPrefix("_") }
                .sorted()
                .map { ConvexCollectionWrapper(name: $0, schema: schema) }
        }
    }
    
    // MARK: - Collection Operations (Stub implementations)
    
    func getDocumentCount(for collectionName: String, filter: DatabaseDocument) async throws -> Int {
        throw DatabaseError.notImplemented("Document operations not yet implemented for Convex")
    }
    
    func findDocuments(in collectionName: String, filter: DatabaseDocument) async throws -> [QueryResult] {
        let result = try await findDocuments(in: collectionName, databaseSchema: nil, filter: filter, skip: 0, limit: 100, sortBy: nil, ascending: true)
        return [result]
    }
    
    func findDocuments(in collectionName: String, filter: DatabaseDocument, skip: Int, limit: Int) async throws -> QueryResult {
        return try await findDocuments(in: collectionName, databaseSchema: nil, filter: filter, skip: skip, limit: limit, sortBy: nil, ascending: true)
    }
    
    func findDocuments(in collectionName: String, databaseSchema: String?, filter: DatabaseDocument, skip: Int, limit: Int, sortBy: String?, ascending: Bool?) async throws -> QueryResult {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }

        let rawQuery = filter["rawQuery"]?.stringValue
        if Self.isExecutableRawQuery(rawQuery) {
            let rawResults = try await executeRawQuery(rawQuery ?? "", databaseSchema: databaseSchema)
            let queryResult = rawResults.first ?? QueryResult(columns: [], rows: [], totalCount: 0, rawRows: [])
            return applyClientSideWindow(to: queryResult, skip: skip, limit: limit, sortBy: sortBy, ascending: ascending)
        }

        return try await wrapConvexError("query") {
            let orderString = ascending.map { $0 ? "asc" : "desc" }
            let filtersBase64 = try encodeFilterToBase64(
                rawFilterJSON: filter["rawQuery"]?.stringValue,
                order: orderString
            )

            var args: [String: ConvexEncodable?] = [
                "table": collectionName,
                "filters": filtersBase64,
                "paginationOpts": ["cursor": nil, "numItems": Float(limit)] as [String: ConvexEncodable?],
            ]
            if let databaseSchema, let componentId = getComponentId(for: databaseSchema) {
                args["componentId"] = componentId
            }

            let jsonRaw: ConvexMobile.ConvexValue = try await mobileClient.query(name: "_system/frontend/paginatedTableDocuments", with: args)
            let json: ConvexMobile.ConvexValue = jsonRaw["value"] ?? jsonRaw

            guard let jsonObj = json.objectValue, !jsonObj.isEmpty else {
                throw DatabaseError.operationFailed("Empty response from _system/frontend/paginatedTableDocuments")
            }
            guard let pageArray = json["page"]?.arrayValue else {
                debugLog("JSON structure: \(json)")
                throw DatabaseError.operationFailed("Missing 'page' array in response")
            }

            let documents = pageArray.compactMap { $0.anyValue as? [String: Any] }
            let totalCount = json["totalCount"]?.numberValue.flatMap { Int($0) } ?? documents.count

            if let continueCursor = json["continueCursor"]?.stringValue, limit > 0 {
                let currentPageIndex = (skip / max(1, limit)) + 1
                var filterMap = tablePageCursors[collectionName] ?? [:]
                var pageMap = filterMap[filtersBase64] ?? [:]
                if currentPageIndex == 1 && pageMap[1] == nil { pageMap[1] = nil }
                pageMap[currentPageIndex + 1] = continueCursor
                filterMap[filtersBase64] = pageMap
                tablePageCursors[collectionName] = filterMap
                debugLog("📄 Stored cursor for table=\(collectionName) filterKeyLen=\(filtersBase64.count) page=\(currentPageIndex + 1)")
            }

            return try await processConvexDocuments(documents, totalCount: totalCount, for: collectionName, databaseSchema: databaseSchema)
        }
    }
    
    func createDocument(in collectionName: String, databaseSchema: String?, document: DatabaseDocument) async throws {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }

        try await wrapConvexError("create") {
            let encodableDocument = document.mapValues { convertToConvexEncodable($0) }
            var args: [String: ConvexEncodable?] = [
                "table": collectionName,
                "documents": [encodableDocument]
            ]
            if let databaseSchema, let componentId = getComponentId(for: databaseSchema) {
                args["componentId"] = componentId
            }

            struct AddDocumentResult: Decodable { let success: Bool? }
            let _: AddDocumentResult = try await mobileClient.mutation("_system/frontend/addDocument", with: args)
            debugLog("✅ Document created successfully in table '\(collectionName)'")
        }
    }

    func updateDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID, data: DatabaseDocument) async throws {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }

        try await wrapConvexError("update") {
            let docId = documentId(from: id.value)
            let encodableFields: [String: ConvexEncodable?] = data.mapValues { convertToConvexEncodable($0) }
            var args: [String: ConvexEncodable?] = [
                "table": collectionName,
                "ids": [docId],
                "fields": encodableFields
            ]
            if let databaseSchema, let componentId = getComponentId(for: databaseSchema) {
                args["componentId"] = componentId
            }

            struct PatchDocumentsResult: Decodable { let success: Bool }
            let result: PatchDocumentsResult = try await mobileClient.mutation("_system/frontend/patchDocumentsFields", with: args)
            guard result.success else {
                throw DatabaseError.operationFailed("Patch operation reported failure for document '\(docId)' in table '\(collectionName)'")
            }
            debugLog("✅ Document updated successfully in table '\(collectionName)' with id '\(docId)'")
        }
    }

    func deleteDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID) async throws {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }

        try await wrapConvexError("delete") {
            let docId = documentId(from: id.value)
            var args: [String: ConvexEncodable?] = [
                "toDelete": [["id": docId, "tableName": collectionName] as [String: ConvexEncodable?]]
            ]
            if let databaseSchema, let componentId = getComponentId(for: databaseSchema) {
                args["componentId"] = componentId
            }

            struct DeleteDocumentsResult: Decodable { let success: Bool? }
            let _: DeleteDocumentsResult = try await mobileClient.mutation("_system/frontend/deleteDocuments", with: args)
            debugLog("🗑️ Document deleted successfully in table '\(collectionName)' with id '\(docId)'")
        }
    }
    
    func getSchema(for collectionName: String, schema: String?) async throws -> DatabaseSchemaResult? {
        guard isConnected else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }

        // Try to get schema from Convex. If no active schema, return nil —
        // the table view derives columns from the query result.
        do {
            _ = try await getAllSchemas(for: schema)

            guard let tableSchema = cachedTableSchema(for: collectionName, schema: schema) else {
                return nil
            }
            
            var columns: [DatabaseSchemaInfo] = [Self.idSchemaField(ordinal: 0)]
            var columnIndex = 1

            // Parse and collect custom fields first
            var customFields: [(String, ConvexFieldType)] = []
            if let documentType = tableSchema["documentType"] as? [String: Any],
               let typeValue = documentType["value"] as? [String: Any] {
                
                // Parse custom fields and collect them
                for (fieldName, fieldInfo) in typeValue {
                    do {
                        let fieldType = try ConvexFieldType(from: fieldInfo as! [String: Any])
                        customFields.append((fieldName, fieldType))
                    } catch {
                        // Skip fields that can't be parsed
                        continue
                    }
                }
            }
            
            // Sort custom fields alphabetically by name
            customFields.sort { $0.0.localizedCompare($1.0) == .orderedAscending }
            
            // Add sorted custom fields
            for (fieldName, fieldType) in customFields {
                var constraints: [ConstraintInfo] = []
                var foreignKeyName: String = ""
                if fieldType.isForeignKey, let refTable = fieldType.referencedTableName {
                    let constraint = ConstraintInfo(
                        oid: 0,
                        name: "convex_fk_\(fieldName)_to_\(refTable)",
                        type: .foreignKey,
                        columns: [fieldName],
                        isDeferrable: false,
                        isDeferred: false,
                        definition: nil,
                        description: "References table \(refTable)",
                        referencedSchema: nil,
                        referencedTable: refTable,
                        referencedColumns: ["_id"],
                        onUpdate: nil,
                        onDelete: nil,
                        extensionName: nil
                    )
                    constraints.append(constraint)
                    foreignKeyName = constraint.name
                }
                columns.append(DatabaseSchemaInfo(
                    ordinalPosition: columnIndex,
                    columnName: fieldName,
                    dataType: fieldType.swiftTypeName,
                    formatType: fieldType.swiftTypeName,
                    typeOid: 0,
                    numericPrecision: nil,
                    datetimePrecision: nil,
                    numericScale: nil,
                    dataLength: nil,
                    isNullable: fieldType.optional ? "YES" : "NO",
                    foreignKey: foreignKeyName,
                    constraints: constraints,
                    comment: nil
                ))
                columnIndex += 1
            }
            
            columns.append(Self.creationTimeSchemaField(ordinal: columnIndex))

            return DatabaseSchemaResult(
                tableName: collectionName,
                schemaName: schema ?? "default",
                columns: columns,
                totalCount: columns.count
            )
        } catch {
            debugLog("⚠️ Failed to get schema from Convex: \(error)")
            return nil
        }
    }

    private func cachedTableSchema(for tableName: String, schema: String?) -> [String: Any]? {
        let schemas = cachedSchemas(for: schema)
        guard let schemas,
              let activeString = schemas["active"] as? String,
              let data = activeString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tables = parsed["tables"] as? [[String: Any]] else { return nil }
        return tables.first { ($0["tableName"] as? String) == tableName }
    }

    func getIndexes(for collectionName: String, schema: String?) async throws -> [DatabaseIndexInfo] {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }
        
        let schema = normalizedSchemaName(schema)

        if schema != "app", getComponentId(for: schema) == nil {
            await ensureComponentsLoaded()
        }

        return try await wrapConvexError("query") {
            let args: [String: ConvexEncodable?] = [
                "tableName": collectionName,
                "tableNamespace": getComponentId(for: schema)
            ]

            let response: ConvexMobile.ConvexValue = try await mobileClient.query(name: "_system/frontend/indexes", with: args)

            guard let indexes = response.anyValue as? [[String: Any]] else {
                return []
            }

            return indexes.compactMap { indexDict in
                mapConvexIndexToDatabaseIndexInfo(indexDict, collectionName: collectionName, schemaName: schema)
            }
        }
    }

    // MARK: - Index Mapping Helper

    private func mapConvexIndexToDatabaseIndexInfo(
        _ indexDict: [String: Any],
        collectionName: String,
        schemaName: String
    ) -> DatabaseIndexInfo? {
        guard let indexName = indexDict["name"] as? String else { return nil }

        // Parse fields (can be array or object)
        var columns: [String] = []
        var indexType: IndexType = .btree
        var includeColumns: [String]? = nil

        if let fieldsArray = indexDict["fields"] as? [String] {
            // Regular index: ["field1", "field2"]
            columns = fieldsArray
            indexType = .btree

        } else if let fieldsDict = indexDict["fields"] as? [String: Any] {
            // Search or Vector index
            if let searchField = fieldsDict["searchField"] as? String {
                columns = [searchField]
                indexType = .fulltext
                includeColumns = fieldsDict["filterFields"] as? [String]

            } else if let vectorField = fieldsDict["vectorField"] as? String {
                columns = [vectorField]
                indexType = .other
                includeColumns = fieldsDict["filterFields"] as? [String]
            }
        }

        // Build comment from backfill state
        var comment: String? = nil
        if let backfill = indexDict["backfill"] as? [String: Any],
           let state = backfill["state"] as? String {
            var commentParts: [String] = ["Backfill: \(state)"]

            // Add stats if available
            if let stats = backfill["stats"] as? [String: Any] {
                if let numDocsIndexed = stats["numDocsIndexed"] as? Int {
                    let totalDocs = stats["totalDocs"] as? Int
                    if let total = totalDocs {
                        commentParts.append("\(numDocsIndexed)/\(total) docs")
                    } else {
                        commentParts.append("\(numDocsIndexed) docs")
                    }
                }
            }

            comment = commentParts.joined(separator: ", ")
        }

        // Check if staged
        if let staged = indexDict["staged"] as? Bool, staged {
            comment = comment == nil ? "Staged" : "\(comment!), Staged"
        }

        return DatabaseIndexInfo(
            name: indexName,
            tableName: collectionName,
            schemaName: schemaName,
            columns: columns,
            indexType: indexType,
            isUnique: false,
            isPrimaryKey: indexName.contains("primary") || indexName.contains("by_id"),
            definition: nil,
            condition: nil,
            includeColumns: includeColumns,
            comment: comment
        )
    }

    // MARK: - Helper Methods

    private func makeDatabaseValue(from value: Any?) -> DatabaseValue? {
        guard let value, !(value is NSNull) else { return nil }
        if let databaseValue = DatabaseValue(value) {
            return databaseValue
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .double(number.doubleValue)
        }
        if let convertible = value as? any CustomStringConvertible {
            return .string(convertible.description)
        }
        return nil
    }

    func convertToConvexEncodable(_ value: DatabaseValue) -> ConvexEncodable? {
        switch value {
        case .null:
            nil
        case .bool(let value):
            value
        case .int(let value):
            abs(value) > Int32.max ? Int64(value) : Double(value)
        case .int64(let value):
            value
        case .double(let value):
            value
        case .string(let value), .decimalString(let value), .objectID(let value):
            value
        case .date(let value):
            value.formatted(.iso8601)
        case .data(let value):
            value.base64EncodedString()
        case .uuid(let value):
            value.uuidString
        case .array(let values):
            values.map { convertToConvexEncodable($0) }
        case .object(let values):
            values.mapValues { convertToConvexEncodable($0) }
        }
    }
    
    func convertToConvexEncodable(_ value: Any?) -> ConvexEncodable? {
        guard let value = value else { return nil }
        
        switch value {
        case let value as DatabaseValue:
            return convertToConvexEncodable(value)
        case let string as String:
            // Try to convert numeric strings to actual numbers
            // First check if it's a large integer (potential bigint)
            if let int64Value = Int64(string) {
                // If it's a very large number, keep it as Int64 for bigint compatibility
                if abs(int64Value) > Int32.max {
                    return int64Value
                }
                // For smaller numbers, convert to Double for float64 compatibility
                return Double(int64Value)
            }
            
            // Try parsing boolean strings
            if string.lowercased() == "true" {
                return true
            }
            if string.lowercased() == "false" {
                return false
            }
            
            // Try parsing as Double for decimal numbers
            if let doubleValue = Double(string) {
                return doubleValue
            }
            
            // Try to parse JSON strings back into objects/arrays
            if string.hasPrefix("{") || string.hasPrefix("[") {
                do {
                    if let jsonData = string.data(using: .utf8) {
                        let jsonObject = try Foundation.JSONSerialization.jsonObject(with: jsonData)
                        return convertToConvexEncodable(jsonObject)
                    }
                } catch {
                    debugLog("⚠️ Failed to parse JSON string: \(error)")
                }
            }
            
            return string
        case let number as NSNumber:
            // Check if it's a boolean
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            // Always prefer Double for NSNumber since Convex often uses float64
            return number.doubleValue
        case let bool as Bool:
            return bool
        case let int as Int:
            // For large integers that might be bigints, preserve as Int64
            if abs(int) > Int32.max {
                return Int64(int)
            }
            return Double(int)
        case let int32 as Int32:
            return int32
        case let int64 as Int64:
            // Keep Int64 values as Int64 for bigint fields, don't convert to Double
            return int64
        case let double as Double:
            return double
        case let float as Float:
            return float
        case let data as Data:
            // Convert Data to base64 string since Data is not ConvexEncodable
            return data.base64EncodedString()
        case let array as [Any]:
            // Keep as array structure for Convex - don't stringify complex arrays
            let convertedArray: [ConvexEncodable?] = array.compactMap { convertToConvexEncodable($0) }
            return convertedArray
        case let dict as [String: Any]:
            // Keep as object structure for Convex - don't stringify complex objects
            let convertedDict: [String: ConvexEncodable?] = dict.mapValues { convertToConvexEncodable($0) }
            return convertedDict
        default:
            // Convert unknown types to string
            return String(describing: value)
        }
    }
    

    // MARK: - Convex Error Handling

    private func extractConvexErrorMessage(from error: ClientError) -> String {
        switch error {
        case .ConvexError(let data):
            if let payload = data.data(using: .utf8),
               let message = try? Foundation.JSONDecoder().decode(String.self, from: payload) {
                return message
            }
            return data
        case .ServerError(let msg), .InternalError(let msg):
            var cleaned = msg
            // Strip "[Request ID: xxx] Server Error\n" prefix
            if let newlineRange = cleaned.range(of: "\n") {
                cleaned = String(cleaned[newlineRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Strip "Uncaught Error: " prefix
            if cleaned.hasPrefix("Uncaught Error: ") {
                cleaned = String(cleaned.dropFirst("Uncaught Error: ".count))
            }
            return cleaned
        }
    }

    private func wrapConvexError<T>(_ operation: String, body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as ClientError {
            throw DatabaseError.operationFailed(extractConvexErrorMessage(from: error))
        }
    }

    /// Builds a componentId-keyed arg dict locally (no capture of non-Sendable
    /// existentials), so it can be safely constructed inside concurrent child
    /// tasks under Swift 6 strict concurrency.
    nonisolated private static func schemaQueryArgs(componentId: String?) -> [String: ConvexEncodable?] {
        guard let componentId, !componentId.isEmpty else { return [:] }
        return ["componentId": componentId]
    }

    // MARK: - Filter Encoding

    private func encodeFilterToBase64(rawFilterJSON: String?, order: String?, defaultOrder: String? = nil) throws -> String {
        if let rawFilterJSON, !rawFilterJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                var payload: [String: Any]
                if let data = rawFilterJSON.data(using: .utf8),
                   let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    payload = parsed
                } else {
                    payload = ["clauses": []]
                }
                if let order { payload["order"] = order }
                else if let defaultOrder, payload["order"] == nil { payload["order"] = defaultOrder }
                let dataOut = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes, .sortedKeys])
                return String(data: dataOut, encoding: .utf8).map { Data($0.utf8).base64EncodedString() }
                    ?? Data(rawFilterJSON.utf8).base64EncodedString()
            } catch {
                return Data(rawFilterJSON.utf8).base64EncodedString()
            }
        } else {
            var payload: [String: Any] = ["clauses": []]
            if let order { payload["order"] = order }
            else if let defaultOrder { payload["order"] = defaultOrder }
            let dataOut = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes, .sortedKeys])
            let jsonString = String(data: dataOut, encoding: .utf8) ?? "{\"clauses\":[]}"
            return Data(jsonString.utf8).base64EncodedString()
        }
    }

    // MARK: - Document ID Conversion

    private func documentId(from id: DatabaseValue) -> String {
        id.stringValue ?? id.description
    }

    // MARK: - System Schema Fields

    private static func idSchemaField(ordinal: Int) -> DatabaseSchemaInfo {
        DatabaseSchemaInfo(
            ordinalPosition: ordinal,
            columnName: "_id",
            dataType: "id",
            formatType: "id",
            typeOid: 0,
            numericPrecision: nil,
            datetimePrecision: nil,
            numericScale: nil,
            dataLength: nil,
            isNullable: "NO",
            comment: "Convex document ID",
            isReadOnly: true
        )
    }

    private static func creationTimeSchemaField(ordinal: Int) -> DatabaseSchemaInfo {
        DatabaseSchemaInfo(
            ordinalPosition: ordinal,
            columnName: "_creationTime",
            dataType: "int64",
            formatType: "int64",
            typeOid: 0,
            numericPrecision: nil,
            datetimePrecision: nil,
            numericScale: nil,
            dataLength: nil,
            isNullable: "NO",
            comment: "Document creation timestamp",
            isReadOnly: true
        )
    }

    // MARK: - Schema Caching

    /// Best-effort warm-up of the caches that gate the table-open hot path.
    /// Runs after connect() / switchDatabase() and swallows errors — if it fails,
    /// the lazy fetch paths still work, just without the pre-warm benefit.
    private func prefetchAfterConnect() async {
        guard isConnected, convexMobileClient != nil else { return }
        async let components: Void = prefetchComponentMapping()
        async let appSchemas: Void = prefetchAppSchemas()
        _ = await components
        _ = await appSchemas
    }

    private func prefetchComponentMapping() async {
        await ensureComponentsLoaded()
    }

    /// Collapses concurrent `getInformationSchema` calls into a single in-flight
    /// request, and short-circuits once the component mapping has been loaded.
    private func ensureComponentsLoaded() async {
        if componentsLoaded { return }
        if let existing = componentsFetchTask {
            await existing.value
            return
        }
        let task = Task {
            _ = try? await self.getInformationSchema()
            self.markComponentsLoaded()
        }
        componentsFetchTask = task
        await task.value
    }

    private func markComponentsLoaded() {
        componentsLoaded = true
        componentsFetchTask = nil
    }

    private func prefetchAppSchemas() async {
        _ = try? await getAllSchemas(for: "app")
    }

    private func getAllSchemas(for schema: String?) async throws -> [String: Any] {
        let effectiveSchema = normalizedSchemaName(schema)
        let cached = cachedSchemas(for: effectiveSchema)
        if let cached { return cached }

        // Fetch fresh schemas
        guard let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("No mobile client available")
        }

        var args: [String: ConvexEncodable?] = [:]
        if effectiveSchema != "app" {
            if getComponentId(for: effectiveSchema) == nil {
                await ensureComponentsLoaded()
            }
            if let componentId = getComponentId(for: effectiveSchema), !componentId.isEmpty {
                args["componentId"] = componentId
            }
        }

        let schemas: ConvexMobile.ConvexValue = try await mobileClient.query(name: "_system/frontend/getSchemas", with: args)

        // Cache the result
        let result = schemas.anyValue as? [String: Any]
        if let result {
            setCachedSchemas(result, for: effectiveSchema)
        }

        return result ?? [:]
    }
    
    
    func getInformationSchema() async throws -> [InformationSchema] {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }

        do {
            let response: ConvexMobile.ConvexValue = try await mobileClient.query(name: "_system/frontend/components:list", with: [:])

            // Extract the components array from the response
            let components: [[String: Any]]
            if let arr = response.arrayValue {
                components = arr.compactMap { $0.anyValue as? [String: Any] }
            } else if response.objectValue != nil {
                if let value = response["value"]?.arrayValue {
                    components = value.compactMap { $0.anyValue as? [String: Any] }
                } else if let comps = response["components"]?.arrayValue {
                    components = comps.compactMap { $0.anyValue as? [String: Any] }
                } else {
                    throw DatabaseError.operationFailed("Invalid components response format")
                }
            } else {
                throw DatabaseError.operationFailed("Response is neither an object nor an array")
            }

            // Convert each component to InformationSchema and store ID mapping
            let informationSchemas = components.compactMap { component -> InformationSchema? in
                let pathValue = component["path"] as? String
                let path = (pathValue?.isEmpty == false) ? pathValue! : "app"

                // Store the component ID mapping safely using the original path
                if let componentIdValue = component["id"] {
                    let componentId = String(describing: componentIdValue)
                    componentIdMapping[path] = componentId
                }

                return InformationSchema(name: path)
            }

            // If no components found, return default "app" component
            return informationSchemas.isEmpty ? [InformationSchema(name: "app")] : informationSchemas
        } catch {
            // If query fails, return default "app" component
            return [InformationSchema(name: "app")]
        }
    }
    
    // MARK: - Collection Management
    
    func createCollection(named collectionName: String) async throws {
        throw DatabaseError.notImplemented("Collection management not yet implemented for Convex")
    }
    
    func renameCollection(databaseSchema: String?, from oldName: String, to newName: String) async throws {
        throw DatabaseError.notImplemented("Collection management not yet implemented for Convex")
    }
    
    func deleteCollection(named collectionName: String, databaseSchema: String?) async throws {
        throw DatabaseError.notImplemented("Collection management not yet implemented for Convex")
    }
    
    // MARK: - AI Functions
    
    func buildSystemPrompt(for collectionName: String, databaseSchema: String?) async throws -> String {
        let currentDate = Date().formatted(.iso8601)
        let schemaPrompt = await buildBrowseSchemaPrompt(for: collectionName, schema: databaseSchema)
        let indexPrompt = await buildBrowseIndexPrompt(for: collectionName, schema: databaseSchema)
        let componentName = databaseSchema ?? "app"

        return """
        You are a Convex query assistant for a desktop database client's floating action bar. Your output is inserted directly into the table query field and executed as-is through Convex's JavaScript query path, so respond with only JavaScript as plain text. Never include explanations, markdown formatting, or code fences.

        <current_table>
        \(collectionName)
        </current_table>

        <current_component>
        \(componentName)
        </current_component>

        <table_schema>
        \(schemaPrompt)
        </table_schema>

        <available_indexes>
        \(indexPrompt)
        </available_indexes>

        <instructions>
        1. Always return a read-only Convex JavaScript query in this exact shape:
           export default query({
             handler: async (ctx) => {
               return await ctx.db.query("tableName").collect();
             },
           })
        2. Use the current table `\(collectionName)` as the base query. Do not switch the primary table.
        3. Queries are read-only. Never return mutations or actions.
        4. Prefer `.withIndex(...)` when the request matches one of the available indexes. Otherwise use `.filter(...)`.
        5. Use Convex query APIs only: `ctx.db.query("table")`, `ctx.db.get(id)`, `.withIndex(...)`, `.filter(...)`, `.order("asc" | "desc")`, `.collect()`, `.take(n)`, `.first()`, and normal JavaScript transforms after `collect()`.
        6. For "newest", "latest", or "most recent", use `.order("desc")`.
        7. For "oldest" or ascending requests, use `.order("asc")`.
        8. Return arrays of objects for best table rendering.
        9. Do not include imports; the runtime adds the Convex wrapper import automatically.
        10. Preserve the `export default query({ ... })` format exactly.
        </instructions>

        <examples>
        <example>
        <input>show all \(collectionName)</input>
        <output>
        export default query({
          handler: async (ctx) => {
            return await ctx.db.query("\(collectionName)").collect();
          },
        })
        </output>
        </example>

        <example>
        <input>show the 10 most recent \(collectionName)</input>
        <output>
        export default query({
          handler: async (ctx) => {
            return await ctx.db.query("\(collectionName)").order("desc").take(10);
          },
        })
        </output>
        </example>

        <example>
        <input>show \(collectionName) where status is active</input>
        <output>
        export default query({
          handler: async (ctx) => {
            return await ctx.db
              .query("\(collectionName)")
              .filter((q) => q.eq(q.field("status"), "active"))
              .collect();
          },
        })
        </output>
        </example>

        <example>
        <input>show \(collectionName) where amount is greater than 100</input>
        <output>
        export default query({
          handler: async (ctx) => {
            return await ctx.db
              .query("\(collectionName)")
              .filter((q) => q.gt(q.field("amount"), 100))
              .collect();
          },
        })
        </output>
        </example>
        </examples>

        Current Date: \(currentDate)
        """
    }

    private func buildBrowseSchemaPrompt(for collectionName: String, schema: String?) async -> String {
        do {
            guard let schemaResult = try await getSchema(for: collectionName, schema: schema),
                  !schemaResult.columns.isEmpty else {
                return "No schema metadata available. Prefer fields that already appear in the current table."
            }

            let lines = schemaResult.columns.map { column in
                let nullable = column.isNullable == "YES" ? "optional" : "required"
                let foreignKey = column.foreignKey.isEmpty ? "" : " [FK]"
                return "- \(column.columnName): \(column.dataType), \(nullable)\(foreignKey)"
            }
            return lines.joined(separator: "\n")
        } catch {
            return "Schema lookup failed: \(error.localizedDescription)"
        }
    }

    private func buildBrowseIndexPrompt(for collectionName: String, schema: String?) async -> String {
        do {
            let indexes = try await getIndexes(for: collectionName, schema: schema)
            guard !indexes.isEmpty else { return "No index metadata available." }

            let lines = indexes.map { index in
                let columns = index.columns.isEmpty ? "unknown fields" : index.columns.joined(separator: ", ")
                return "- \(index.name): \(columns)"
            }
            return lines.joined(separator: "\n")
        } catch {
            return "Index lookup failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Real-time Subscription
    func subscribeToCollectionChanges(
        collectionName: String,
        databaseSchema: String?,
        filter: String?,
        limit: Int,
        sortBy: String?,
        ascending: Bool?,
        page: Int?,
        onUpdate: @escaping @Sendable (QueryResult) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        guard isConnected, let mobileClient = convexMobileClient else {
            throw DatabaseError.connectionFailed("Not connected to Convex or no mobile client available")
        }

        let orderString = ascending.map { $0 ? "asc" : "desc" }
        let filtersBase64 = try encodeFilterToBase64(
            rawFilterJSON: filter,
            order: orderString,
            defaultOrder: "desc"
        )

        let requestedPage = page ?? 1
        let cursorForPage = self.tablePageCursors[collectionName]?[filtersBase64]?[requestedPage] ?? nil

        var args: [String: ConvexEncodable?] = [
            "table": collectionName,
            "filters": filtersBase64,
            "paginationOpts": ["cursor": cursorForPage, "numItems": Float(limit)] as [String: ConvexEncodable?],
        ]
        if let databaseSchema, let componentId = getComponentId(for: databaseSchema) {
            args["componentId"] = componentId
        }

        debugLog("🛰️ Subscribing to _system/frontend/paginatedTableDocuments for table: \(collectionName)")

        // Clear any stale dedup hash from a previous subscription on the same
        // table so the new subscription's first event isn't mistaken for a
        // duplicate (which would leave the view stuck on .loading).
        lastSubscriptionPayloadHash.removeValue(forKey: collectionName)

        // Create subscription using ConvexValue to handle arbitrary JSON objects
        let subscription = mobileClient.subscribe(
            to: "_system/frontend/paginatedTableDocuments",
            with: args,
            yielding: ConvexMobile.ConvexValue.self
        )

        // Handle subscription updates inline so Task cancellation propagates
        do {
            for try await convexValue in subscription.values {
                if Task.isCancelled { break }

                // Check if this payload is identical to the last one to avoid processing duplicates
                let payloadHash = String(convexValue.description.hashValue)
                if let lastHash = lastSubscriptionPayloadHash[collectionName], lastHash == payloadHash {
                    debugLog("🔄 Skipping duplicate subscription payload for table: \(collectionName)")
                    continue
                }
                lastSubscriptionPayloadHash[collectionName] = payloadHash

                debugLog("📥 Subscription event received for table: \(collectionName)")
                do {
                    // Unwrap { status, value } envelope if present
                    let json: ConvexMobile.ConvexValue = convexValue["value"] ?? convexValue

                    guard let jsonObj = json.objectValue, !jsonObj.isEmpty else {
                        debugLog("❌ Subscription payload is not an object: \(convexValue)")
                        continue
                    }

                    // Store continueCursor for next page under current filter signature
                    if let continueCursor = json["continueCursor"]?.stringValue {
                        var filterMap = self.tablePageCursors[collectionName] ?? [:]
                        var pageMap = filterMap[filtersBase64] ?? [:]
                        if pageMap[requestedPage] == nil && requestedPage == 1 { pageMap[1] = nil }
                        pageMap[requestedPage + 1] = continueCursor
                        filterMap[filtersBase64] = pageMap
                        self.tablePageCursors[collectionName] = filterMap
                        debugLog("📡 Stored subscription cursor for table=\(collectionName) page=\(requestedPage + 1)")
                    }

                    guard let jsonResult = json.anyValue as? [String: Any] else {
                        debugLog("❌ Subscription payload could not be converted to dictionary")
                        continue
                    }
                    let queryResult = try await self.transformConvexResultToQueryResult(
                        jsonResult,
                        for: collectionName,
                        databaseSchema: databaseSchema
                    )
                    await MainActor.run { onUpdate(queryResult) }
                } catch {
                    debugLog("❌ Failed to process subscription payload: \(error)")
                    await MainActor.run { onError(error) }
                }
            }
            debugLog("ℹ️ Subscription completed for table: \(collectionName)")
        } catch let error as ClientError {
            switch error {
            case .ConvexError(let data):
                if let payloadData = data.data(using: .utf8),
                   let message = String(data: payloadData, encoding: .utf8) {
                    debugLog("❌ Convex subscription ConvexError: \(message)")
                } else {
                    debugLog("❌ Convex subscription ConvexError (unparseable): \(data)")
                }
                await MainActor.run { onError(DatabaseError.operationFailed(data)) }
            case .ServerError(let msg):
                debugLog("❌ Convex subscription ServerError: \(msg)")
                await MainActor.run { onError(DatabaseError.operationFailed(msg)) }
            case .InternalError(let msg):
                debugLog("❌ Convex subscription InternalError: \(msg)")
                await MainActor.run { onError(DatabaseError.operationFailed(msg)) }
            @unknown default:
                debugLog("❌ Convex subscription unknown ClientError: \(error)")
                await MainActor.run { onError(error) }
            }
        } catch is CancellationError {
            debugLog("🛑 Subscription cancelled for table: \(collectionName)")
        } catch {
            debugLog("❌ Subscription error (type=\(type(of: error))): \(error)")
            await MainActor.run { onError(error) }
        }
    }
    
    // MARK: - Shared Document Processing
    
    private func processConvexDocuments(_ documents: [[String: Any]], totalCount: Int, for tableName: String, databaseSchema: String?) async throws -> QueryResult {
        var columns: [QueryColumnInfo] = []

        if let tableSchema = cachedTableSchema(for: tableName, schema: databaseSchema),
           let documentType = tableSchema["documentType"] as? [String: Any],
           let typeValue = documentType["value"] as? [String: Any] {
            // Build columns from cached schema
            columns.append(QueryColumnInfo(name: "_id", dataType: "string", format: "id", index: 0))
            var idx = 1
            for fieldName in typeValue.keys.sorted() {
                let fieldType: String
                if let dict = typeValue[fieldName] as? [String: Any],
                   let parsed = try? ConvexFieldType(from: dict) {
                    fieldType = parsed.swiftTypeName
                } else {
                    fieldType = "string"
                }
                columns.append(QueryColumnInfo(name: fieldName, dataType: fieldType, format: fieldType, index: idx))
                idx += 1
            }
            columns.append(QueryColumnInfo(name: "_creationTime", dataType: "float64", format: "timestamp", index: idx))
        } else {
            // No schema — convertArbitraryToQueryResult already builds complete columns + rows
            return convertArbitraryToQueryResult(documents)
        }

        // Convert documents to rows using schema types
        var rows: [[String: QueryRowInfo]] = []
        var rawRows: [DatabaseRawRow] = []
        rows.reserveCapacity(documents.count)
        rawRows.reserveCapacity(documents.count)

        for document in documents {
            var row = [String: QueryRowInfo](minimumCapacity: columns.count)
            var rawRow = DatabaseRawRow(minimumCapacity: columns.count)

            for column in columns {
                let key = column.name
                let value = document[key]
                let dataType = column.dataType
                let formatType = column.format ?? dataType

                row[key] = QueryRowInfo(
                    value: ConvexValue.formatValueForDisplay(value: value, fieldName: key, dataType: dataType),
                    dataType: dataType,
                    format: formatType
                )
                rawRow[key] = makeDatabaseValue(from: value)
            }

            rows.append(row)
            rawRows.append(rawRow)
        }

        return QueryResult(
            columns: columns,
            rows: rows,
            totalCount: totalCount,
            rawRows: rawRows
        )
    }

    private func transformConvexResultToQueryResult(
        _ convexResult: [String: Any],
        for tableName: String,
        databaseSchema: String?
    ) async throws -> QueryResult {
        // Parse the Convex response
        guard let page = convexResult["page"] as? [[String: Any]] else {
            throw DatabaseError.operationFailed("Invalid subscription response format")
        }
        
        let documents = page
        let totalCount = convexResult["totalCount"] as? Int ?? documents.count
        
        // Use the shared processing function
        return try await processConvexDocuments(
            documents,
            totalCount: totalCount,
            for: tableName,
            databaseSchema: databaseSchema
        )
    }

    private func applyClientSideWindow(to result: QueryResult, skip: Int, limit: Int, sortBy: String?, ascending: Bool?) -> QueryResult {
        var entries = Array(zip(result.rows, result.rawRows))

        if let sortBy, let ascending {
            entries.sort { lhs, rhs in
                Self.compareDatabaseValues(lhs.1[sortBy] ?? nil, rhs.1[sortBy] ?? nil, ascending: ascending)
            }
        }

        let totalCount = max(result.totalCount, entries.count)
        let start = min(max(skip, 0), entries.count)
        let end = limit > 0 ? min(start + limit, entries.count) : entries.count
        let window = Array(entries[start..<end])

        return QueryResult(
            columns: result.columns,
            rows: window.map { $0.0 },
            totalCount: totalCount,
            rawRows: window.map { $0.1 }
        )
    }

    nonisolated private static func compareDatabaseValues(_ lhs: DatabaseValue?, _ rhs: DatabaseValue?, ascending: Bool) -> Bool {
        let ordering = compareDatabaseValues(lhs, rhs)
        if ordering == .orderedSame {
            return false
        }
        return ascending ? ordering == .orderedAscending : ordering == .orderedDescending
    }

    nonisolated private static func compareDatabaseValues(_ lhs: DatabaseValue?, _ rhs: DatabaseValue?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        default:
            break
        }

        if let lhsNumber = numericSortValue(lhs), let rhsNumber = numericSortValue(rhs) {
            if lhsNumber < rhsNumber { return .orderedAscending }
            if lhsNumber > rhsNumber { return .orderedDescending }
            return .orderedSame
        }

        switch (lhs, rhs) {
        case (.bool(let lhsValue), .bool(let rhsValue)):
            if lhsValue == rhsValue { return .orderedSame }
            return lhsValue ? .orderedDescending : .orderedAscending
        case (.date(let lhsValue), .date(let rhsValue)):
            if lhsValue < rhsValue { return .orderedAscending }
            if lhsValue > rhsValue { return .orderedDescending }
            return .orderedSame
        default:
            let lhsString = lhs?.description ?? ""
            let rhsString = rhs?.description ?? ""
            return lhsString.localizedStandardCompare(rhsString)
        }
    }

    nonisolated private static func numericSortValue(_ value: DatabaseValue?) -> Double? {
        switch value {
        case .int(let intValue):
            return Double(intValue)
        case .int64(let intValue):
            return Double(intValue)
        case .double(let doubleValue):
            return doubleValue
        case .decimalString(let decimalValue):
            return Double(decimalValue)
        case .string(let stringValue):
            return Double(stringValue)
        default:
            return nil
        }
    }

    // Clear subscription payload hash for a specific table (called when subscription is cancelled)
    func clearSubscriptionCache(for tableName: String) async {
        lastSubscriptionPayloadHash.removeValue(forKey: tableName)
        debugLog("🧹 Cleared subscription cache for table: \(tableName)")
    }

    // Clear schema cache (protocol conformance)
    func clearSchemaCache(for tableName: String, schema: String?) async {
        clearCachedSchemas(for: schema)
    }

}


extension ConvexDriver {
    // MARK: - Embedded Token Metadata
    struct EmbeddedDeployment: Codable {
        let name: String
        let deploymentType: String
        let projectId: Int64
        let deploymentId: String
    }
    
    struct EmbeddedMeta: Codable {
        let projectId: Int64
        let teamName: String?
        let projectName: String?
        let deployments: [EmbeddedDeployment]?
    }

    /// Rebuilds the embedded token with current deployments for keychain persistence.
    func buildUpdatedEmbeddedToken() async -> String? {
        guard let deployKey = accessToken, let projectId = projectId else { return nil }
        let embeddedDeployments = deployments.map { dep in
            EmbeddedDeployment(
                name: dep.name,
                deploymentType: dep.deploymentType,
                projectId: dep.projectId,
                deploymentId: String(dep.deploymentUrl.replacing("https://", with: "").replacing(".convex.cloud", with: ""))
            )
        }
        let meta = EmbeddedMeta(
            projectId: projectId,
            teamName: teamName,
            projectName: projectName,
            deployments: embeddedDeployments.isEmpty ? nil : embeddedDeployments
        )
        guard let data = try? Foundation.JSONEncoder().encode(meta) else { return nil }
        return deployKey + "|m=" + data.base64EncodedString()
    }

    // MARK: - URI Parsing
    private func parseTargetDatabase(from uri: String) -> String? {
        // Parse fragment like "#target=Production" from the URI
        guard let fragmentRange = uri.range(of: "#target=") else { return nil }
        let fragment = String(uri[fragmentRange.upperBound...])

        // Handle additional parameters by taking only up to the next &
        let targetDatabase = fragment.components(separatedBy: "&").first
        return targetDatabase?.isEmpty == false ? targetDatabase : nil
    }
    
    func parseDeployKeyAndMeta(from raw: String) -> (deployKey: String, meta: EmbeddedMeta?) {
        // Expected format: "<deployKey>|m=<base64(json)>". The deploy key itself can contain '|',
        // so we must split on the LAST occurrence of "|m=" and keep everything before it intact.
        guard let metaRange = raw.range(of: "|m=", options: .backwards) else {
            return (raw, nil)
        }

        let deployKey = String(raw[..<metaRange.lowerBound])
        let base64 = String(raw[metaRange.upperBound...])

        guard let data = decodeBase64Flexible(base64) else {
            return (deployKey, nil)
        }

        do {
            let meta = try Foundation.JSONDecoder().decode(EmbeddedMeta.self, from: data)
            return (deployKey, meta)
        } catch {
            // Failed to decode metadata, return raw deploy key
        }

        return (deployKey, nil)
    }

    // Accept both standard base64 and URL-safe base64, auto-padding as needed
    private func decodeBase64Flexible(_ s: String) -> Data? {
        if let data = Data(base64Encoded: s) { return data }
        let urlSafe = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let paddingNeeded = (4 - urlSafe.count % 4) % 4
        let padded = urlSafe + String(repeating: "=", count: paddingNeeded)
        return Data(base64Encoded: padded)
    }
}
