import SwiftUI

struct ChartDataPoint: Identifiable {
    let id: String
    let x: String
    let y: Double
    var series: String

    init(x: String, y: Double, series: String = "", id: String? = nil) {
        self.x = x
        self.y = y
        self.series = series
        self.id = id ?? "\(x)\u{1F}\(series)"
    }

    var truncatedX: String {
        x.count > 16 ? String(x.prefix(14)) + "…" : x
    }

    static let seriesPalette: [Color] = [
        AccentColor.coral.color,
        AccentColor.ocean.color,
        AccentColor.purple.color,
        AccentColor.ruby.color,
        AccentColor.emerald.color,
        AccentColor.amber.color,
        AccentColor.teal.color,
        AccentColor.indigo.color,
        AccentColor.magenta.color,
        AccentColor.lime.color,
        AccentColor.azure.color,
        AccentColor.crimson.color,
        AccentColor.violet.color,
        AccentColor.mint.color,
        AccentColor.gold.color,
    ]

    static func hasMultipleSeries(_ data: [ChartDataPoint]) -> Bool {
        Set(data.lazy.map(\.series)).count > 1
    }

    static func seriesNames(_ data: [ChartDataPoint]) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        for point in data {
            if seen.insert(point.series).inserted {
                ordered.append(point.series)
            }
        }
        return ordered
    }

    static func normalized(_ data: [ChartDataPoint]) -> [ChartDataPoint] {
        let filled = fillMissingSeries(data)
        var totalByX: [String: Double] = [:]
        for point in filled {
            totalByX[point.x, default: 0] += point.y
        }
        return filled.map { point in
            let total = totalByX[point.x] ?? 1
            return ChartDataPoint(x: point.x, y: total > 0 ? point.y / total : 0, series: point.series, id: point.id)
        }
    }

    /// Disambiguates duplicate (x, series) pairs so identities stay unique yet
    /// deterministic across recomputations.
    static func uniquelyIdentified(_ data: [ChartDataPoint]) -> [ChartDataPoint] {
        var counts: [String: Int] = [:]
        return data.map { point in
            let occurrence = counts[point.id, default: 0]
            counts[point.id] = occurrence + 1
            guard occurrence > 0 else { return point }
            return ChartDataPoint(x: point.x, y: point.y, series: point.series, id: "\(point.id)\u{1F}\(occurrence)")
        }
    }

    /// First index of each x value, for O(1) axis-label lookup.
    static func indexByX(_ data: [ChartDataPoint]) -> [String: Int] {
        var indices: [String: Int] = [:]
        for (index, point) in data.enumerated() where indices[point.x] == nil {
            indices[point.x] = index
        }
        return indices
    }

    static func fillMissingSeries(_ data: [ChartDataPoint]) -> [ChartDataPoint] {
        var orderedX: [String] = []
        var seenX: Set<String> = []
        for point in data {
            if seenX.insert(point.x).inserted {
                orderedX.append(point.x)
            }
        }
        let allSeries = seriesNames(data)
        var existing: Set<String> = []
        for point in data {
            existing.insert("\(point.x)\u{0}\(point.series)")
        }
        var result = data
        for x in orderedX {
            for s in allSeries {
                if !existing.contains("\(x)\u{0}\(s)") {
                    result.append(ChartDataPoint(x: x, y: 0, series: s))
                }
            }
        }
        return result
    }

    static func xAxisStride(for data: [ChartDataPoint], availableWidth: CGFloat) -> Int {
        guard !data.isEmpty, availableWidth > 0 else { return 1 }
        let maxLabelChars = min(data.map(\.truncatedX.count).max() ?? 8, 16)
        let charWidth: CGFloat = 6.5
        let labelWidth = CGFloat(maxLabelChars) * charWidth + 16
        let maxLabels = max(1, Int(availableWidth / labelWidth))
        guard data.count > maxLabels else { return 1 }
        return Int(ceil(Double(data.count) / Double(maxLabels)))
    }
}

@Observable
@MainActor
final class ChartBlockViewModel {

    let block: NotebookBlock
    private weak var dataController: NotebookDataController?
    let session = ChartDriverSession()

    var config: ChartBlockConfig?

    // Table picker state
    var isShowingTablePicker = false
    var availableCollections: [any CollectionWrapper] = []
    var availableSchemas: [InformationSchema] = []
    var selectedPickerSchema: String?
    var previewResult: QueryResult?
    var isLoadingPreview = false

    // Environment/deployment state (Convex)
    var availableEnvironments: [String] = []
    var selectedEnvironment: String?

    var schemaResult: DatabaseSchemaResult?

    // Chart state
    var chartData: [ChartDataPoint] = [] {
        didSet {
            let filled = ChartDataPoint.fillMissingSeries(chartData)
            seriesFilledChartData = filled
            normalizedChartData = ChartDataPoint.normalized(filled)
        }
    }
    // Derived once per data change so chart views don't recompute inside body.
    private(set) var normalizedChartData: [ChartDataPoint] = []
    private(set) var seriesFilledChartData: [ChartDataPoint] = []
    var isLoadingChart = false
    var chartError: String?

    // Connection state
    var isConnecting = false
    var connectionError: String?

    private(set) var hasStartedLoading = false

    init(block: NotebookBlock, dataController: NotebookDataController) {
        self.block = block
        self.dataController = dataController
        self.config = block.chartConfig()
    }

    func loadDataIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true

        if dataController?.isDashboardPublished == true,
           let cached = block.cachedChartData() {
            chartData = ChartDataPoint.uniquelyIdentified(cached.toChartData())
            return
        }

        guard let cfg = config, !cfg.tableName.isEmpty else { return }
        if let queryBlockIdStr = cfg.sourceQueryBlockId,
           let queryBlockId = UUID(uuidString: queryBlockIdStr) {
            loadFromQuerySource(blockId: queryBlockId, cfg: cfg)
        } else {
            Task {
                await reconnectAndLoad(cfg)
            }
        }
    }

    // MARK: - Connection

    private func resolveConnectionUri(_ cfg: ChartBlockConfig) -> String? {
        dataController?.connections.first(where: { $0.keychainId == cfg.connectionKeychainId })?.connectionUri
    }

    func refreshQuerySourceSchema() {
        guard let cfg = config,
              let queryBlockIdStr = cfg.sourceQueryBlockId,
              let queryBlockId = UUID(uuidString: queryBlockIdStr),
              schemaResult == nil else { return }
        loadFromQuerySource(blockId: queryBlockId, cfg: cfg)
    }

    private func loadFromQuerySource(blockId: UUID, cfg: ChartBlockConfig) {
        guard let result = dataController?.queryResult(for: blockId) else {
            chartError = "Run the source query block first"
            return
        }

        schemaResult = DatabaseSchemaResult(
            tableName: cfg.tableName,
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

        if shouldFetchChart(for: cfg) {
            Task { await fetchChartData() }
        }
    }

    func reconnectAndRefresh() async {
        guard let cfg = config, !cfg.tableName.isEmpty else { return }
        if cfg.sourceQueryBlockId != nil {
            await fetchChartData()
        } else {
            await reconnectAndLoad(cfg)
        }
    }

    private func reconnectAndLoad(_ cfg: ChartBlockConfig) async {
        guard let dbType = DatabaseType(rawValue: cfg.databaseType),
              let uri = resolveConnectionUri(cfg) else { return }
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

            schemaResult = try await session.getSchema(tableName: cfg.tableName, schema: cfg.schemaName)
            if shouldFetchChart(for: cfg) {
                await fetchChartData()
            }
        } catch {
            chartError = error.localizedDescription
        }
    }

    private static let environmentCapableTypes: Set<DatabaseType> = [.convex]

    func connectToQuerySource(blockId: UUID, outputName: String) {
        guard let result = dataController?.queryResult(for: blockId) else {
            chartError = "Run the source query block first"
            return
        }

        let cfg = ChartBlockConfig(
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

        let draft = ChartBlockConfig(
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

                    if let firstTable = availableCollections.first {
                        confirmTableSelection(tableName: firstTable.name)
                    }
                }
            } else {
                if let defaultDb = connection.defaultDatabase, !defaultDb.isEmpty {
                    try? await session.switchDatabase(to: defaultDb)
                }

                try await loadSchemasAndCollections(databaseType: dbType, preferredSchema: nil)

                config = draft

                if let firstTable = availableCollections.first {
                    confirmTableSelection(tableName: firstTable.name)
                }
            }
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
        chartData = []
        chartError = nil

        if var cfg = config {
            cfg.databaseName = environmentName
            cfg.tableName = ""
            cfg.schemaName = nil
            cfg.fields = [:]
            cfg.fieldAggregations = [:]
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
        chartData = []
        chartError = nil
        if var cfg = config {
            cfg.tableName = ""
            cfg.schemaName = schema
            cfg.fields = [:]
            cfg.fieldAggregations = [:]
            config = cfg
            persistConfig()
        }
        do {
            availableCollections = try await session.listCollections(schema: schema)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadPreview(tableName: String) async {
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        do {
            previewResult = try await session.fetchTableData(
                tableName: tableName,
                schema: selectedPickerSchema,
                limit: 50
            )
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func confirmTableSelection(tableName: String) {
        guard var cfg = config else { return }
        cfg.tableName = tableName
        cfg.schemaName = selectedPickerSchema
        cfg.fields = [:]
        cfg.fieldAggregations = [:]
        config = cfg
        schemaResult = nil
        chartData = []
        chartError = nil
        isShowingTablePicker = false
        previewResult = nil
        persistConfig()
        Task { await loadSchemaForConfig() }
    }

    // MARK: - Schema

    private func loadSchemaForConfig() async {
        guard let cfg = config, !cfg.tableName.isEmpty else { return }
        do {
            schemaResult = try await session.getSchema(tableName: cfg.tableName, schema: cfg.schemaName)
        } catch {
            chartError = error.localizedDescription
        }
    }

    // MARK: - Column classification

    var measureColumns: [DatabaseSchemaInfo] {
        schemaResult?.columns.filter { isNumericType($0.dataType) } ?? []
    }

    var dimensionColumns: [DatabaseSchemaInfo] {
        schemaResult?.columns.filter { !isNumericType($0.dataType) } ?? []
    }

    func isNumericColumn(_ col: DatabaseSchemaInfo) -> Bool {
        isNumericType(col.dataType)
    }

    var validColumnNames: Set<String> {
        Set(schemaResult?.columns.map(\.columnName) ?? [])
    }

    func isFilterFieldValid(_ filter: ChartFilterCondition) -> Bool {
        validColumnNames.contains(filter.field)
    }

    // MARK: - Axis Config

    func setChartType(_ type: ChartBlockConfig.ChartType) {
        config?.chartType = type
        persistConfig()
    }

    func setFieldColumn(key: String, column: String) {
        config?.fields[key] = [column]
        if isMeasureFieldKey(key) {
            setDefaultAggregation(forField: key, column: column)
        }
        persistConfig()
        triggerFetchIfReady()
    }

    func addFieldColumn(key: String, column: String) {
        var current = config?.fields[key] ?? []
        guard !current.contains(column) else { return }
        current.append(column)
        config?.fields[key] = current
        if isMeasureFieldKey(key) {
            setDefaultAggregation(forField: key, column: column)
        }
        persistConfig()
        triggerFetchIfReady()
    }

    func removeFieldColumn(key: String, column: String) {
        var current = config?.fields[key] ?? []
        current.removeAll { $0 == column }
        config?.fields[key] = current.isEmpty ? nil : current
        var inner = config?.fieldAggregations[key] ?? [:]
        inner.removeValue(forKey: column)
        config?.fieldAggregations[key] = inner.isEmpty ? nil : inner
        persistConfig()
        triggerFetchIfReady()
    }

    func resetFields() {
        config?.fields = [:]
        config?.fieldAggregations = [:]
        chartData = []
        chartError = nil
        persistConfig()
    }

    // MARK: - Aggregation

    func setAggregation(_ agg: AggregationFunction, forField fieldKey: String, column: String) {
        config?.setAggregation(agg, forField: fieldKey, column: column)
        persistConfig()
        triggerFetchIfReady()
    }

    func resolvedAggregation(forField fieldKey: String, column: String) -> AggregationFunction {
        if let stored = config?.aggregation(forField: fieldKey, column: column) {
            return stored
        }
        let dataType = schemaResult?.columns.first(where: { $0.columnName == column })?.dataType ?? ""
        let chartType = config?.chartType ?? .groupedColumn
        return AggregationFunction.defaultAggregation(for: dataType, chartType: chartType)
    }

    private func isMeasureFieldKey(_ key: String) -> Bool {
        let definitions = config?.chartType.fieldDefinitions ?? []
        return definitions.first(where: { $0.key == key })?.isMeasureField ?? false
    }

    private func setDefaultAggregation(forField fieldKey: String, column: String) {
        let dataType = schemaResult?.columns.first(where: { $0.columnName == column })?.dataType ?? ""
        let chartType = config?.chartType ?? .groupedColumn
        let defaultAgg = AggregationFunction.defaultAggregation(for: dataType, chartType: chartType)
        config?.setAggregation(defaultAgg, forField: fieldKey, column: column)
    }

    private func triggerFetchIfReady() {
        guard shouldFetchChart(for: config) else { return }
        Task { await fetchChartData() }
    }

    private func shouldFetchChart(for config: ChartBlockConfig?) -> Bool {
        guard let cfg = config else { return false }

        switch cfg.chartType {
        case .histogram:
            return cfg.xAxisColumn != nil
        case .pivotTable:
            return false
        default:
            return cfg.xAxisColumn != nil && cfg.yAxisColumn != nil
        }
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

    // MARK: - Data Fetching

    func runChart() async {
        if let queryBlockIdStr = config?.sourceQueryBlockId,
           let queryBlockId = UUID(uuidString: queryBlockIdStr) {
            guard let queryViewModel = await dataController?.rerunQueryBlock(blockId: queryBlockId) else {
                chartError = "Run the source query block first"
                return
            }

            if let queryError = queryViewModel.queryError {
                chartError = queryError
                return
            }
        }

        await fetchChartData()
    }

    func fetchChartData() async {
        guard let cfg = config else {
            chartError = ChartBlockError.noAxesConfigured.localizedDescription
            return
        }

        guard let xCol = cfg.xAxisColumn else {
            chartError = "Select an X-axis to render chart"
            return
        }

        guard cfg.chartType == .histogram || cfg.yAxisColumn != nil else {
            chartError = ChartBlockError.noAxesConfigured.localizedDescription
            return
        }

        isLoadingChart = true
        chartError = nil
        defer { isLoadingChart = false }

        if let queryBlockIdStr = cfg.sourceQueryBlockId,
           let queryBlockId = UUID(uuidString: queryBlockIdStr) {
            guard let result = dataController?.queryResult(for: queryBlockId) else {
                chartError = "Run the source query block first"
                return
            }

            let points = chartPoints(from: result, config: cfg, xColumn: xCol)
            applyChartPoints(points)
            return
        }

        do {
            let effectiveLimit = min(cfg.rowLimit, 200)
            let validFilters = cfg.filters.filter { $0.isComplete && isFilterFieldValid($0) }

            if cfg.chartType == .histogram {
                let result = try await session.fetchTableData(
                    tableName: cfg.tableName,
                    schema: cfg.schemaName,
                    limit: effectiveLimit,
                    filters: validFilters
                )
                let points = chartPoints(from: result, config: cfg, xColumn: xCol)
                applyChartPoints(points)
                return
            }

            guard let yCol = cfg.yAxisColumn else {
                chartError = ChartBlockError.noAxesConfigured.localizedDescription
                return
            }

            let definitions = cfg.chartType.fieldDefinitions
            let dimensions = definitions
                .filter { !$0.isMeasureField }
                .flatMap { cfg.fields[$0.key] ?? [] }
            let measures: [(column: String, aggregation: AggregationFunction)] = definitions
                .filter(\.isMeasureField)
                .flatMap { def in
                    (cfg.fields[def.key] ?? []).map { col in
                        (column: col, aggregation: resolvedAggregation(forField: def.key, column: col))
                    }
                }

            let needsAggregation = !measures.isEmpty && !measures.allSatisfy { $0.aggregation == .none }

            if needsAggregation, !measures.isEmpty {
                let result = try await session.fetchAggregatedData(
                    tableName: cfg.tableName,
                    schema: cfg.schemaName,
                    dimensions: dimensions,
                    measures: measures,
                    limit: effectiveLimit,
                    filters: validFilters
                )
                var points: [ChartDataPoint] = []
                let multiSeries = measures.count > 1
                for row in result.rows {
                    guard let xRaw = row[xCol]?.value else { continue }
                    let xStr = chartLabel(for: xRaw)
                    for measure in measures {
                        let aliasCol = "\(measure.column)\(measure.aggregation.sqlAliasSuffix)"
                        let yInfo = row[aliasCol] ?? row[measure.column]
                        guard let yRaw = yInfo?.value,
                              let yNum = toDouble(yRaw) else { continue }
                        points.append(ChartDataPoint(
                            x: xStr,
                            y: yNum,
                            series: multiSeries ? measure.column : ""
                        ))
                    }
                }
                applyChartPoints(points)
            } else {
                let allYCols = cfg.fields["yAxis"] ?? [yCol]
                let result = try await session.fetchTableData(
                    tableName: cfg.tableName,
                    schema: cfg.schemaName,
                    limit: effectiveLimit,
                    filters: validFilters
                )
                var points: [ChartDataPoint] = []
                let multiSeries = allYCols.count > 1
                for row in result.rows {
                    guard let xRaw = row[xCol]?.value else { continue }
                    let xStr = chartLabel(for: xRaw)
                    for col in allYCols {
                        guard let yRaw = row[col]?.value,
                              let yNum = toDouble(yRaw) else { continue }
                        points.append(ChartDataPoint(
                            x: xStr,
                            y: yNum,
                            series: multiSeries ? col : ""
                        ))
                    }
                }
                applyChartPoints(points)
            }
        } catch {
            chartError = error.localizedDescription
        }
    }

    private func saveChartCache() {
        block.saveCachedResult(CachedChartData(from: chartData))
        dataController?.saveContext()
    }

    func reloadConfig() {
        config = block.chartConfig()
        hasStartedLoading = false
        availableCollections = []
        availableSchemas = []
        selectedPickerSchema = nil
        previewResult = nil
        availableEnvironments = []
        selectedEnvironment = nil
        schemaResult = nil
        chartError = nil

        guard let cfg = config else {
            chartData = []
            return
        }

        if let queryBlockIdStr = cfg.sourceQueryBlockId,
           let queryBlockId = UUID(uuidString: queryBlockIdStr) {
            hasStartedLoading = true
            loadFromQuerySource(blockId: queryBlockId, cfg: cfg)
            return
        }

        guard !cfg.tableName.isEmpty else {
            chartData = []
            return
        }

        hasStartedLoading = true
        Task { await reconnectAndLoad(cfg) }
    }

    // MARK: - Persistence

    private func persistConfig() {
        guard let cfg = config else { return }
        block.saveChartConfig(cfg)
        dataController?.updateBlock(block)
    }

    // MARK: - Cleanup

    func cleanup() async {
        await session.disconnect()
    }

    // MARK: - Helpers

    private func isNumericType(_ type: String) -> Bool {
        AggregationFunction.isNumericDataType(type)
    }

    private func chartPoints(from result: QueryResult, config: ChartBlockConfig, xColumn: String) -> [ChartDataPoint] {
        if config.chartType == .histogram {
            return histogramPoints(from: result, xColumn: xColumn)
        }

        let allYCols = config.fields["yAxis"] ?? config.yAxisColumn.map { [$0] } ?? []
        var points: [ChartDataPoint] = []
        let multiSeries = allYCols.count > 1

        for row in result.rows {
            guard let xRaw = row[xColumn]?.value else { continue }
            let xLabel = chartLabel(for: xRaw)

            for column in allYCols {
                guard let yRaw = row[column]?.value,
                      let yValue = toDouble(yRaw) else { continue }
                points.append(
                    ChartDataPoint(
                        x: xLabel,
                        y: yValue,
                        series: multiSeries ? column : ""
                    )
                )
            }
        }

        return points
    }

    private func histogramPoints(from result: QueryResult, xColumn: String) -> [ChartDataPoint] {
        var orderedLabels: [String] = []
        var counts: [String: Double] = [:]

        for row in result.rows {
            guard let xRaw = row[xColumn]?.value else { continue }
            let label = chartLabel(for: xRaw)
            if counts[label] == nil {
                orderedLabels.append(label)
            }
            counts[label, default: 0] += 1
        }

        return orderedLabels.map { label in
            ChartDataPoint(x: label, y: counts[label] ?? 0)
        }
    }

    private func applyChartPoints(_ points: [ChartDataPoint]) {
        chartData = ChartDataPoint.uniquelyIdentified(reduceChartData(points, maxPoints: 160))
        saveChartCache()
    }

    private func chartLabel(for value: Any) -> String {
        switch value {
        case let dbValue as DatabaseValue:
            dbValue.description
        default:
            String(describing: value)
        }
    }

    private func toDouble(_ value: Any) -> Double? {
        switch value {
        case let dbValue as DatabaseValue:
            return dbValue.doubleValue
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            return number.doubleValue
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        case let i as Int64:
            return Double(i)
        case let i as Int32:
            return Double(i)
        case let f as Float:
            return Double(f)
        case let s as String:
            return Double(s)
        case let d as Decimal:
            return NSDecimalNumber(decimal: d).doubleValue
        default:
            return nil
        }
    }

    private func reduceChartData(_ points: [ChartDataPoint], maxPoints: Int) -> [ChartDataPoint] {
        guard !points.isEmpty, maxPoints > 1 else { return points }

        var orderedXValues: [String] = []
        var seenX: Set<String> = []
        for point in points {
            if seenX.insert(point.x).inserted {
                orderedXValues.append(point.x)
            }
        }

        let seriesCount = max(1, Set(points.map(\.series)).count)
        let maxCategories = max(1, maxPoints / seriesCount)

        guard orderedXValues.count > maxCategories else { return points }

        let step = Double(orderedXValues.count - 1) / Double(maxCategories - 1)
        var keepX: Set<String> = []
        for i in 0..<maxCategories {
            let index = min(Int(Double(i) * step), orderedXValues.count - 1)
            keepX.insert(orderedXValues[index])
        }

        return points.filter { keepX.contains($0.x) }
    }
}
