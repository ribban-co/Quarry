//
//  QueryHistoryService.swift
//  Quarry
//
//  Created by Claude on 1/23/26.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class QueryHistoryService {
    private let modelContext: ModelContext
    private let connectionKeychainId: String

    var retentionDays: Int = 90
    var maxEntriesPerConnection: Int = 10_000

    init(modelContext: ModelContext, connectionKeychainId: String) {
        self.modelContext = modelContext
        self.connectionKeychainId = connectionKeychainId
    }

    func recordQuery(
        query: String,
        queryType: QueryType? = nil,
        source: QuerySource,
        databaseType: DatabaseType,
        databaseName: String? = nil,
        schemaName: String? = nil,
        tableName: String? = nil,
        executionDurationMs: Int? = nil,
        rowsAffected: Int? = nil,
        wasSuccessful: Bool = true,
        errorMessage: String? = nil
    ) {
        let sanitizationResult = QuerySanitizer.sanitize(query)
        let detectedType = queryType ?? QuerySanitizer.detectQueryType(from: query)
        let detectedTable = tableName ?? QuerySanitizer.extractTableName(from: query)

        let encryptedQuery = QueryHistoryEncryptionService.encrypt(
            query: sanitizationResult.sanitizedQuery,
            connectionKeychainId: connectionKeychainId
        )

        let entry = QueryHistoryEntry(
            connectionKeychainId: connectionKeychainId,
            encryptedQuery: encryptedQuery,
            queryType: detectedType,
            querySource: source,
            databaseType: databaseType,
            databaseName: databaseName,
            schemaName: schemaName,
            tableName: detectedTable,
            executionDurationMs: executionDurationMs,
            rowsAffected: rowsAffected,
            wasSuccessful: wasSuccessful,
            errorMessage: errorMessage,
            wasSanitized: sanitizationResult.wasSanitized
        )

        modelContext.insert(entry)

        do {
            try modelContext.save()
        } catch {
            debugLog("Failed to save query history entry: \(error)")
        }

        Task {
            await enforceRetentionLimits()
        }
    }

    func fetchHistory(
        limit: Int = 100,
        offset: Int = 0,
        searchText: String? = nil,
        queryTypes: Set<QueryType>? = nil,
        sources: Set<QuerySource>? = nil,
        tableName: String? = nil,
        successOnly: Bool? = nil,
        databaseName: String? = nil
    ) -> [QueryHistoryEntryViewModel] {
        // SwiftData #Predicate macros can't compose at runtime and the Swift
        // type checker times out when a single predicate gates four optional
        // axes via `||` chains. So we narrow on the server-side via a small
        // predicate (connectionKeychainId + optional databaseName) and apply
        // the remaining filters in memory — the result set is bounded by
        // `limit` so post-filtering is cheap.
        let predicate: Predicate<QueryHistoryEntry>
        if let databaseName {
            predicate = #Predicate<QueryHistoryEntry> { entry in
                entry.connectionKeychainId == connectionKeychainId &&
                entry.databaseName == databaseName
            }
        } else {
            predicate = #Predicate<QueryHistoryEntry> { entry in
                entry.connectionKeychainId == connectionKeychainId
            }
        }

        var descriptor = FetchDescriptor<QueryHistoryEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.executedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        do {
            var entries = try modelContext.fetch(descriptor)
            if let queryTypes, !queryTypes.isEmpty {
                let allowed = Set(queryTypes.map(\.rawValue))
                entries = entries.filter { allowed.contains($0.queryType) }
            }
            if let sources, !sources.isEmpty {
                let allowed = Set(sources.map(\.rawValue))
                entries = entries.filter { allowed.contains($0.querySource) }
            }
            if let successOnly {
                entries = entries.filter { $0.wasSuccessful == successOnly }
            }
            let viewModels = entries.compactMap { entry in
                createViewModel(from: entry, searchText: searchText)
            }
            migrateLegacyEncryption(for: entries)
            return viewModels
        } catch {
            debugLog("Failed to fetch query history: \(error)")
            return []
        }
    }

    /// Lazily re-encrypts entries still under the legacy derived key so they
    /// migrate to the Keychain-backed key as they're read. One save per batch.
    private func migrateLegacyEncryption(for entries: [QueryHistoryEntry]) {
        var migrated = 0
        for entry in entries {
            guard let encryptedQuery = entry.encryptedQuery,
                  let reencrypted = QueryHistoryEncryptionService.reencryptLegacyEntry(
                    encryptedQuery: encryptedQuery,
                    connectionKeychainId: connectionKeychainId
                  ) else { continue }
            entry.encryptedQuery = reencrypted
            migrated += 1
        }
        guard migrated > 0 else { return }
        do {
            try modelContext.save()
            debugLog("Re-encrypted \(migrated) legacy query history entries")
        } catch {
            debugLog("Failed to persist re-encrypted query history: \(error)")
        }
    }

    func deleteEntry(_ entryId: String) {
        let predicate = #Predicate<QueryHistoryEntry> { entry in
            entry.entryId == entryId
        }

        var descriptor = FetchDescriptor<QueryHistoryEntry>(predicate: predicate)
        descriptor.fetchLimit = 1

        do {
            let entries = try modelContext.fetch(descriptor)
            for entry in entries {
                modelContext.delete(entry)
            }
            try modelContext.save()
        } catch {
            debugLog("Failed to delete query history entry: \(error)")
        }
    }

    func clearHistory() {
        let predicate = #Predicate<QueryHistoryEntry> { entry in
            entry.connectionKeychainId == connectionKeychainId
        }

        let descriptor = FetchDescriptor<QueryHistoryEntry>(predicate: predicate)

        do {
            let entries = try modelContext.fetch(descriptor)
            for entry in entries {
                modelContext.delete(entry)
            }
            try modelContext.save()
        } catch {
            debugLog("Failed to clear query history: \(error)")
        }
    }

    static func deleteHistoryForConnection(modelContext: ModelContext, connectionKeychainId: String) {
        let predicate = #Predicate<QueryHistoryEntry> { entry in
            entry.connectionKeychainId == connectionKeychainId
        }

        let descriptor = FetchDescriptor<QueryHistoryEntry>(predicate: predicate)

        do {
            let entries = try modelContext.fetch(descriptor)
            for entry in entries {
                modelContext.delete(entry)
            }
            try modelContext.save()
        } catch {
            debugLog("Failed to delete history for connection: \(error)")
        }
    }

    func getHistoryCount() -> Int {
        let predicate = #Predicate<QueryHistoryEntry> { entry in
            entry.connectionKeychainId == connectionKeychainId
        }

        let descriptor = FetchDescriptor<QueryHistoryEntry>(predicate: predicate)

        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            debugLog("Failed to get history count: \(error)")
            return 0
        }
    }

    private func enforceRetentionLimits() async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

        let agePredicate = #Predicate<QueryHistoryEntry> { entry in
            entry.connectionKeychainId == connectionKeychainId &&
            entry.executedAt < cutoffDate
        }

        let ageDescriptor = FetchDescriptor<QueryHistoryEntry>(predicate: agePredicate)

        do {
            let oldEntries = try modelContext.fetch(ageDescriptor)
            for entry in oldEntries {
                modelContext.delete(entry)
            }

            let countPredicate = #Predicate<QueryHistoryEntry> { entry in
                entry.connectionKeychainId == connectionKeychainId
            }

            var countDescriptor = FetchDescriptor<QueryHistoryEntry>(
                predicate: countPredicate,
                sortBy: [SortDescriptor(\.executedAt, order: .reverse)]
            )

            let totalCount = try modelContext.fetchCount(countDescriptor)

            if totalCount > maxEntriesPerConnection {
                countDescriptor.fetchOffset = maxEntriesPerConnection
                let entriesToDelete = try modelContext.fetch(countDescriptor)
                for entry in entriesToDelete {
                    modelContext.delete(entry)
                }
            }

            try modelContext.save()
        } catch {
            debugLog("Failed to enforce retention limits: \(error)")
        }
    }

    private func createViewModel(from entry: QueryHistoryEntry, searchText: String?) -> QueryHistoryEntryViewModel? {
        guard let encryptedQuery = entry.encryptedQuery else { return nil }

        guard let decryptedQuery = QueryHistoryEncryptionService.decrypt(
            encryptedQuery: encryptedQuery,
            connectionKeychainId: connectionKeychainId
        ) else {
            return nil
        }

        if let searchText = searchText, !searchText.isEmpty {
            if !decryptedQuery.localizedStandardContains(searchText) {
                return nil
            }
        }

        return QueryHistoryEntryViewModel(
            entryId: entry.entryId,
            query: decryptedQuery,
            queryType: entry.queryTypeEnum,
            querySource: entry.querySourceEnum,
            databaseName: entry.databaseName,
            schemaName: entry.schemaName,
            tableName: entry.tableName,
            executedAt: entry.executedAt,
            formattedDuration: entry.formattedDuration,
            rowsAffected: entry.rowsAffected,
            wasSuccessful: entry.wasSuccessful,
            errorMessage: entry.errorMessage,
            wasSanitized: entry.wasSanitized
        )
    }
}

struct QueryHistoryEntryViewModel: Identifiable {
    let id: String
    let query: String
    let queryType: QueryType
    let querySource: QuerySource
    let databaseName: String?
    let schemaName: String?
    let tableName: String?
    let executedAt: Date
    let formattedDuration: String?
    let rowsAffected: Int?
    let wasSuccessful: Bool
    let errorMessage: String?
    let wasSanitized: Bool

    init(
        entryId: String,
        query: String,
        queryType: QueryType,
        querySource: QuerySource,
        databaseName: String?,
        schemaName: String?,
        tableName: String?,
        executedAt: Date,
        formattedDuration: String?,
        rowsAffected: Int?,
        wasSuccessful: Bool,
        errorMessage: String?,
        wasSanitized: Bool
    ) {
        self.id = entryId
        self.query = query
        self.queryType = queryType
        self.querySource = querySource
        self.databaseName = databaseName
        self.schemaName = schemaName
        self.tableName = tableName
        self.executedAt = executedAt
        self.formattedDuration = formattedDuration
        self.rowsAffected = rowsAffected
        self.wasSuccessful = wasSuccessful
        self.errorMessage = errorMessage
        self.wasSanitized = wasSanitized
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: executedAt, relativeTo: Date())
    }

    var queryPreview: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.replacing("\n", with: " ").replacing("  ", with: " ")
        if singleLine.count > 100 {
            return String(singleLine.prefix(100)) + "..."
        }
        return singleLine
    }
}
