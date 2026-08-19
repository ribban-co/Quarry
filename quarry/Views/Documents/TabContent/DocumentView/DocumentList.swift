
import SwiftUI
import AppKit
import MongoKitten

struct DocumentList: View {
    @Bindable var selectedTab: DatabaseTab
    @Environment(ConnectionInstance.self) private var instance
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    @State private var viewState: TableListViewState = .loading
    @State private var currentActiveFilter: String? = nil

    // Caching
    @State private var cachedDocuments: QueryResult?
    @State private var cachedTabName: String?

    // Modification tracking
    @State private var modificationTracker = TableModificationTracker()
    @State private var isProcessingUpdates = false
    
    let schemaToUse = DatabaseSchemaResult(tableName: "", schemaName: "", columns: [], totalCount: 0)
    
    /// Extract current query result from viewState
    private var currentQueryResult: QueryResult? {
        if case .loaded(let queryResult, _) = viewState {
            return queryResult
        }
        
        return nil
    }
    
    var body: some View {
        ZStack {
            if let queryResult = currentQueryResult {
                DocumentListScrollView(queryResult: queryResult) {
                    await loadDocuments(page: 1, limit: 300)
                }
            }
            
            // Floating Action bar:
            VStack {
                Spacer()
                FloatingActionBar(
                    tabID: selectedTab.id,
                    viewState: viewState,
                    tableName: selectedTab.name,
                    tabViewMode: $selectedTab.viewMode,
                    modificationTracker: modificationTracker,
                    isProcessingUpdates: isProcessingUpdates,
                    onRefresh: { currentPage, itemsPerPage, fetchSchema in
                        Task {
                            await loadDocuments(page: currentPage, limit: itemsPerPage)
                        }
                    },
                    onLoadDocuments: { filter in
                        Task {
                            // Update the active filter state for persistence across refreshes
                            currentActiveFilter = filter?.isEmpty == true ? nil : filter

                            // Load documents with the new filter, resetting to page 1
                            await loadDocuments(page: 1, limit: 300, filter: filter)
                        }
                    },
                    onCommitModifications: {
                        //                            Task {
                        //                                isProcessingUpdates = true
                        //                                await commitModifications()
                        //                                isProcessingUpdates = false
                        //                            }
                    },
                    onNewRecord: {
                        //                            handleNewRecord()
                    },
                    onDiscardChanges: {
                        // No-op for document view
                    },
                    databaseType: instance.databaseType,
                    currentQueryResult: currentQueryResult,
                    schema: nil,
                    schemaModificationTracker: nil,
                    onCommitSchemaModifications: nil
                )
                .padding(.bottom, 6)
            }
        }
        .padding(.leading, -6)
        .task(id: selectedTab.id) {
            await loadDocumentsIfNeeded()
        }
    }
    
    /// Load documents only if they don't exist in cache or collection has changed
    private func loadDocumentsIfNeeded() async {
        // Check if we need to fetch
        let shouldFetch = cachedTabName != selectedTab.name ||
            cachedDocuments == nil ||
            selectedTab.forceFetch

        if shouldFetch {
            // Generate initial filter if tab has filter info
            let initialFilter = generateInitialFilter()
            currentActiveFilter = initialFilter

            // Fetch fresh data
            await loadDocuments(page: 1, limit: 300, filter: initialFilter)

            // Reset forceFetch flag
            selectedTab.forceFetch = false
        } else {
            // Use cached data - instant load!
            if let cachedDocuments = cachedDocuments {
                viewState = .loaded(cachedDocuments, schemaToUse)
            }
        }
    }

    /// Load documents with options to force fetch and control schema fetching
    private func loadDocuments(page: Int = 1, limit: Int = 300, filter: String? = nil) async {
        do {
            viewState = .loading

            let queryResult = try await instance.databaseService.findDocuments(
                in: selectedTab.name,
                databaseSchema: nil,
                filter: filter ?? currentActiveFilter ?? "",
                skip: (page - 1) * limit,
                limit: limit,
                sortBy: nil,
                ascending: nil
            )

            // Cache the result for next time
            cachedDocuments = queryResult
            cachedTabName = selectedTab.name

            viewState = .loaded(queryResult, schemaToUse)
        } catch {
            debugLog(error.localizedDescription)
            viewState = .error(error.localizedDescription)
        }
    }

    private func generateInitialFilter() -> String? {
        guard let filterColumn = selectedTab.filterColumn,
              let filterValue = selectedTab.filterValue else {
            return nil
        }

        let conditions = [FilterCondition(
            conjunction: .whereClause,
            field: filterColumn,
            filterOperator: .equals,
            value: filterValue
        )]

        return instance.databaseService.generateFilterQuery(
            from: conditions,
            tableName: selectedTab.name,
            databaseSchema: selectedTab.databaseSchema
        )
    }
}

struct DocumentListScrollView: View {
    let queryResult: QueryResult
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(queryResult.rows.enumerated()), id: \.offset) { index, document in
                    DocumentRowView(
                        document: document,
                        index: index,
                        onRefresh: onRefresh
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 2)
                    .padding(.leading, 10)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 24)
            
            Spacer()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if queryResult.rows.isEmpty {
                ContentUnavailableView {
                    Label("No Documents Available", systemImage: "tray")
                        .font(.title2)
                } description: {
                    Text("This collection doesn't contain any documents yet.\nAdd your first document or import data to get started.")
                } actions: {
                    Button {
                        Task {
                            await onRefresh()
                        }
                    } label: {
                        Text("Refresh")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
