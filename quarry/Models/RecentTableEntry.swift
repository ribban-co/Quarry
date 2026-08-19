import Foundation
import SwiftData

@Model
final class RecentTableEntry {
    var entryId: String = UUID().uuidString
    var connectionKeychainId: String = ""
    var tableName: String = ""
    var databaseName: String = ""
    var schemaName: String? = nil
    var tableType: String = "table"
    var openedAt: Date = Date()

    init(
        connectionKeychainId: String,
        tableName: String,
        databaseName: String,
        schemaName: String? = nil,
        tableType: String = "table"
    ) {
        self.connectionKeychainId = connectionKeychainId
        self.tableName = tableName
        self.databaseName = databaseName
        self.schemaName = schemaName
        self.tableType = tableType
    }
}
