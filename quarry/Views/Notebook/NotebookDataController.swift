import SwiftData
import SwiftUI

enum NotebookViewMode: String {
    case notebook
    case dashboard
}

@Observable
@MainActor
final class NotebookDataController {

    private static let defaultTextBlockHeight = 140.0
    private static let staleRefreshInterval: TimeInterval = 5 * 60

    let notebookId: UUID
    let modelContainer: ModelContainer

    private(set) var notebook: Notebook?
    private(set) var connections: [Connection] = []
    private(set) var blocks: [NotebookBlock] = []
    var isRightSidebarVisible = false
    var pendingAgentMessage: String?
    var pendingAgentConnections: [Connection]?
    var viewMode: NotebookViewMode = .notebook
    var isScrolled = false
    var isPublishPreviewing = false
    var isViewingPublished = false
    var isAgentStreaming = false

    private var sidebarVisibleBeforePreview = false

    private var chartViewModels: [UUID: ChartBlockViewModel] = [:]
    private var singleValueViewModels: [UUID: SingleValueBlockViewModel] = [:]
    private var queryViewModels: [UUID: QueryBlockViewModel] = [:]

    var hasBlocks: Bool { !blocks.isEmpty }

    private(set) var cachedDashboardBlocks: [NotebookBlock] = []

    var isPublished: Bool {
        get { notebook?.isPublished ?? false }
        set {
            notebook?.isPublished = newValue
            notebook?.updatedAt = Date()
            save()
        }
    }

    var isDashboardPublished: Bool {
        isViewingPublished
    }

    func invalidateDashboardBlocks() {
        cachedDashboardBlocks = blocks.filter { !$0.isHiddenInDashboard }.sorted { $0.dashboardSortOrder < $1.dashboardSortOrder }
    }

    /// Enters preview in one synchronous batch so every observer coalesces into
    /// a single transition instead of one per flag.
    func beginPublishPreview() {
        guard !isPublishPreviewing else { return }
        sidebarVisibleBeforePreview = isRightSidebarVisible
        isRightSidebarVisible = false
        viewMode = .dashboard
        isPublishPreviewing = true
        refreshIfStale()
    }

    func cancelPublishPreview() {
        guard isPublishPreviewing else { return }
        isPublishPreviewing = false
        viewMode = .notebook
        isRightSidebarVisible = sidebarVisibleBeforePreview
    }

    func publishDashboard() {
        isPublishPreviewing = false
        isPublished = true
        isViewingPublished = true
        isRightSidebarVisible = false
    }

    func unpublishDashboard() {
        isPublished = false
        isViewingPublished = false
    }

    var isRefreshing = false

    var lastRefreshedAt: Date? {
        notebook?.lastRefreshedAt
    }

    /// Preview shouldn't blank every card on a notebook that was just refreshed.
    func refreshIfStale() {
        guard !isRefreshing else { return }
        guard let last = lastRefreshedAt else {
            rerunAllQueries()
            return
        }
        guard Date().timeIntervalSince(last) > Self.staleRefreshInterval else { return }
        rerunAllQueries()
    }

    func rerunAllQueries() {
        isRefreshing = true
        let chartTasks = chartViewModels.values.map { vm in
            Task { await vm.reconnectAndRefresh() }
        }
        let singleValueTasks = singleValueViewModels.values.map { vm in
            Task { await vm.reconnectAndRefresh() }
        }
        let queryTasks = queryViewModels.values.map { vm in
            Task { await vm.reconnectAndRefresh() }
        }
        Task {
            for task in chartTasks { await task.value }
            for task in singleValueTasks { await task.value }
            for task in queryTasks { await task.value }
            notebook?.lastRefreshedAt = Date()
            save()
            isRefreshing = false
        }
    }

    func toggleBlockDashboardVisibility(_ block: NotebookBlock) {
        block.isHiddenInDashboard.toggle()
        block.updatedAt = Date()
        invalidateDashboardBlocks()
        save()
    }

    var title: String {
        get { notebook?.title ?? "Untitled Notebook" }
        set {
            notebook?.title = newValue
            notebook?.updatedAt = Date()
            save()
        }
    }

    var descriptionText: String {
        get { notebook?.descriptionText ?? "" }
        set {
            notebook?.descriptionText = newValue
            notebook?.updatedAt = Date()
            save()
        }
    }

    var status: NotebookStatus {
        get { notebook?.status ?? .exploratory }
        set {
            notebook?.status = newValue
            notebook?.updatedAt = Date()
            save()
        }
    }

    init(notebookId: UUID, modelContainer: ModelContainer) {
        self.notebookId = notebookId
        self.modelContainer = modelContainer
    }

    func load() {
        let context = modelContainer.mainContext
        let id = notebookId

        let notebookDescriptor = FetchDescriptor<Notebook>(
            predicate: #Predicate { $0.id == id }
        )
        notebook = try? context.fetch(notebookDescriptor).first

        refreshConnections()

        let blockDescriptor = FetchDescriptor<NotebookBlock>(
            predicate: #Predicate { $0.notebookId == id },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        blocks = (try? context.fetch(blockDescriptor)) ?? []

        if blocks.count >= 2, blocks.allSatisfy({ $0.dashboardSortOrder == 0 }) {
            for (i, block) in blocks.enumerated() {
                block.dashboardSortOrder = i
            }
            save()
        }
        invalidateDashboardBlocks()

        if isPublished {
            viewMode = .dashboard
            isViewingPublished = true
        }
    }

    func addChartBlock() {
        addBlock(type: .chart)
    }

    func insertChartBlock(at index: Int) {
        insertBlock(type: .chart, at: index)
    }

    func addTextBlock() {
        addBlock(type: .text)
    }

    func insertTextBlock(at index: Int) {
        insertBlock(type: .text, at: index)
    }

    func addSingleValueBlock() {
        addBlock(type: .singleValue)
    }

    func insertSingleValueBlock(at index: Int) {
        insertBlock(type: .singleValue, at: index)
    }

    func addQueryBlock() {
        addBlock(type: .query)
    }

    func insertQueryBlock(at index: Int) {
        insertBlock(type: .query, at: index)
    }

    private func addBlock(type: NotebookBlockType) {
        guard let notebook else { return }
        let nextOrder = (blocks.map(\.sortOrder).max() ?? -1) + 1
        let block = NotebookBlock(notebookId: notebook.id, blockType: type, sortOrder: nextOrder)
        block.dashboardSortOrder = nextDashboardOrder()
        if type == .singleValue {
            block.blockHeight = 120
            block.blockWidthFraction = 0.25
        } else if type == .query {
            block.blockHeight = 380
        } else if type == .text {
            block.blockHeight = Self.defaultTextBlockHeight
        }
        modelContainer.mainContext.insert(block)
        blocks.append(block)
        invalidateDashboardBlocks()
        save()
    }

    private func insertBlock(type: NotebookBlockType, at index: Int) {
        guard let notebook else { return }
        let block = NotebookBlock(notebookId: notebook.id, blockType: type, sortOrder: index)
        block.dashboardSortOrder = nextDashboardOrder()
        if type == .singleValue {
            block.blockHeight = 120
            block.blockWidthFraction = 0.25
        } else if type == .query {
            block.blockHeight = 380
        } else if type == .text {
            block.blockHeight = Self.defaultTextBlockHeight
        }
        modelContainer.mainContext.insert(block)
        blocks.insert(block, at: index)
        reindexSortOrders()
        invalidateDashboardBlocks()
        save()
    }

    func chartViewModel(for block: NotebookBlock) -> ChartBlockViewModel {
        if let existing = chartViewModels[block.id] {
            return existing
        }
        let vm = ChartBlockViewModel(block: block, dataController: self)
        chartViewModels[block.id] = vm
        return vm
    }

    func singleValueViewModel(for block: NotebookBlock) -> SingleValueBlockViewModel {
        if let existing = singleValueViewModels[block.id] {
            return existing
        }
        let vm = SingleValueBlockViewModel(block: block, dataController: self)
        singleValueViewModels[block.id] = vm
        return vm
    }

    func queryViewModel(for block: NotebookBlock) -> QueryBlockViewModel {
        if let existing = queryViewModels[block.id] {
            return existing
        }
        let vm = QueryBlockViewModel(block: block, dataController: self)
        queryViewModels[block.id] = vm
        return vm
    }

    // MARK: - Query Data Source Registry

    struct QueryDataSource {
        let blockId: UUID
        let outputName: String
        let result: QueryResult
    }

    var availableQueryDataSources: [QueryDataSource] {
        queryViewModels.compactMap { (id, vm) in
            guard let result = vm.queryResult,
                  let config = vm.config,
                  !config.outputName.isEmpty else { return nil }
            return QueryDataSource(blockId: id, outputName: config.outputName, result: result)
        }
    }

    func queryResult(for blockId: UUID) -> QueryResult? {
        if let liveResult = queryViewModels[blockId]?.queryResult {
            return liveResult
        }

        guard let block = blocks.first(where: { $0.id == blockId && $0.blockType == .query }),
              let cachedResult = block.cachedQueryData() else {
            return nil
        }

        return cachedResult.toQueryResult()
    }

    func rerunQueryBlock(blockId: UUID) async -> QueryBlockViewModel? {
        guard let block = blocks.first(where: { $0.id == blockId && $0.blockType == .query }) else {
            return nil
        }

        let vm = queryViewModel(for: block)
        guard let cfg = vm.config, !cfg.connectionKeychainId.isEmpty else {
            await vm.executeQuery()
            return vm
        }

        await vm.reconnectAndRefresh()
        return vm
    }

    func queryBlockDidUpdate(blockId: UUID) {
        let blockIdString = blockId.uuidString
        for (_, vm) in chartViewModels {
            if vm.config?.sourceQueryBlockId == blockIdString {
                vm.refreshQuerySourceSchema()
                Task { await vm.fetchChartData() }
            }
        }
        for (_, vm) in singleValueViewModels {
            if vm.config?.sourceQueryBlockId == blockIdString {
                Task { await vm.fetchSingleValue() }
            }
        }
    }

    func deleteBlock(_ block: NotebookBlock) {
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            if !block.notebookInline, index + 1 < blocks.count, blocks[index + 1].notebookInline {
                blocks[index + 1].notebookInline = false
            }
            if !block.dashboardInline, index + 1 < blocks.count, blocks[index + 1].dashboardInline {
                blocks[index + 1].dashboardInline = false
            }
        }
        // Disconnect removed view models' driver sessions instead of leaving
        // that to controller deinit, which may run much later (or never while
        // something still retains the view model).
        let chartVM = chartViewModels.removeValue(forKey: block.id)
        let singleValueVM = singleValueViewModels.removeValue(forKey: block.id)
        let queryVM = queryViewModels.removeValue(forKey: block.id)
        Task {
            await chartVM?.cleanup()
            await singleValueVM?.cleanup()
            await queryVM?.cleanup()
        }
        modelContainer.mainContext.delete(block)
        blocks.removeAll { $0.id == block.id }
        reindexSortOrders()
        invalidateDashboardBlocks()
        reindexDashboardSortOrders()
        save()
    }

    func duplicateBlock(_ block: NotebookBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        guard let notebook else { return }
        let newBlock = NotebookBlock(notebookId: notebook.id, blockType: block.blockType, sortOrder: index + 1)
        newBlock.configJSON = block.configJSON
        newBlock.blockHeight = block.blockHeight
        newBlock.blockWidthFraction = block.blockWidthFraction
        newBlock.dashboardInline = block.dashboardInline
        newBlock.notebookInline = false
        newBlock.dashboardSortOrder = nextDashboardOrder()
        modelContainer.mainContext.insert(newBlock)
        blocks.insert(newBlock, at: index + 1)
        reindexSortOrders()
        invalidateDashboardBlocks()
        reindexDashboardSortOrders()
        save()
    }

    func moveBlockUp(_ block: NotebookBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }), index > 0 else { return }
        if !block.notebookInline, index + 1 < blocks.count, blocks[index + 1].notebookInline {
            blocks[index + 1].notebookInline = false
        }
        blocks.swapAt(index, index - 1)
        if blocks[index].notebookInline, index > 0, !blocks[index - 1].notebookInline {
            blocks[index].notebookInline = false
        }
        reindexSortOrders()
        save()
    }

    func moveBlockDown(_ block: NotebookBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }), index < blocks.count - 1 else { return }
        if !block.notebookInline, index + 1 < blocks.count, blocks[index + 1].notebookInline {
            blocks[index + 1].notebookInline = false
        }
        blocks.swapAt(index, index + 1)
        block.notebookInline = false
        reindexSortOrders()
        save()
    }

    func moveBlock(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < blocks.count,
              destinationIndex >= 0, destinationIndex <= blocks.count else { return }
        let block = blocks.remove(at: sourceIndex)
        let insertIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        blocks.insert(block, at: min(insertIndex, blocks.count))
        reindexSortOrders()
        save()
    }

    func updateBlock(_ block: NotebookBlock) {
        block.updatedAt = Date()
        save()
    }

    func saveContext() {
        save()
    }

    func refreshChartViewModel(for blockId: UUID, config _: ChartBlockConfig) {
        guard let vm = chartViewModels[blockId] else { return }
        vm.reloadConfig()
    }

    func refreshSingleValueViewModel(for blockId: UUID) {
        singleValueViewModels[blockId]?.reloadConfig()
    }

    func refreshQueryViewModel(for blockId: UUID) {
        queryViewModels[blockId]?.reloadConfig()
    }

    func moveDashboardBlock(from sourceIndex: Int, to destinationIndex: Int) {
        var dash = cachedDashboardBlocks
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < dash.count,
              destinationIndex >= 0, destinationIndex <= dash.count else { return }
        let block = dash.remove(at: sourceIndex)
        let insertIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        dash.insert(block, at: min(insertIndex, dash.count))
        for (i, b) in dash.enumerated() {
            b.dashboardSortOrder = i
        }
        invalidateDashboardBlocks()
        save()
    }

    private func reindexSortOrders() {
        for (i, block) in blocks.enumerated() {
            block.sortOrder = i
        }
    }

    private func reindexDashboardSortOrders() {
        for (i, block) in cachedDashboardBlocks.enumerated() {
            block.dashboardSortOrder = i
        }
    }

    private func nextDashboardOrder() -> Int {
        (blocks.map(\.dashboardSortOrder).max() ?? -1) + 1
    }

    func refreshConnections() {
        let connectionDescriptor = FetchDescriptor<Connection>(
            sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
        )
        connections = (try? modelContainer.mainContext.fetch(connectionDescriptor)) ?? []
    }

    private func save() {
        try? modelContainer.mainContext.save()
    }
}
