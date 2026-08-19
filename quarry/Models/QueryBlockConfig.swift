import Foundation

struct QueryBlockConfig: Codable {
    var connectionKeychainId: String
    var connectionName: String
    var databaseType: String
    var databaseName: String
    var schemaName: String?
    var queryText: String = ""
    var outputName: String = ""
    var rowLimit: Int = 500
}

extension NotebookBlock {
    func queryBlockConfig() -> QueryBlockConfig? {
        guard blockType == .query, !configJSON.isEmpty,
              let data = configJSON.data(using: .utf8) else { return nil }
        return try? Foundation.JSONDecoder().decode(QueryBlockConfig.self, from: data)
    }

    func saveQueryBlockConfig(_ config: QueryBlockConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        configJSON = json
        updatedAt = Date()
    }
}
