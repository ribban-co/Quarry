import Foundation

struct ChartFilterCondition: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var field: String
    var filterOperator: ChartFilterOperator
    var value: String

    enum ChartFilterOperator: String, Codable, CaseIterable {
        case equals = "equals"
        case notEquals = "not equals"
        case greaterThan = "greater than"
        case greaterThanOrEquals = "greater or equals"
        case lessThan = "less than"
        case lessThanOrEquals = "less than or equals"
        case like = "like"
        case isNull = "is null"
        case isNotNull = "is not null"

        var displayName: String {
            switch self {
            case .equals: "Is equal to"
            case .notEquals: "Is not equal to"
            case .greaterThan: "Greater than"
            case .greaterThanOrEquals: "Greater or equal to"
            case .lessThan: "Less than"
            case .lessThanOrEquals: "Less than or equal to"
            case .like: "Contains"
            case .isNull: "Is empty"
            case .isNotNull: "Is not empty"
            }
        }

        var needsValue: Bool {
            switch self {
            case .isNull, .isNotNull: false
            default: true
            }
        }

        var sqlOperator: String {
            switch self {
            case .equals: "="
            case .notEquals: "!="
            case .greaterThan: ">"
            case .greaterThanOrEquals: ">="
            case .lessThan: "<"
            case .lessThanOrEquals: "<="
            case .like: "ILIKE"
            case .isNull: "IS NULL"
            case .isNotNull: "IS NOT NULL"
            }
        }
    }

    private var looksLikeSQLExpression: Bool {
        let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
        let keywords = ["current_date", "current_timestamp", "now()", "interval",
                        "date(", "datetime(", "curdate()", "date_sub(", "date_add(",
                        "extract(", "age(", "make_date("]
        return keywords.contains { lower.contains($0) }
    }

    var sqlFragment: String {
        let escapedField = "\"\(field)\""
        if !filterOperator.needsValue {
            return "\(escapedField) \(filterOperator.sqlOperator)"
        }
        switch filterOperator {
        case .like:
            let escaped = value.replacing("'", with: "''")
            return "\(escapedField) ILIKE '%\(escaped)%'"
        default:
            if looksLikeSQLExpression {
                return "\(escapedField) \(filterOperator.sqlOperator) \(value)"
            }
            let escaped = value.replacing("'", with: "''")
            return "\(escapedField) \(filterOperator.sqlOperator) '\(escaped)'"
        }
    }

    var displaySummary: String {
        if !filterOperator.needsValue {
            return "\(field) \(filterOperator.displayName)"
        }
        return "\(field) \(filterOperator.displayName) \(value)"
    }

    var isComplete: Bool {
        !field.isEmpty && (filterOperator.needsValue ? !value.isEmpty : true)
    }
}

struct ChartFieldDefinition {
    let key: String
    let label: String
    let cardinality: Cardinality
    let columnFilter: ColumnFilter

    var isMeasureField: Bool {
        key == "yAxis" || key == "values"
    }

    enum Cardinality {
        case single
        case multiple
    }

    enum ColumnFilter {
        case all
        case numeric
    }
}

enum AggregationFunction: String, Codable, CaseIterable {
    case sum
    case average
    case count
    case countDistinct
    case min
    case max
    case none

    var displayName: String {
        switch self {
        case .sum: "Sum"
        case .average: "Average"
        case .count: "Count"
        case .countDistinct: "Count distinct"
        case .min: "Min"
        case .max: "Max"
        case .none: "No aggregation"
        }
    }

    func sqlExpression(for column: String) -> String {
        if column == "*" && self == .count { return "COUNT(*)" }
        let escaped = "\"\(column)\""
        switch self {
        case .sum: return "SUM(\(escaped))"
        case .average: return "AVG(\(escaped))"
        case .count: return "COUNT(\(escaped))"
        case .countDistinct: return "COUNT(DISTINCT \(escaped))"
        case .min: return "MIN(\(escaped))"
        case .max: return "MAX(\(escaped))"
        case .none: return escaped
        }
    }

    var sqlAliasSuffix: String {
        switch self {
        case .sum: "_sum"
        case .average: "_avg"
        case .count: "_count"
        case .countDistinct: "_count_distinct"
        case .min: "_min"
        case .max: "_max"
        case .none: ""
        }
    }

    private static let numericKeywords = ["int", "float", "double", "decimal", "numeric", "real", "number", "serial", "money"]
    private static let dateKeywords = ["date", "time", "timestamp"]

    static func isNumericDataType(_ dataType: String) -> Bool {
        let lower = dataType.lowercased()
        return numericKeywords.contains { lower.contains($0) }
    }

    static func isDateDataType(_ dataType: String) -> Bool {
        let lower = dataType.lowercased()
        return dateKeywords.contains { lower.contains($0) }
    }

    static func defaultAggregation(for dataType: String) -> AggregationFunction {
        isNumericDataType(dataType) ? .sum : .count
    }

    static func defaultAggregation(for dataType: String, chartType: ChartBlockConfig.ChartType) -> AggregationFunction {
        if chartType == .pie {
            return .count
        }
        return defaultAggregation(for: dataType)
    }

    static func availableAggregations(for dataType: String, chartType: ChartBlockConfig.ChartType? = nil) -> [AggregationFunction] {
        if isNumericDataType(dataType) {
            return [.sum, .average, .count, .countDistinct, .min, .max, .none]
        }
        if isDateDataType(dataType) {
            return [.count, .countDistinct, .min, .max, .none]
        }
        if chartType == .pie {
            return [.sum, .count, .countDistinct, .none]
        }
        return [.count, .countDistinct, .none]
    }
}

struct ChartBlockConfig: Codable {
    var connectionKeychainId: String
    var connectionName: String
    var databaseType: String
    var databaseName: String
    var schemaName: String?
    var tableName: String
    var fields: [String: [String]] = [:]
    var fieldAggregations: [String: [String: AggregationFunction]] = [:]
    var chartType: ChartType = .groupedColumn
    var rowLimit: Int = 500
    var filters: [ChartFilterCondition] = []
    var sourceQueryBlockId: String?

    func aggregation(forField fieldKey: String, column: String) -> AggregationFunction? {
        fieldAggregations[fieldKey]?[column]
    }

    mutating func setAggregation(_ agg: AggregationFunction, forField fieldKey: String, column: String) {
        var inner = fieldAggregations[fieldKey] ?? [:]
        inner[column] = agg
        fieldAggregations[fieldKey] = inner
    }

    var xAxisColumn: String? {
        get { fields["xAxis"]?.first }
        set { fields["xAxis"] = newValue.map { [$0] } }
    }

    var yAxisColumn: String? {
        get { fields["yAxis"]?.first }
        set { fields["yAxis"] = newValue.map { [$0] } }
    }

    init(
        connectionKeychainId: String,
        connectionName: String,
        databaseType: String,
        databaseName: String,
        schemaName: String? = nil,
        tableName: String,
        fields: [String: [String]] = [:],
        fieldAggregations: [String: [String: AggregationFunction]] = [:],
        chartType: ChartType = .groupedColumn,
        rowLimit: Int = 500,
        filters: [ChartFilterCondition] = [],
        sourceQueryBlockId: String? = nil
    ) {
        self.connectionKeychainId = connectionKeychainId
        self.connectionName = connectionName
        self.databaseType = databaseType
        self.databaseName = databaseName
        self.schemaName = schemaName
        self.tableName = tableName
        self.fields = fields
        self.fieldAggregations = fieldAggregations
        self.chartType = chartType
        self.rowLimit = rowLimit
        self.filters = filters
        self.sourceQueryBlockId = sourceQueryBlockId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionKeychainId = try container.decode(String.self, forKey: .connectionKeychainId)
        connectionName = try container.decode(String.self, forKey: .connectionName)
        databaseType = try container.decode(String.self, forKey: .databaseType)
        databaseName = try container.decode(String.self, forKey: .databaseName)
        schemaName = try container.decodeIfPresent(String.self, forKey: .schemaName)
        tableName = try container.decode(String.self, forKey: .tableName)
        chartType = try container.decodeIfPresent(ChartType.self, forKey: .chartType) ?? .groupedColumn
        rowLimit = try container.decodeIfPresent(Int.self, forKey: .rowLimit) ?? 500
        filters = try container.decodeIfPresent([ChartFilterCondition].self, forKey: .filters) ?? []
        fieldAggregations = try container.decodeIfPresent([String: [String: AggregationFunction]].self, forKey: .fieldAggregations) ?? [:]
        sourceQueryBlockId = try container.decodeIfPresent(String.self, forKey: .sourceQueryBlockId)

        if let decoded = try container.decodeIfPresent([String: [String]].self, forKey: .fields) {
            fields = decoded
        } else {
            var migrated: [String: [String]] = [:]
            if let x = try container.decodeIfPresent(String.self, forKey: .legacyXAxis) {
                migrated["xAxis"] = [x]
            }
            if let y = try container.decodeIfPresent(String.self, forKey: .legacyYAxis) {
                migrated["yAxis"] = [y]
            }
            fields = migrated
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(connectionKeychainId, forKey: .connectionKeychainId)
        try container.encode(connectionName, forKey: .connectionName)
        try container.encode(databaseType, forKey: .databaseType)
        try container.encode(databaseName, forKey: .databaseName)
        try container.encodeIfPresent(schemaName, forKey: .schemaName)
        try container.encode(tableName, forKey: .tableName)
        try container.encode(fields, forKey: .fields)
        try container.encode(fieldAggregations, forKey: .fieldAggregations)
        try container.encode(chartType, forKey: .chartType)
        try container.encode(rowLimit, forKey: .rowLimit)
        try container.encode(filters, forKey: .filters)
        try container.encodeIfPresent(sourceQueryBlockId, forKey: .sourceQueryBlockId)
    }

    private enum CodingKeys: String, CodingKey {
        case connectionKeychainId, connectionName, databaseType, databaseName
        case schemaName, tableName, fields, fieldAggregations, chartType, rowLimit, filters
        case sourceQueryBlockId
        case legacyXAxis = "xAxisColumn"
        case legacyYAxis = "yAxisColumn"
    }

    enum ChartType: String, Codable, CaseIterable {
        // Column (vertical)
        case groupedColumn = "bar"
        case stackedColumn
        case hundredPercentStackedColumn

        // Bar (horizontal)
        case groupedBar
        case stackedBar
        case hundredPercentStackedBar

        // Line & Area
        case line
        case stackedArea = "area"
        case hundredPercentStackedArea

        // Other
        case histogram
        case scatter
        case pie

        // Table
        case pivotTable

        var displayName: String {
            switch self {
            case .groupedColumn: "Grouped column"
            case .stackedColumn: "Stacked column"
            case .hundredPercentStackedColumn: "100% Stacked column"
            case .groupedBar: "Grouped bar"
            case .stackedBar: "Stacked bar"
            case .hundredPercentStackedBar: "100% Stacked bar"
            case .line: "Line"
            case .stackedArea: "Stacked area"
            case .hundredPercentStackedArea: "100% Stacked area"
            case .histogram: "Histogram"
            case .scatter: "Scatter"
            case .pie: "Pie"
            case .pivotTable: "Pivot table"
            }
        }

        var fieldDefinitions: [ChartFieldDefinition] {
            switch self {
            case .groupedColumn, .stackedColumn, .hundredPercentStackedColumn,
                 .groupedBar, .stackedBar, .hundredPercentStackedBar,
                 .line, .stackedArea, .hundredPercentStackedArea:
                [
                    ChartFieldDefinition(key: "xAxis", label: "X-axis", cardinality: .single, columnFilter: .all),
                    ChartFieldDefinition(key: "yAxis", label: "Y-axis", cardinality: .multiple, columnFilter: .all),
                ]
            case .histogram:
                [
                    ChartFieldDefinition(key: "xAxis", label: "X-axis", cardinality: .single, columnFilter: .all),
                ]
            case .scatter:
                [
                    ChartFieldDefinition(key: "xAxis", label: "X-axis", cardinality: .single, columnFilter: .all),
                    ChartFieldDefinition(key: "yAxis", label: "Y-axis", cardinality: .single, columnFilter: .all),
                ]
            case .pie:
                [
                    ChartFieldDefinition(key: "xAxis", label: "Label", cardinality: .single, columnFilter: .all),
                    ChartFieldDefinition(key: "yAxis", label: "Size", cardinality: .single, columnFilter: .all),
                ]
            case .pivotTable:
                [
                    ChartFieldDefinition(key: "rows", label: "Rows", cardinality: .multiple, columnFilter: .all),
                    ChartFieldDefinition(key: "columns", label: "Columns", cardinality: .multiple, columnFilter: .all),
                    ChartFieldDefinition(key: "values", label: "Values", cardinality: .multiple, columnFilter: .all),
                ]
            }
        }
    }

    struct ChartTypeGroup {
        let title: String
        let types: [ChartType]
    }

    static let chartTypeGroups: [ChartTypeGroup] = [
        ChartTypeGroup(title: "COLUMN", types: [.groupedColumn, .stackedColumn, .hundredPercentStackedColumn]),
        ChartTypeGroup(title: "BAR", types: [.groupedBar, .stackedBar, .hundredPercentStackedBar]),
        ChartTypeGroup(title: "LINE & AREA", types: [.line, .stackedArea, .hundredPercentStackedArea]),
        ChartTypeGroup(title: "OTHER", types: [.histogram, .scatter, .pie]),
        ChartTypeGroup(title: "TABLE", types: [.pivotTable]),
    ]
}

extension NotebookBlock {
    func chartConfig() -> ChartBlockConfig? {
        guard blockType == .chart, !configJSON.isEmpty,
              let data = configJSON.data(using: .utf8) else { return nil }
        return try? Foundation.JSONDecoder().decode(ChartBlockConfig.self, from: data)
    }

    func saveChartConfig(_ config: ChartBlockConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        configJSON = json
        updatedAt = Date()
    }
}
