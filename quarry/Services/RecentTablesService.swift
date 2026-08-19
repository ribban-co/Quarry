import Foundation
import SwiftData

@MainActor
@Observable
final class RecentTablesService {
    private let modelContext: ModelContext
    private let connectionKeychainId: String
    private let maxItems: Int = 50

    init(modelContext: ModelContext, connectionKeychainId: String) {
        self.modelContext = modelContext
        self.connectionKeychainId = connectionKeychainId
    }

    func recordTableOpened(tableName: String, databaseName: String, schemaName: String?, tableType: String = "table") {
        let newEntry = RecentTableEntry(
            connectionKeychainId: connectionKeychainId,
            tableName: tableName,
            databaseName: databaseName,
            schemaName: schemaName,
            tableType: tableType
        )
        modelContext.insert(newEntry)

        do {
            try modelContext.save()
        } catch {
            debugLog("Failed to record recent table: \(error)")
            return
        }

        // Clean up duplicates and enforce limit in a separate pass
        cleanupDuplicates(tableName: tableName, databaseName: databaseName, schemaName: schemaName)
        enforceLimit()

        do {
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            debugLog("Failed to cleanup recent tables: \(error)")
        }
    }

    func fetchRecent(limit: Int = 50, databaseName: String? = nil) -> [RecentTableEntry] {
        let keychainId = connectionKeychainId

        let predicate: Predicate<RecentTableEntry>
        if let dbName = databaseName {
            predicate = #Predicate<RecentTableEntry> { entry in
                entry.connectionKeychainId == keychainId &&
                entry.databaseName == dbName
            }
        } else {
            predicate = #Predicate<RecentTableEntry> { entry in
                entry.connectionKeychainId == keychainId
            }
        }

        var descriptor = FetchDescriptor<RecentTableEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.openedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            debugLog("Failed to fetch recent tables: \(error)")
            return []
        }
    }

    private func cleanupDuplicates(tableName: String, databaseName: String, schemaName: String?) {
        let keychainId = connectionKeychainId
        let name = tableName
        let dbName = databaseName
        let predicate: Predicate<RecentTableEntry>
        if let schema = schemaName {
            predicate = #Predicate<RecentTableEntry> { entry in
                entry.connectionKeychainId == keychainId &&
                entry.tableName == name &&
                entry.databaseName == dbName &&
                entry.schemaName == schema
            }
        } else {
            predicate = #Predicate<RecentTableEntry> { entry in
                entry.connectionKeychainId == keychainId &&
                entry.tableName == name &&
                entry.databaseName == dbName &&
                entry.schemaName == nil
            }
        }

        var descriptor = FetchDescriptor<RecentTableEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.openedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50

        do {
            let entries = try modelContext.fetch(descriptor)
            // Keep only the most recent one
            for entry in entries.dropFirst() {
                modelContext.delete(entry)
            }
        } catch {
            debugLog("Failed to cleanup duplicate recent tables: \(error)")
        }
    }

    private func enforceLimit() {
        let keychainId = connectionKeychainId

        let predicate = #Predicate<RecentTableEntry> { entry in
            entry.connectionKeychainId == keychainId
        }

        var descriptor = FetchDescriptor<RecentTableEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.openedAt, order: .reverse)]
        )
        descriptor.fetchOffset = maxItems
        descriptor.fetchLimit = 100

        do {
            let entriesToDelete = try modelContext.fetch(descriptor)
            for entry in entriesToDelete {
                modelContext.delete(entry)
            }
        } catch {
            debugLog("Failed to enforce recent tables limit: \(error)")
        }
    }

    static func deleteForConnection(modelContext: ModelContext, connectionKeychainId: String) {
        let keychainId = connectionKeychainId

        let predicate = #Predicate<RecentTableEntry> { entry in
            entry.connectionKeychainId == keychainId
        }

        let descriptor = FetchDescriptor<RecentTableEntry>(predicate: predicate)

        do {
            let entries = try modelContext.fetch(descriptor)
            for entry in entries {
                modelContext.delete(entry)
            }
            try modelContext.save()
        } catch {
            debugLog("Failed to delete recent tables for connection: \(error)")
        }
    }
}
