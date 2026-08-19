import Foundation

struct SingleValueBlockConfig: Codable {
    var connectionKeychainId: String
    var connectionName: String
    var databaseType: String
    var databaseName: String
    var schemaName: String?
    var tableName: String
    var column: String?
    var aggregation: AggregationFunction = .count
    var filters: [ChartFilterCondition] = []
    var label: String?
    var sourceQueryBlockId: String?
}

extension NotebookBlock {
    func singleValueConfig() -> SingleValueBlockConfig? {
        guard blockType == .singleValue, !configJSON.isEmpty,
              let data = configJSON.data(using: .utf8) else { return nil }
        return try? Foundation.JSONDecoder().decode(SingleValueBlockConfig.self, from: data)
    }

    func saveSingleValueConfig(_ config: SingleValueBlockConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        configJSON = json
        updatedAt = Date()
    }
}
