import AppKit
import SwiftUI

enum TableListViewState: Equatable {
    case loading
    case error(String)
    case loaded(QueryResult, DatabaseSchemaResult?)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    static func == (lhs: TableListViewState, rhs: TableListViewState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.loaded(let lhsResult, let lhsSchema), .loaded(let rhsResult, let rhsSchema)):
            return lhsResult.totalCount == rhsResult.totalCount &&
                   lhsSchema?.columns.count == rhsSchema?.columns.count
        default:
            return false
        }
    }
}

@Observable @MainActor
class TableDataController {

    let instance: ConnectionInstance
    let tab: DatabaseTab

    var viewState: TableListViewState = .loading
    var sortColumn: String?
    var sortAscending: Bool = true

    var cachedSchema: DatabaseSchemaResult?
    var cachedIndexes: [DatabaseIndexInfo]?
    var cachedDocuments: QueryResult?
    var cachedTabName: String?
    private var cachedConnectionGeneration: Int?
    private var cachedDatabaseName: String?

    var loadingTask: Task<Void, Never>?
    private var loadingTaskID = UUID()

    var modificationTracker = TableModificationTracker()
    var schemaModificationTracker = SchemaModificationTracker()
    var isProcessingUpdates = false
    var isProcessingSchemaUpdates = false
    var needsToSelectLastRow = false

    var currentError: Error?
    var showingErrorAlert = false
    var showingViewStateError = false
    var viewStateErrorMessage = ""

    var filterConditions: [FilterCondition] = [FilterCondition(conjunction: .whereClause, field: "", filterOperator: .equals, value: "")]
    var currentActiveFilter: String?

    /// Total rows in the table for the active filter — nil while unknown.
    /// Fetched off the load path and cached per (table, filter, connection).
    private(set) var totalRowCount: Int?
    private var totalRowCountKey: String?

    private var lastTabFilterColumn: String?
    private var lastTabFilterValue: String?

    private var isFetchingSchema = false
    private var isFetchingIndexes = false
    var isSubscribedToRealTime = false
    var receivedFirstRealtimeEvent = false
    var skipNextRealtimeEvent = false
    var changeDetector = TableChangeDetector()
    var updatedFields: Set<String> = []
    var updatedRows: Set<Int> = []

    init(instance: ConnectionInstance, tab: DatabaseTab) {
        self.instance = instance
        self.tab = tab

        if instance.connection.databaseType == .convex {
            sortAscending = false
        }
    }

    func cancel() {
        cancelLoadingTask()
        cancelRealTimeSubscription()
    }

    func cancelLoadingTask() {
        loadingTaskID = UUID()
        loadingTask?.cancel()
        loadingTask = nil
    }

    /// User-initiated cancel from the action bar's ✕ while loading. Stops the
    /// load and restores the last loaded result so the UI doesn't hang in
    /// the loading state.
    func cancelActiveLoad() {
        cancelLoadingTask()
        if case .loading = viewState {
            if let cachedDocuments {
                viewState = .loaded(cachedDocuments, cachedSchema)
            } else {
                viewState = .error("Query cancelled")
            }
        }
    }

    /// Eager non-MainActor fetch used by `prewarmTableDataController`. The DB
    /// query is dispatched on the driver's actor (separate from Main) so it
    /// runs *in parallel* with the tab UI mount that's blocking Main. Saves
    /// ~17–21 ms on first table open per window.
    ///
    /// Honors `tab.filterColumn`/`tab.filterValue` (set by foreign-key click
    /// navigation) by computing the initial filter clause synchronously here
    /// — otherwise FK-link tabs would prewarm an unfiltered result set.
    func prewarmFetch() {
        guard instance.isReady,
              let driverBox = instance.databaseService.currentDriverBox() else {
            return
        }

        // Match `loadDocumentsIfNeeded` behavior: derive the initial filter
        // from the tab's FK-link parameters before kicking off the fetch.
        let initialFilter = generateInitialFilter()
        currentActiveFilter = initialFilter

        // Snapshot Sendable params on MainActor so the detached task doesn't
        // need to hop back here just to read them.
        let tabName = tab.name
        let dbSchema = tab.databaseSchema
        let connectionGen = instance.connectionGeneration
        let dbName = instance.connectedDatabase?.name
        let limit = 300
        let sortBy = sortColumn
        let asc = sortAscending
        let filterString = initialFilter ?? ""

        let taskID = UUID()
        loadingTaskID = taskID

        // The prewarm path bypasses loadDocuments, so kick the total-count
        // fetch here too or first-open tabs never get the "N of M" label.
        refreshTotalRowCount(filter: filterString)

        loadingTask = Task.detached(priority: .userInitiated) { [weak self] in
            async let docsResult: QueryResult? = {
                do {
                    return try await driverBox.findDocuments(
                        in: tabName,
                        databaseSchema: dbSchema,
                        filter: ["rawQuery": .string(filterString)],
                        skip: 0,
                        limit: limit,
                        sortBy: sortBy,
                        ascending: asc
                    )
                } catch {
                    return nil
                }
            }()
            async let schemaResult: DatabaseSchemaResult? = {
                do {
                    return try await driverBox.getSchema(for: tabName, schema: dbSchema)
                } catch {
                    return nil
                }
            }()

            let documents = await docsResult
            let schema = await schemaResult

            await MainActor.run {
                guard let self else { return }
                guard self.tab.name == tabName else { return }
                guard self.loadingTaskID == taskID else { return }

                if let schema {
                    self.cachedSchema = schema
                }
                if let documents {
                    self.cachedDocuments = documents
                    self.cachedTabName = tabName
                    self.cachedConnectionGeneration = connectionGen
                    self.cachedDatabaseName = dbName
                    self.viewState = .loaded(documents, self.cachedSchema)
                }

                if self.loadingTaskID == taskID {
                    self.loadingTask = nil
                }
            }
        }
    }

    func scheduleLoadDocumentsIfNeeded() {
        // Idempotent guard: if a load is already in flight (e.g. the prewarm
        // fetch from `createNewTab`) and the tab hasn't asked for a forced
        // refetch, leave it alone — cancelling and restarting would waste the
        // in-flight DB roundtrip.
        if loadingTask != nil, !tab.forceFetch {
            return
        }
        scheduleLoadingTask { controller in
            await controller.loadDocumentsIfNeeded()
        }
    }

    /// Lazily fetch indexes only when the user actually views the schema mode.
    /// Indexes were a 200+ KB query at every table open; they're only used in
    /// `SchemaModeView`, so we keep them off the table-open hot path.
    func loadIndexesIfNeeded(force: Bool = false) {
        if !force, cachedIndexes != nil { return }
        if isFetchingIndexes && !force { return }
        guard instance.isReady else { return }
        let tabName = tab.name
        let databaseSchema = tab.databaseSchema
        isFetchingIndexes = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isFetchingIndexes = false }
            do {
                let indexes = try await instance.databaseService.getIndexes(for: tabName, databaseSchema: databaseSchema, forceFetch: force)
                guard self.tab.name == tabName else { return }
                self.cachedIndexes = indexes
            } catch {
                debugLog("Failed to fetch indexes for \(tabName): \(error.localizedDescription)")
            }
        }
    }

    func scheduleLoadOrSubscribe(
        forceFetch: Bool = false,
        fetchSchema: Bool = true,
        page: Int = 1,
        limit: Int = 300,
        filter: String? = nil,
        skipNextRealtimeEvent: Bool = true
    ) {
        scheduleLoadingTask { controller in
            if skipNextRealtimeEvent {
                controller.skipNextRealtimeEvent = true
            }
            await controller.loadOrSubscribe(
                forceFetch: forceFetch,
                fetchSchema: fetchSchema,
                page: page,
                limit: limit,
                filter: filter
            )
        }
    }

    private func scheduleLoadingTask(
        _ operation: @escaping @MainActor @Sendable (TableDataController) async -> Void
    ) {
        cancelLoadingTask()

        let taskID = UUID()
        loadingTaskID = taskID
        loadingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.loadingTaskID == taskID {
                    self.loadingTask = nil
                }
            }
            await operation(self)
        }
    }

    // MARK: - Computed Properties

    var currentQueryResult: QueryResult? {
        if case .loaded(let queryResult, _) = viewState {
            return queryResult
        }
        return cachedDocuments
    }

    var currentSchema: DatabaseSchemaResult? {
        if case .loaded(_, let schema) = viewState {
            return schema
        }
        return cachedSchema
    }

    // MARK: - Error Handling

    func showError(_ error: Error) {
        currentError = error
        showingErrorAlert = true
    }

    func handleViewStateChange() {
        if case .error(let message) = viewState {
            viewStateErrorMessage = message
            showingViewStateError = true
        }
    }

    private func forceViewStateRefresh(with result: QueryResult, schema: DatabaseSchemaResult?) {
        viewState = .loading
        viewState = .loaded(result, schema)
    }

    private func makeDatabaseValue(from value: Any?) -> DatabaseValue? {
        guard let value else { return nil }
        if let databaseValue = DatabaseValue(value) {
            return databaseValue
        }
        if let convertible = value as? any CustomStringConvertible {
            return .string(convertible.description)
        }
        return nil
    }

    private func makeTrackerRow(from rawRow: DatabaseRawRow) -> [String: Any] {
        rawRow.reduce(into: [:]) { partialResult, entry in
            if let value = entry.value?.anyValue {
                partialResult[entry.key] = value
            }
        }
    }

    private func columnsForNewRecord() -> [QueryColumnInfo]? {
        if let currentSchema {
            return queryColumns(from: currentSchema)
        }

        guard let currentQueryResult, !currentQueryResult.columns.isEmpty else {
            return nil
        }

        return currentQueryResult.columns
    }

    // MARK: - Loading

    func loadDocumentsIfNeeded() async {
        guard instance.isReady else {
            if viewState != .loading { viewState = .loading }
            return
        }

        let shouldFetch = cachedTabName != tab.name
            || cachedDocuments == nil
            || tab.forceFetch
            || cachedConnectionGeneration != instance.connectionGeneration
            || cachedDatabaseName != instance.connectedDatabase?.name

        guard shouldFetch else {
            if let cachedDocuments {
                viewState = .loaded(cachedDocuments, cachedSchema)
            }
            if !isSubscribedToRealTime && shouldUseRealtime(for: currentActiveFilter) {
                await subscribeToRealTimeUpdatesIfSupported(page: 1)
            }
            return
        }

        let initialFilter = generateInitialFilter()
        currentActiveFilter = initialFilter
        // Initial open: forceFetch documents (we have nothing cached) but
        // DON'T force schema refetch — let the driver's per-connection
        // schema cache (PostgreSQLDriver.databaseSchema) serve repeat opens
        // instantly. Only explicit user refresh (refreshData) bypasses cache.
        await loadOrSubscribe(forceFetch: true, fetchSchema: true, forceSchemaRefetch: false, page: 1, limit: 300, filter: initialFilter)
        tab.forceFetch = false
    }

    func loadOrSubscribe(forceFetch: Bool = false, fetchSchema: Bool = true, forceSchemaRefetch: Bool = false, page: Int = 1, limit: Int = 300, filter: String? = nil) async {
        guard instance.isReady else {
            if viewState != .loading { viewState = .loading }
            return
        }

        let effectiveFilter = filter ?? currentActiveFilter
        currentActiveFilter = effectiveFilter

        if shouldUseRealtime(for: effectiveFilter) {
            if forceFetch || cachedDocuments == nil { viewState = .loading }

            // Fire schema in background — don't block the subscription. Indexes
            // are loaded lazily by the schema-mode UI on demand.
            if fetchSchema && (forceSchemaRefetch || cachedSchema == nil || cachedTabName != tab.name) {
                let tabName = tab.name
                let databaseSchema = tab.databaseSchema
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let schema = try await instance.databaseService.getSchema(for: tabName, databaseSchema: databaseSchema, forceFetch: forceSchemaRefetch)
                        guard self.tab.name == tabName else { return }
                        self.cachedSchema = schema
                    } catch {
                        debugLog("Failed to fetch schema for \(tabName): \(error.localizedDescription)")
                    }
                }
            }
            cachedTabName = tab.name
            cachedConnectionGeneration = instance.connectionGeneration
            cachedDatabaseName = instance.connectedDatabase?.name
            cancelRealTimeSubscription()
            await subscribeToRealTimeUpdatesIfSupported(page: page)
            return
        }

        cancelRealTimeSubscription()
        await loadDocuments(forceFetch: forceFetch, fetchSchema: fetchSchema, forceSchemaRefetch: forceSchemaRefetch, page: page, limit: limit, filter: effectiveFilter)
    }

    func loadDocuments(forceFetch: Bool = false, fetchSchema: Bool = true, forceSchemaRefetch: Bool = false, page: Int = 1, limit: Int = 300, filter: String? = nil) async {
        guard !Task.isCancelled else { return }
        guard instance.isReady else {
            if viewState != .loading { viewState = .loading }
            return
        }

        if !forceFetch,
           cachedTabName == tab.name,
           cachedConnectionGeneration == instance.connectionGeneration,
           cachedDatabaseName == instance.connectedDatabase?.name,
           let cachedDocuments {
            viewState = .loaded(cachedDocuments, cachedSchema)
            refreshTotalRowCount(filter: filter ?? currentActiveFilter ?? "")
            return
        }

        do {
            viewState = .loading

            guard !Task.isCancelled else { return }

            let databaseSchema = tab.databaseSchema
            // Schema is kicked off only when we don't already have it locally
            // OR when the user explicitly asked for a refresh. Documents
            // forceFetch alone does NOT force schema refetch — the driver's
            // per-connection schema cache (PostgreSQLDriver.databaseSchema)
            // makes repeat opens of the same table instant, matching TablePlus.
            let needsSchema = fetchSchema && (forceSchemaRefetch || cachedSchema == nil || cachedTabName != tab.name)

            // Kick off schema in the background so the document fetch doesn't
            // wait on it. Indexes are NOT fetched here — they're only used in
            // schema mode and we lazy-load on demand (TablePlus parity). The
            // big indexes query was the dominant cost on the wire after
            // schema started caching.
            if needsSchema {
                let tabName = tab.name
                Task { [weak self] in
                    guard let self else { return }
                    let schema: DatabaseSchemaResult?
                    do {
                        schema = try await instance.databaseService.getSchema(for: tabName, databaseSchema: databaseSchema, forceFetch: forceSchemaRefetch)
                    } catch {
                        debugLog("Failed to fetch schema for \(tabName): \(error.localizedDescription)")
                        schema = nil
                    }
                    guard self.tab.name == tabName else { return }
                    if let schema {
                        self.cachedSchema = schema
                        self.updateTabSchemaDeviation(self.hasColumnMismatch(queryResult: self.cachedDocuments, schema: schema))
                        if let docs = self.cachedDocuments {
                            // Re-emit loaded state so observers refresh with the
                            // newly-arrived schema info.
                            self.viewState = .loaded(docs, schema)
                        }
                    }
                }
            }

            // Kick off the total count alongside the page query — it queues on
            // the same connection, so starting it here (not after the page and
            // schema round-trips) is what makes the "N of M" label feel instant.
            refreshTotalRowCount(filter: filter ?? "", force: forceFetch)

            let documents = try await instance.databaseService.findDocuments(
                in: tab.name,
                databaseSchema: databaseSchema,
                filter: filter ?? "",
                skip: (page - 1) * limit,
                limit: limit,
                sortBy: sortColumn,
                ascending: sortAscending
            )

            guard !Task.isCancelled else { return }

            cachedDocuments = documents
            cachedTabName = tab.name
            cachedConnectionGeneration = instance.connectionGeneration
            cachedDatabaseName = instance.connectedDatabase?.name

            // Paint immediately with whatever schema we already have. If
            // `needsSchema` is true and the background task hasn't returned
            // yet, schema is nil here — the background task will re-emit
            // `.loaded(documents, schema)` when it arrives.
            viewState = .loaded(documents, cachedSchema)

            if let schema = cachedSchema {
                let mismatch = hasColumnMismatch(queryResult: documents, schema: schema)
                updateTabSchemaDeviation(mismatch)
                // Lazy revalidation: if the freshly-fetched documents return
                // columns that don't match our cached schema, the schema is
                // stale (someone altered the table externally). Refetch in
                // the background to repair the cache.
                if mismatch {
                    let tabName = tab.name
                    let dbSchema = tab.databaseSchema
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            let freshSchema = try await instance.databaseService.getSchema(for: tabName, databaseSchema: dbSchema, forceFetch: true)
                            guard self.tab.name == tabName else { return }
                            self.cachedSchema = freshSchema
                            self.updateTabSchemaDeviation(self.hasColumnMismatch(queryResult: self.cachedDocuments, schema: freshSchema))
                            if let docs = self.cachedDocuments {
                                self.viewState = .loaded(docs, freshSchema)
                            }
                        } catch {
                            debugLog("Lazy schema refetch failed for \(tabName): \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            debugLog(error.localizedDescription)
            viewState = .error(error.localizedDescription)
        }
    }

    /// Fetches the table's total row count (honoring the active filter) in the
    /// background. Cached per (table, filter, connection) so page navigation
    /// doesn't re-count; `force` re-counts on explicit refresh.
    private func refreshTotalRowCount(filter: String, force: Bool = false) {
        let key = [
            tab.name,
            tab.databaseSchema ?? "",
            filter,
            String(instance.connectionGeneration),
            instance.connectedDatabase?.name ?? ""
        ].joined(separator: "|")

        guard force || key != totalRowCountKey else { return }
        // Clear a stale total when switching table/filter; keep it visible
        // during a same-key force refresh to avoid label flicker.
        if key != totalRowCountKey { totalRowCount = nil }
        totalRowCountKey = key

        let tabName = tab.name
        let databaseSchema = tab.databaseSchema
        Task { [weak self] in
            guard let self else { return }
            var count: Int?
            do {
                count = try await instance.databaseService.getTotalRowCount(
                    for: tabName,
                    databaseSchema: databaseSchema,
                    filter: filter
                )
                if count == nil {
                    debugLog("Total row count unavailable for \(tabName)")
                }
            } catch {
                debugLog("Total row count failed for \(tabName): \(error.localizedDescription)")
            }
            guard self.totalRowCountKey == key else { return }
            self.totalRowCount = count
        }
    }

    func refreshData() async {
        // Explicit user refresh: bypass driver schema cache too.
        await loadOrSubscribe(forceFetch: true, fetchSchema: true, forceSchemaRefetch: true, page: 1, limit: 300, filter: currentActiveFilter)
    }

    func clearCache() {
        cancelLoadingTask()
        cancelRealTimeSubscription()
        cachedSchema = nil
        cachedIndexes = nil
        isFetchingIndexes = false
        cachedDocuments = nil
        cachedTabName = nil
        cachedConnectionGeneration = nil
        cachedDatabaseName = nil
        sortColumn = nil
        sortAscending = instance.connection.databaseType != .convex
        viewState = .loading
    }

    private func extractRowId(from result: QueryResult, rowIndex: Int) -> DatabaseRecordID? {
        result.recordID(row: rowIndex)
    }

    // MARK: - Schema Modifications

    func commitSchemaModifications() async {
        let validationErrors = schemaModificationTracker.validateModifications()
        guard validationErrors.isEmpty else {
            currentError = DatabaseError.operationFailed(validationErrors.joined(separator: "\n"))
            showingErrorAlert = true
            return
        }

        debugLog("💾 Saving \(schemaModificationTracker.totalModificationCount) schema modifications...")

        do {
            guard let service = instance.databaseService.makeSchemaModificationService() else {
                throw DatabaseError.operationFailed("No active database driver")
            }

            let plan = schemaModificationTracker.snapshot()
            try await service.executeModifications(
                tableName: tab.name,
                schema: tab.databaseSchema,
                plan: plan
            )

            schemaModificationTracker.clearAll()

            // We just executed ALTER/CREATE/DROP — the cached schema is stale.
            await loadOrSubscribe(forceFetch: true, fetchSchema: true, forceSchemaRefetch: true, page: 1, limit: 300, filter: currentActiveFilter)

            // SchemaModeView holds its own snapshot of the schema/indexes — nudge it to refetch.
            NotificationCenter.default.post(name: .schemaTableRefresh, object: nil)

            debugLog("✅ Schema modifications saved successfully")
        } catch {
            currentError = error
            showingErrorAlert = true
        }
    }

    // MARK: - Data Modifications

    func commitModifications() async {
        NSApp.keyWindow?.makeFirstResponder(nil)

        let modifications = modificationTracker.allModifications

        guard !modifications.isEmpty else {
            debugLog("ℹ️ No modifications to save")
            return
        }

        debugLog("💾 Saving \(modifications.count) modified rows...")

        for rowModification in modifications {
            do {
                switch rowModification.type {
                case .insert:
                    var newDocument = [String: Any]()
                    for (columnName, cellMod) in rowModification.cellModifications {
                        newDocument[columnName] = cellMod.newValue
                    }
                    try await instance.databaseService.createDocument(in: tab.name, databaseSchema: tab.databaseSchema, document: newDocument)
                    debugLog("✅ Inserted new row at index \(rowModification.rowIndex)")

                case .update:
                    guard let currentQueryResult,
                          rowModification.rowIndex < currentQueryResult.rawRows.count else {
                        debugLog("❌ Invalid row index: \(rowModification.rowIndex)")
                        continue
                    }

                    var updateData: [String: Any] = [:]
                    for (columnName, cellMod) in rowModification.cellModifications where cellMod.hasChanged {
                        updateData[columnName] = cellMod.newValue
                    }

                    guard let id = extractRowId(from: currentQueryResult, rowIndex: rowModification.rowIndex) else {
                        debugLog("❌ Could not find row identifier for row \(rowModification.rowIndex)")
                        continue
                    }

                    try await instance.databaseService.updateDocument(
                        in: tab.name,
                        databaseSchema: tab.databaseSchema,
                        id: id,
                        data: updateData
                    )

                    debugLog("✅ Updated row \(rowModification.rowIndex) with \(updateData.count) changes")

                case .delete:
                    guard let currentQueryResult,
                          rowModification.rowIndex < currentQueryResult.rawRows.count else {
                        debugLog("❌ Invalid row index: \(rowModification.rowIndex)")
                        continue
                    }

                    guard let id = extractRowId(from: currentQueryResult, rowIndex: rowModification.rowIndex) else {
                        debugLog("❌ Could not find row identifier for row \(rowModification.rowIndex)")
                        continue
                    }

                    try await instance.databaseService.deleteDocument(in: tab.name, databaseSchema: tab.databaseSchema, id: id)
                    debugLog("✅ Deleted row at index \(rowModification.rowIndex)")
                }
            } catch {
                showError(error)
                return
            }
        }

        modificationTracker.resetAllModifications()

        if !instance.databaseService.supportsRealTime {
            await loadDocuments(forceFetch: true, fetchSchema: false, page: 1, limit: 300, filter: currentActiveFilter)
        }

        debugLog("✅ All modifications saved successfully")
    }

    // MARK: - New Record

    func handleNewRecord() {
        guard let currentResult = currentQueryResult,
              let columns = columnsForNewRecord(),
              !columns.isEmpty else { return }

        let newRawRow: DatabaseRawRow = [:]
        var newProcessedRow = [String: QueryRowInfo]()

        for column in columns {
            newProcessedRow[column.name] = QueryRowInfo(
                value: nil,
                dataType: column.dataType,
                format: column.format
            )
        }

        let newIndex = currentResult.rawRows.count
        modificationTracker.markAsNewRow(rowIndex: newIndex, initialData: makeTrackerRow(from: newRawRow))

        var updatedRawRows = currentResult.rawRows
        updatedRawRows.append(newRawRow)

        var updatedProcessedRows = currentResult.rows
        updatedProcessedRows.append(newProcessedRow)

        let updatedResult = QueryResult(
            columns: columns,
            rows: updatedProcessedRows,
            totalCount: currentResult.totalCount + 1,
            rawRows: updatedRawRows
        )

        cachedDocuments = updatedResult
        viewState = .loaded(updatedResult, currentSchema)
        needsToSelectLastRow = true
    }

    func handlePasteRows() {
        guard let schema = cachedSchema, let currentResult = cachedDocuments else { return }
        guard let clipboardString = NSPasteboard.general.string(forType: .string),
              !clipboardString.isEmpty else { return }

        let parsedRows = parseClipboardContent(clipboardString, schema: schema)
        guard !parsedRows.isEmpty else { return }

        var updatedRawRows = currentResult.rawRows
        var updatedProcessedRows = currentResult.rows

        for rowData in parsedRows {
            let newIndex = updatedRawRows.count

            var processedRow = [String: QueryRowInfo]()

            for column in schema.columns {
                let value = rowData[column.columnName] ?? nil

                processedRow[column.columnName] = QueryRowInfo(
                    value: value,
                    dataType: column.dataType,
                    format: column.formatType
                )
            }

            modificationTracker.markAsNewRow(rowIndex: newIndex, initialData: makeTrackerRow(from: rowData))
            updatedRawRows.append(rowData)
            updatedProcessedRows.append(processedRow)
        }

        let updatedResult = QueryResult(
            columns: queryColumns(from: schema),
            rows: updatedProcessedRows,
            totalCount: currentResult.totalCount + parsedRows.count,
            rawRows: updatedRawRows
        )

        cachedDocuments = updatedResult
        needsToSelectLastRow = true
        forceViewStateRefresh(with: updatedResult, schema: cachedSchema)
        debugLog("✅ Pasted \(parsedRows.count) row(s)")
    }

    // MARK: - Discard Changes

    func handleDiscardChanges() {
        needsToSelectLastRow = false

        guard let currentResult = cachedDocuments else {
            modificationTracker.resetAllModifications(of: .update, .insert)
            return
        }

        let insertIndices = modificationTracker.allModifications
            .filter { $0.type == .insert }
            .map { $0.rowIndex }
            .sorted(by: >)

        var updatedRawRows = currentResult.rawRows
        var updatedProcessedRows = currentResult.rows

        for index in insertIndices where index < updatedRawRows.count && index < updatedProcessedRows.count {
            updatedRawRows.remove(at: index)
            updatedProcessedRows.remove(at: index)
        }

        modificationTracker.resetAllModifications(of: .update, .insert)

        let updatedResult = QueryResult(
            columns: currentResult.columns,
            rows: updatedProcessedRows,
            totalCount: currentResult.totalCount - insertIndices.count,
            rawRows: updatedRawRows
        )

        cachedDocuments = updatedResult
        forceViewStateRefresh(with: updatedResult, schema: cachedSchema)

        NotificationCenter.default.post(
            name: .tableReloadData,
            object: nil,
            userInfo: ["tableName": tab.name, "tabID": tab.id.uuidString]
        )

        debugLog("✅ Discarded changes, removed \(insertIndices.count) inserted row(s)")
    }

    // MARK: - Delete / Undo Row

    private func removeRow(at index: Int) -> QueryResult? {
        guard let currentResult = cachedDocuments,
              currentResult.rawRows.indices.contains(index) else {
            return nil
        }

        var rawRows = currentResult.rawRows
        var processedRows = currentResult.rows
        rawRows.remove(at: index)
        processedRows.remove(at: index)

        let updatedResult = QueryResult(
            columns: currentResult.columns,
            rows: processedRows,
            totalCount: currentResult.totalCount - 1,
            rawRows: rawRows
        )

        cachedDocuments = updatedResult
        return updatedResult
    }

    func deleteNewlyAddedRecord(atIndex index: Int) {
        modificationTracker.deleteRow(rowIndex: index)

        guard let updatedResult = removeRow(at: index) else {
            debugLog("❌ Invalid index for deletion: \(index)")
            return
        }

        viewState = .loaded(updatedResult, cachedSchema)
        debugLog("✅ Deleted new record at index \(index)")
    }

    func undoRowInsert(atIndex index: Int) {
        guard let updatedResult = removeRow(at: index) else {
            debugLog("❌ Invalid index for undo row insert: \(index)")
            return
        }

        needsToSelectLastRow = false

        forceViewStateRefresh(with: updatedResult, schema: cachedSchema)

        NotificationCenter.default.post(
            name: .tableReloadData,
            object: nil,
            userInfo: ["tableName": tab.name, "tabID": tab.id.uuidString]
        )

        debugLog("✅ Undid row insert at index \(index)")
    }

    // MARK: - New Field (Schema)

    func handleNewField() {
        let newColumn = DatabaseSchemaInfo(
            ordinalPosition: (cachedSchema?.columns.count ?? 0) + 1,
            columnName: generateUniqueColumnName(),
            dataType: "",
            formatType: "character varying",
            typeOid: 1043,
            isNullable: "YES",
            columnDefault: nil
        )

        schemaModificationTracker.trackColumnAddition(newColumn)

        NotificationCenter.default.post(
            name: .tableReloadData,
            object: nil,
            userInfo: ["autoEditLastRow": true, "tabID": tab.id.uuidString]
        )
    }

    func generateUniqueColumnName() -> String {
        let existingNames = Set((cachedSchema?.columns ?? []).map { $0.columnName })
        var counter = 1
        var name = "new_column"
        while existingNames.contains(name) || schemaModificationTracker.isColumnNew(name) {
            name = "new_column_\(counter)"
            counter += 1
        }
        return name
    }

    // MARK: - Clipboard Parsing

    func parseClipboardContent(_ content: String, schema: DatabaseSchemaResult) -> [DatabaseRawRow] {
        if let jsonRows = parseJSONClipboard(content, schema: schema), !jsonRows.isEmpty {
            return jsonRows
        }
        return parseTSVClipboard(content, schema: schema)
    }

    private func parseJSONClipboard(_ content: String, schema: DatabaseSchemaResult) -> [DatabaseRawRow]? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let jsonArray: [[String: Any]]
        if let array = json as? [[String: Any]] {
            jsonArray = array
        } else if let single = json as? [String: Any] {
            jsonArray = [single]
        } else {
            return nil
        }

        var result: [DatabaseRawRow] = []
        for jsonRow in jsonArray {
            var rowData: DatabaseRawRow = [:]
            for column in schema.columns {
                if let value = jsonRow[column.columnName],
                   !(value is NSNull),
                   let databaseValue = makeDatabaseValue(from: value) {
                    rowData[column.columnName] = databaseValue
                }
            }
            result.append(rowData)
        }
        return result
    }

    private func parseTSVClipboard(_ content: String, schema: DatabaseSchemaResult) -> [DatabaseRawRow] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        let columns = schema.columns
        var result: [DatabaseRawRow] = []

        for line in lines {
            let values = line.components(separatedBy: "\t")
            var rowData: DatabaseRawRow = [:]

            for (index, column) in columns.enumerated() {
                if index < values.count {
                    let value = values[index]
                    if !value.isEmpty,
                       value.uppercased() != "NULL",
                       let databaseValue = makeDatabaseValue(from: value) {
                        rowData[column.columnName] = databaseValue
                    }
                }
            }
            result.append(rowData)
        }

        return result
    }

    // MARK: - Filter

    func updateFilterConditions() {
        let tabFilterChanged = lastTabFilterColumn != tab.filterColumn
            || lastTabFilterValue != tab.filterValue
        let hasManualFilters = filterConditions.count > 1
            || (filterConditions.count == 1 && !filterConditions[0].value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        if let filterColumn = tab.filterColumn,
           let filterValue = tab.filterValue {
            if tabFilterChanged || !hasManualFilters {
                filterConditions = [FilterCondition(
                    conjunction: .whereClause,
                    field: filterColumn,
                    filterOperator: .equals,
                    value: filterValue
                )]
            }
        } else if !hasManualFilters {
            filterConditions = [FilterCondition(conjunction: .whereClause, field: "", filterOperator: .equals, value: "")]
        }

        lastTabFilterColumn = tab.filterColumn
        lastTabFilterValue = tab.filterValue
    }

    func generateInitialFilter() -> String? {
        guard let filterColumn = tab.filterColumn,
              let filterValue = tab.filterValue else {
            return nil
        }

        let conditions = [FilterCondition(
            conjunction: .whereClause,
            field: filterColumn,
            filterOperator: .equals,
            value: filterValue
        )]

        return instance.databaseService.generateFilterQuery(from: conditions, tableName: tab.name, databaseSchema: tab.databaseSchema)
    }

    // MARK: - Real-time Subscriptions

    func subscribeToRealTimeUpdatesIfSupported(page: Int = 1) async {
        guard shouldUseRealtime(for: currentActiveFilter) && !isSubscribedToRealTime else {
            return
        }

        do {
            let onUpdate: @Sendable (QueryResult) -> Void = { [weak self] updatedResult in
                Task { @MainActor in
                    self?.handleRealTimeUpdate(updatedResult)
                }
            }
            let onError: @Sendable (Error) -> Void = { [weak self] error in
                Task { @MainActor in
                    self?.handleRealTimeError(error)
                }
            }
            try await instance.databaseService.subscribeToTableChanges(
                tabId: tab.id,
                tableName: tab.name,
                schema: tab.databaseSchema,
                filter: currentActiveFilter,
                limit: 300,
                sortBy: sortColumn,
                ascending: sortAscending,
                page: page,
                onUpdate: onUpdate,
                onError: onError
            )
            isSubscribedToRealTime = true
            debugLog("✅ Subscribed to real-time updates for table: \(tab.name)")
        } catch {
            debugLog("❌ Failed to subscribe to real-time updates: \(error)")
        }
    }

    func handleRealTimeUpdate(_ updatedResult: QueryResult) {
        receivedFirstRealtimeEvent = true

        if skipNextRealtimeEvent {
            skipNextRealtimeEvent = false
            changeDetector.baseline(with: updatedResult)
            fetchSchemaIfNeeded()
            forceViewStateRefresh(with: updatedResult, schema: cachedSchema)
            cachedDocuments = updatedResult
            return
        }

        let change: TableChangeDetector.ChangeResult
        if cachedDocuments == nil && changeDetector.lastHash == nil {
            changeDetector.baseline(with: updatedResult)
            change = .init(changedFields: [], changedRows: [], changedCells: [:], isDifferent: true)
        } else {
            let oldCount = cachedDocuments?.rawRows.count ?? 0
            let newCount = updatedResult.rawRows.count
            if oldCount != newCount {
                change = changeDetector.detectExclusive(old: cachedDocuments, new: updatedResult)
            } else {
                change = changeDetector.detect(old: cachedDocuments, new: updatedResult)
            }
        }

        guard change.isDifferent else {
            debugLog("📊 Real-time update skipped - no changes detected for table: \(tab.name)")
            return
        }

        fetchSchemaIfNeeded()

        var fields = Set<String>()
        var rows = Set<Int>()
        for (rowIndex, cols) in change.changedCells {
            rows.insert(rowIndex)
            fields.formUnion(cols)
        }
        updatedFields = fields
        updatedRows = rows

        forceViewStateRefresh(with: updatedResult, schema: cachedSchema)

        cachedDocuments = updatedResult

        modificationTracker.reconcile(changedCells: change.changedCells, in: updatedResult)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.updatedFields.removeAll()
            self?.updatedRows.removeAll()
        }
    }

    private func fetchSchemaIfNeeded() {
        guard cachedSchema == nil, !isFetchingSchema else { return }
        isFetchingSchema = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isFetchingSchema = false }
            if let schema = try? await instance.databaseService.getSchema(for: tab.name, databaseSchema: tab.databaseSchema) {
                self.cachedSchema = schema
            }
        }
    }

    private func handleRealTimeError(_ error: Error) {
        debugLog("❌ Real-time subscription error: \(error)")
        isSubscribedToRealTime = false
    }

    func cancelRealTimeSubscription() {
        guard isSubscribedToRealTime else { return }
        instance.databaseService.cancelSubscription(forTabId: tab.id)
        isSubscribedToRealTime = false
        debugLog("🛑 Cancelled real-time subscription for table: \(tab.name)")
    }

    // MARK: - Helpers

    private func hasColumnMismatch(queryResult: QueryResult?, schema: DatabaseSchemaResult?) -> Bool {
        guard let queryResult, let schema, !queryResult.columns.isEmpty else {
            return false
        }
        let queryColumnNames = Set(queryResult.columns.map(\.name))
        let schemaColumnNames = Set(schema.columns.map(\.columnName))
        return queryColumnNames != schemaColumnNames
    }

    private func shouldUseRealtime(for filter: String?) -> Bool {
        guard instance.databaseService.supportsRealTime else {
            return false
        }

        if instance.connection.databaseType == .convex,
           ConvexDriver.isExecutableRawQuery(filter) {
            return false
        }

        return true
    }

    private func queryColumns(from schema: DatabaseSchemaResult) -> [QueryColumnInfo] {
        schema.columns.enumerated().map { index, column in
            QueryColumnInfo(
                name: column.columnName,
                dataType: column.dataType,
                format: column.formatType,
                index: index
            )
        }
    }

    private func updateTabSchemaDeviation(_ hasDeviation: Bool) {
        if let tabIndex = instance.tabs.firstIndex(where: { $0.id == tab.id }) {
            instance.tabs[tabIndex].hasSchemaDeviation = hasDeviation
        }
    }

    // MARK: - Notification Handling

    func handleMarkRowAsDeleted(rowIndex: Int, tableName: String) {
        guard tableName == tab.name else { return }

        modificationTracker.markAsDeleted(rowIndex: rowIndex)

        NotificationCenter.default.post(
            name: .tableReloadData,
            object: nil,
            userInfo: ["tableName": tableName, "tabID": tab.id.uuidString]
        )
    }
}
