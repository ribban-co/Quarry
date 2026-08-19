import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class NotebookBlocksController: NSViewController {

    private let dataController: NotebookDataController
    private let headerView: NSView?

    var onScrollOffsetChanged: ((CGFloat) -> Void)?

    private var scrollView: NSScrollView!
    private var collectionView: NSCollectionView!
    private var collectionHeightConstraint: NSLayoutConstraint?
    nonisolated(unsafe) private var scrollBoundsObserver: NSObjectProtocol?

    private var blockControllers: [UUID: NSViewController] = [:]
    private var actionBarView: NotebookActionBarView?
    private var actionBarContainer: NSView!
    private var insertionIndicators: [BlockInsertionIndicatorView] = []
    private var inlineActionBar: NotebookActionBarView?
    private var expandedGapIndex: Int?
    nonisolated(unsafe) private var clickAwayMonitor: Any?
    private var pendingFocusBlockId: UUID?
    private var initialLoadComplete = false
    private var previousBlockIds: [UUID] = []
    private var lastKnownWidth: CGFloat = 0
    private var isLayoutFrozen = false

    private let dragController = BlockDragController()
    private var currentDropIntent: NotebookDropIntent?
    private var dropIndicatorLayer: CAShapeLayer?
    private var dimOverlayLayer: CALayer?
    private var itemHighlightLayers: [CAShapeLayer] = []
    private var divisionPreviewLayers: [CAShapeLayer] = []

    private enum NotebookDropIntent: Equatable {
        case insertRow(beforeIndex: Int)
        case insertInRow(rowIndex: Int, hoveredItemIndex: Int)
    }

    init(dataController: NotebookDataController, headerView: NSView? = nil) {
        self.dataController = dataController
        self.headerView = headerView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
        if let clickAwayMonitor {
            NSEvent.removeMonitor(clickAwayMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        setupCollectionView()
        observeBlocks()
        observeViewMode()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLayoutFreeze),
            name: .notebookChartFreeze,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLayoutUnfreeze),
            name: .notebookChartUnfreeze,
            object: nil
        )
    }

    @objc private func handleLayoutFreeze(_ notification: Notification) {
        guard notification.object as? NSWindow == view.window else { return }
        isLayoutFrozen = true
    }

    @objc private func handleLayoutUnfreeze(_ notification: Notification) {
        guard notification.object as? NSWindow == view.window else { return }
        isLayoutFrozen = false
        let currentWidth = collectionView.bounds.width
        if currentWidth != lastKnownWidth, currentWidth > 0 {
            lastKnownWidth = currentWidth
            invalidateLayoutAndHeight()
        }
    }

    // MARK: - Setup

    func setTopContentInset(_ inset: CGFloat) {
        scrollView.contentInsets.top = inset
    }

    var currentScrollOffset: CGFloat {
        max(0, scrollView.contentView.bounds.origin.y)
    }

    private func setupCollectionView() {
        let layout = NotebookGridLayout()
        layout.dataController = dataController

        collectionView = NonRecyclingCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(NotebookChartItem.self, forItemWithIdentifier: NotebookChartItem.identifier)
        collectionView.register(NotebookTextItem.self, forItemWithIdentifier: NotebookTextItem.identifier)
        collectionView.register(NotebookSingleValueItem.self, forItemWithIdentifier: NotebookSingleValueItem.identifier)
        collectionView.register(NotebookQueryItem.self, forItemWithIdentifier: NotebookQueryItem.identifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.onLayout = { [weak self] in
            self?.updateInsertionIndicators()
        }

        if let headerView {
            headerView.translatesAutoresizingMaskIntoConstraints = false
            documentView.addSubview(headerView)

            NSLayoutConstraint.activate([
                headerView.topAnchor.constraint(equalTo: documentView.topAnchor),
                headerView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
                headerView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            ])
        }

        documentView.addSubview(collectionView)

        let collectionTopAnchor = headerView?.bottomAnchor ?? documentView.topAnchor
        let heightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 0)
        collectionHeightConstraint = heightConstraint

        actionBarContainer = NSView()
        actionBarContainer.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(actionBarContainer)

        setupActionBar()

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: collectionTopAnchor),
            collectionView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            heightConstraint,

            actionBarContainer.topAnchor.constraint(equalTo: collectionView.bottomAnchor),
            actionBarContainer.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            actionBarContainer.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            actionBarContainer.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: collectionView.widthAnchor),
        ])

        scrollView = NSScrollView()
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let offset = max(0, self.scrollView.contentView.bounds.origin.y)
                self.onScrollOffsetChanged?(offset)
                self.loadVisibleBlockData()
            }
        }
    }

    private func setupActionBar() {
        let bar = NotebookActionBarView(dataController: dataController) { [weak self] in
            self?.scrollToBottom()
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        actionBarContainer.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: actionBarContainer.topAnchor),
            bar.leadingAnchor.constraint(equalTo: actionBarContainer.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: actionBarContainer.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: actionBarContainer.bottomAnchor),
        ])

        actionBarView = bar
    }

    private func updateCollectionHeight() {
        guard let layout = collectionView.collectionViewLayout else {
            return
        }
        collectionView.layoutSubtreeIfNeeded()
        let newHeight = layout.collectionViewContentSize.height
        collectionHeightConstraint?.constant = newHeight
        updateInsertionIndicators()
    }

    private func updateInsertionIndicators() {
        guard let layout = collectionView.collectionViewLayout as? NotebookGridLayout,
              let documentView = scrollView.documentView else { return }

        let rows = layout.cachedRows
        let neededCount = rows.count

        while insertionIndicators.count < neededCount {
            let indicator = BlockInsertionIndicatorView()
            documentView.addSubview(indicator, positioned: .above, relativeTo: collectionView)
            insertionIndicators.append(indicator)
        }
        while insertionIndicators.count > neededCount {
            insertionIndicators.removeLast().removeFromSuperview()
        }

        let collectionOriginY = collectionView.frame.origin.y
        for i in 0..<neededCount {
            let indicator = insertionIndicators[i]
            guard let gapFrame = insertionGapFrame(at: i, rows: rows, collectionOriginY: collectionOriginY) else {
                indicator.isHidden = true
                continue
            }
            indicator.frame = gapFrame

            indicator.isHidden = (expandedGapIndex == i)

            let insertionIndex = i == 0 ? 0 : rows[i].startIndex
            indicator.onPlusTapped = { [weak self] _ in
                self?.expandInsertionGap(indicatorIndex: i, insertionBlockIndex: insertionIndex)
            }
        }

        positionInlineActionBar()
    }

    // MARK: - Inline Insertion Bar

    private func expandInsertionGap(indicatorIndex: Int, insertionBlockIndex: Int) {
        collapseInsertionGap(animated: false)

        expandedGapIndex = indicatorIndex

        guard let layout = collectionView.collectionViewLayout as? NotebookGridLayout else { return }
        layout.insertBarBeforeRowIndex = indicatorIndex

        collectionView.collectionViewLayout?.invalidateLayout()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            self.collectionView.layoutSubtreeIfNeeded()
        }

        updateCollectionHeight()

        let bar = NotebookActionBarView(dataController: dataController, insertionIndex: insertionBlockIndex) { [weak self] in
            self?.collapseInsertionGap(animated: true)
        }
        scrollView.documentView?.addSubview(bar)
        inlineActionBar = bar

        positionInlineActionBar()

        clickAwayMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let bar = self.inlineActionBar else { return event }
            if !bar.containsInteractiveArea(windowPoint: event.locationInWindow) {
                let shouldConsume = self.clickIsInsideExpandedGap(event)
                self.collapseInsertionGap(animated: true)
                return shouldConsume ? nil : event
            }
            return event
        }
    }

    private func collapseInsertionGap(animated: Bool) {
        if let monitor = clickAwayMonitor {
            NSEvent.removeMonitor(monitor)
            clickAwayMonitor = nil
        }

        inlineActionBar?.removeFromSuperview()
        inlineActionBar = nil
        expandedGapIndex = nil

        guard let layout = collectionView.collectionViewLayout as? NotebookGridLayout else { return }
        guard layout.insertBarBeforeRowIndex != nil else { return }
        layout.insertBarBeforeRowIndex = nil

        collectionView.collectionViewLayout?.invalidateLayout()

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                self.collectionView.layoutSubtreeIfNeeded()
            }
        }

        updateCollectionHeight()
    }

    private func positionInlineActionBar() {
        guard let layout = collectionView.collectionViewLayout as? NotebookGridLayout,
              let barFrame = layout.insertBarFrame,
              let bar = inlineActionBar else { return }

        let collectionOriginY = collectionView.frame.origin.y
        let fittingHeight = max(1, bar.fittingSize.height)
        let barHeight = min(barFrame.height, fittingHeight)
        bar.frame = NSRect(
            x: barFrame.origin.x,
            y: barFrame.midY + collectionOriginY - (barHeight / 2),
            width: barFrame.width,
            height: barHeight
        )
    }

    private func clickIsInsideExpandedGap(_ event: NSEvent) -> Bool {
        guard let layout = collectionView.collectionViewLayout as? NotebookGridLayout,
              let gapFrame = layout.insertBarFrame,
              let documentView = scrollView.documentView else {
            return false
        }

        let pointInDocument = documentView.convert(event.locationInWindow, from: nil)
        let frameInDocument = gapFrame.offsetBy(dx: 0, dy: collectionView.frame.origin.y)
        return frameInDocument.contains(pointInDocument)
    }

    // MARK: - Resize

    private func invalidateLayoutAndHeight() {
        collectionView.collectionViewLayout?.invalidateLayout()
        updateCollectionHeight()
    }

    private func handleBlockResize(block: NotebookBlock, newHeight: CGFloat) {
        block.blockHeight = newHeight
        invalidateLayoutAndHeight()
    }

    // MARK: - Block Controllers

    private func blockController(for block: NotebookBlock) -> NSViewController {
        if let existing = blockControllers[block.id] {
            return existing
        }
        let controller: NSViewController
        switch block.blockType {
        case .chart:
            controller = ChartBlockController(block: block, dataController: dataController, showChrome: false)
        case .text:
            let textController = TextBlockController(block: block, dataController: dataController)
            controller = textController
            if initialLoadComplete {
                pendingFocusBlockId = block.id
            }
        case .singleValue:
            controller = SingleValueBlockController(block: block, dataController: dataController, showChrome: false)
        case .query:
            controller = QueryBlockController(block: block, dataController: dataController, showChrome: false)
        }
        addChild(controller)
        blockControllers[block.id] = controller
        return controller
    }

    private var loadedBlockIds: Set<UUID> = []

    private func loadVisibleBlockData() {
        guard loadedBlockIds.count < blockControllers.count,
              let layout = collectionView.collectionViewLayout as? NotebookGridLayout else { return }

        let clipBounds = scrollView.contentView.bounds
        let collectionOriginY = collectionView.frame.origin.y
        let expandedRect = NSRect(
            x: clipBounds.origin.x,
            y: clipBounds.origin.y - collectionOriginY - 300,
            width: clipBounds.width,
            height: clipBounds.height + 600
        )

        let blocks = dataController.blocks
        for attrs in layout.layoutAttributesForElements(in: expandedRect) {
            guard let index = attrs.indexPath?.item, index < blocks.count else { continue }
            let block = blocks[index]
            guard !loadedBlockIds.contains(block.id) else { continue }

            guard let controller = blockControllers[block.id] else { continue }
            switch controller {
            case let chart as ChartBlockController:
                chart.viewModel.loadDataIfNeeded()
            case let singleValue as SingleValueBlockController:
                singleValue.viewModel.loadDataIfNeeded()
            case let query as QueryBlockController:
                query.viewModel.loadDataIfNeeded()
            default:
                break
            }
            loadedBlockIds.insert(block.id)
        }
    }

    private func cleanupRemovedControllers() {
        let currentIds = Set(dataController.blocks.map(\.id))
        for (id, controller) in blockControllers where !currentIds.contains(id) {
            if let chartController = controller as? ChartBlockController {
                chartController.cleanupSession()
            }
            if let singleValueController = controller as? SingleValueBlockController {
                singleValueController.cleanupSession()
            }
            if let queryController = controller as? QueryBlockController {
                queryController.cleanupSession()
            }
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            blockControllers.removeValue(forKey: id)
        }
    }

    // MARK: - Item Wiring

    private func wireItemCallbacks(on item: NotebookBaseItem) {
        item.onResize = { [weak self] block, newHeight in
            self?.handleBlockResize(block: block, newHeight: newHeight)
        }
        item.onDragBegan = { [weak self, weak item] event in
            guard let self, let item, let index = self.currentBlockIndex(for: item) else { return }
            self.beginDrag(blockIndex: index, event: event)
        }
        item.onDragMoved = { [weak self] event in self?.updateDrag(event: event) }
        item.onDragEnded = { [weak self] event in self?.endDrag(event: event) }
        item.onDragCancelled = { [weak self] in self?.cleanupDrag() }
    }

    private func currentBlockIndex(for item: NotebookBaseItem) -> Int? {
        guard let blockID = item.currentBlock?.id else { return nil }
        return dataController.blocks.firstIndex { $0.id == blockID }
    }

    private func wireRunCallback(on item: NotebookBaseItem, action: @escaping () async -> Void) {
        item.onRun = { [weak item] in
            item?.setRunLoading(true)
            Task {
                await action()
                await MainActor.run { item?.setRunLoading(false) }
            }
        }
    }

    private func wireMenuCallback(on item: NotebookBaseItem, block: NotebookBlock) {
        item.onMenuTapped = { [weak self] sender in
            self?.showBlockMenu(for: block, sender: sender)
        }
        item.onTitleChanged = { [weak self] newTitle in
            guard let self else { return }
            block.title = newTitle
            self.dataController.updateBlock(block)
        }
        item.onToggleDashboardVisibility = { [weak self] in
            guard let self else { return }
            self.dataController.toggleBlockDashboardVisibility(block)
            item.configureBase(block: block)
        }
    }

    // MARK: - Block Menu

    private var blockMenuPopover: NSPopover?
    private weak var blockMenuItemRef: NotebookBaseItem?
    private var configPopover: NSPopover?
    private weak var configPopoverItemRef: NotebookBaseItem?

    private func showBlockMenu(for block: NotebookBlock, sender: NSButton) {
        let dc = dataController
        let dismiss = { [weak self] in self?.blockMenuPopover?.performClose(nil) }

        let blockIndex = dc.blocks.firstIndex(where: { $0.id == block.id }) ?? 0
        let isFirst = blockIndex == 0
        let isLast = blockIndex == dc.blocks.count - 1

        let addBlockType: () -> Void
        switch block.blockType {
        case .chart:
            addBlockType = { dc.insertChartBlock(at: blockIndex + 1) }
        case .text:
            addBlockType = { dc.insertTextBlock(at: blockIndex + 1) }
        case .singleValue:
            addBlockType = { dc.insertSingleValueBlock(at: blockIndex + 1) }
        case .query:
            addBlockType = { dc.insertQueryBlock(at: blockIndex + 1) }
        }

        let popoverVC = BlockMenuPopoverController(
            canMoveUp: !isFirst,
            canMoveDown: !isLast,
            onAddAbove: { dismiss(); dc.insertTextBlock(at: blockIndex) },
            onAddBelow: { dismiss(); addBlockType() },
            onMoveUp: { dismiss(); dc.moveBlockUp(block) },
            onMoveDown: { dismiss(); dc.moveBlockDown(block) },
            onDuplicate: { dismiss(); dc.duplicateBlock(block) },
            isHiddenInDashboard: block.isHiddenInDashboard,
            onToggleDashboardVisibility: { dismiss(); dc.toggleBlockDashboardVisibility(block) },
            onDelete: { dismiss(); dc.deleteBlock(block) }
        )

        let item = collectionView.item(at: IndexPath(item: blockIndex, section: 0)) as? NotebookBaseItem
        item?.isMenuForceHovered = true
        item?.forceActionBarVisible = true

        let pop = NSPopover()
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.delegate = self
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        self.blockMenuPopover = pop
        self.blockMenuItemRef = item
    }

    // MARK: - Observation

    private func observeBlocks() {
        if previousBlockIds.isEmpty {
            previousBlockIds = dataController.blocks.map(\.id)
        }
        withObservationTracking {
            _ = self.dataController.blocks.map(\.id)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                guard !self.dragController.isDragging else {
                    self.observeBlocks()
                    return
                }
                self.cleanupRemovedControllers()
                self.loadedBlockIds.formIntersection(self.dataController.blocks.map(\.id))

                if self.view.window != nil, self.collectionView.bounds.width > 0 {
                    self.applyBlocksDiff()
                    self.updateCollectionHeight()
                    self.loadVisibleBlockData()
                    self.initialLoadComplete = true

                    if let focusId = self.pendingFocusBlockId {
                        self.pendingFocusBlockId = nil
                        if let index = self.dataController.blocks.firstIndex(where: { $0.id == focusId }),
                           let textItem = self.collectionView.item(at: IndexPath(item: index, section: 0)) as? NotebookTextItem {
                            textItem.focusEditor()
                        }
                    }
                } else {
                    self.needsReloadOnVisible = true
                }

                self.observeBlocks()
            }
        }
    }

    private var needsReloadOnVisible = false

    private func applyBlocksDiff() {
        let newIds = dataController.blocks.map(\.id)
        let oldIds = previousBlockIds

        guard !oldIds.isEmpty else {
            collectionView.reloadData()
            previousBlockIds = newIds
            return
        }

        let oldSet = Set(oldIds)
        let newSet = Set(newIds)
        let removed = oldSet.subtracting(newSet)
        let inserted = newSet.subtracting(oldSet)

        if removed.isEmpty, inserted.isEmpty, oldIds == newIds {
            previousBlockIds = newIds
            return
        }

        if removed.isEmpty, inserted.count == 1, oldIds.count + 1 == newIds.count {
            let insertedId = inserted.first!
            if let insertIndex = newIds.firstIndex(of: insertedId) {
                let remaining = newIds.filter { $0 != insertedId }
                if remaining == oldIds {
                    collectionView.insertItems(at: [IndexPath(item: insertIndex, section: 0)])
                    previousBlockIds = newIds
                    return
                }
            }
        }

        if inserted.isEmpty, removed.count == 1, oldIds.count - 1 == newIds.count {
            let removedId = removed.first!
            if let removeIndex = oldIds.firstIndex(of: removedId) {
                let remaining = oldIds.filter { $0 != removedId }
                if remaining == newIds {
                    collectionView.deleteItems(at: [IndexPath(item: removeIndex, section: 0)])
                    previousBlockIds = newIds
                    return
                }
            }
        }

        // Same items, different order → move
        if removed.isEmpty, inserted.isEmpty, oldIds.count == newIds.count, Set(oldIds) == Set(newIds) {
            collectionView.performBatchUpdates {
                var working = oldIds
                for (newIndex, id) in newIds.enumerated() {
                    guard let currentIndex = working.firstIndex(of: id) else { continue }
                    if currentIndex != newIndex {
                        working.remove(at: currentIndex)
                        working.insert(id, at: newIndex)
                        collectionView.moveItem(
                            at: IndexPath(item: currentIndex, section: 0),
                            to: IndexPath(item: newIndex, section: 0)
                        )
                    }
                }
            }
            previousBlockIds = newIds
            return
        }

        collectionView.reloadData()
        previousBlockIds = newIds
    }

    private func observeViewMode() {
        withObservationTracking {
            _ = self.dataController.viewMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.dataController.viewMode == .notebook {
                    self.needsReloadOnVisible = true
                }
                self.observeViewMode()
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        if needsReloadOnVisible, view.window != nil {
            needsReloadOnVisible = false
            cleanupRemovedControllers()
            applyBlocksDiff()
            loadVisibleBlockData()
        }

        if !isLayoutFrozen {
            let currentWidth = collectionView.bounds.width
            if currentWidth != lastKnownWidth, currentWidth > 0 {
                lastKnownWidth = currentWidth
                invalidateLayoutAndHeight()
            } else {
                updateCollectionHeight()
            }
        }
    }

    private func scrollToBottom() {
        Task { @MainActor in
            guard let documentView = self.scrollView.documentView else { return }
            let bottomPoint = NSPoint(x: 0, y: documentView.frame.maxY)
            self.scrollView.contentView.scroll(to: bottomPoint)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }
    // MARK: - Drag to Reorder

    private static let titleOffset: CGFloat = 29
    private static let resizeHandleHeight: CGFloat = 12
    private static let singleValueRowTopInset: CGFloat = 16

    private func rowBottomInset(for row: NotebookRowInfo) -> CGFloat {
        guard row.startIndex >= 0, row.endIndex < dataController.blocks.count else {
            return Self.resizeHandleHeight
        }

        let rowBlocks = dataController.blocks[row.startIndex...row.endIndex]
        return rowBlocks.allSatisfy { $0.blockType == .singleValue } ? 0 : Self.resizeHandleHeight
    }

    private func rowTopInset(for row: NotebookRowInfo) -> CGFloat {
        guard row.startIndex >= 0, row.endIndex < dataController.blocks.count else {
            return Self.titleOffset
        }

        let rowBlocks = dataController.blocks[row.startIndex...row.endIndex]
        guard !rowBlocks.isEmpty else { return 0 }
        return rowBlocks.allSatisfy { $0.blockType == .singleValue } ? Self.singleValueRowTopInset : Self.titleOffset
    }

    private func insertionGapFrame(
        at indicatorIndex: Int,
        rows: [NotebookRowInfo],
        collectionOriginY: CGFloat
    ) -> NSRect? {
        guard indicatorIndex >= 0, indicatorIndex < rows.count else { return nil }

        let gapTop: CGFloat
        let gapBottom: CGFloat

        if indicatorIndex == 0 {
            gapTop = collectionOriginY
            gapBottom = rows[0].frame.minY + collectionOriginY
        } else {
            let previousRow = rows[indicatorIndex - 1]
            gapTop = previousRow.frame.maxY + collectionOriginY - rowBottomInset(for: previousRow)
            gapBottom = rows[indicatorIndex].frame.minY + collectionOriginY + rowTopInset(for: rows[indicatorIndex])
        }

        guard gapBottom >= gapTop else { return nil }
        return NSRect(x: 0, y: gapTop, width: collectionView.bounds.width, height: gapBottom - gapTop)
    }

    private func contentRect(from frame: NSRect) -> NSRect {
        NSRect(
            x: frame.minX,
            y: frame.minY + Self.titleOffset,
            width: frame.width,
            height: frame.height - Self.titleOffset - Self.resizeHandleHeight
        )
    }

    private func contentRect(forItemAt itemIndex: Int, layout: NotebookGridLayout) -> NSRect? {
        if let item = collectionView.item(at: IndexPath(item: itemIndex, section: 0)) as? NotebookBaseItem {
            return item.blockContainer.convert(item.blockContainer.bounds, to: collectionView)
        }

        guard let attrs = layout.layoutAttributesForItem(at: IndexPath(item: itemIndex, section: 0)) else {
            return nil
        }

        return contentRect(from: attrs.frame)
    }

    private func contentRect(for row: NotebookRowInfo, layout: NotebookGridLayout) -> NSRect {
        var rowRect: NSRect?

        for itemIndex in row.startIndex...row.endIndex {
            guard let itemRect = contentRect(forItemAt: itemIndex, layout: layout) else { continue }
            rowRect = rowRect?.union(itemRect) ?? itemRect
        }

        return rowRect ?? contentRect(from: row.frame)
    }

    private func beginDrag(blockIndex: Int, event: NSEvent) {
        guard blockIndex >= 0, blockIndex < dataController.blocks.count else { return }

        let block = dataController.blocks[blockIndex]
        dragController.beginDrag(
            sourceIndex: blockIndex,
            block: block,
            event: event,
            snapshotContainer: view,
            dimContainer: scrollView.documentView ?? view
        )

        if let item = collectionView.item(at: IndexPath(item: blockIndex, section: 0)) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                item.view.animator().alphaValue = 0.15
            }
        }

        let overlay = CALayer()
        overlay.isHidden = true
        overlay.cornerRadius = 10
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            overlay.backgroundColor = isDark
                ? NSColor.black.withAlphaComponent(0.3).cgColor
                : NSColor.white.withAlphaComponent(0.4).cgColor
        }
        collectionView.layer?.addSublayer(overlay)
        dimOverlayLayer = overlay

        let indicator = CAShapeLayer()
        indicator.isHidden = true
        collectionView.layer?.addSublayer(indicator)
        dropIndicatorLayer = indicator

        actionBarContainer.isHidden = true
        collapseInsertionGap(animated: false)
        insertionIndicators.forEach { $0.isHidden = true }
    }

    private func updateDrag(event: NSEvent) {
        guard dragController.isDragging else { return }

        dragController.updateSnapshotPosition(event: event, containerView: view)
        dragController.updateAutoScroll(scrollView: scrollView, sourceView: view) { }

        guard let sourceIndex = dragController.dragSourceIndex else { return }
        let locationInCollection = collectionView.convert(event.locationInWindow, from: nil)
        let newIntent = computeDropIntent(at: locationInCollection, sourceIndex: sourceIndex)

        if newIntent != currentDropIntent {
            currentDropIntent = newIntent
            updateDropIndicator(for: newIntent)
        }
    }

    private func endDrag(event: NSEvent) {
        guard let sourceIndex = dragController.dragSourceIndex else {
            cleanupDrag()
            return
        }

        let blocks = dataController.blocks
        guard sourceIndex < blocks.count else {
            cleanupDrag()
            return
        }

        let sourceBlock = blocks[sourceIndex]

        guard let intent = currentDropIntent else {
            cleanupDrag()
            return
        }

        let layout = collectionView.collectionViewLayout as? NotebookGridLayout
        let rows = layout?.cachedRows ?? []
        let sourceRowIndex = rowIndex(containing: sourceIndex, in: rows)

        let oldIds = blocks.map(\.id)

        switch intent {
        case .insertRow(let beforeIndex):
            promoteNextInlineBlock(after: sourceIndex, in: blocks)
            sourceBlock.notebookInline = false
            let destIndex = beforeIndex < rows.count ? rows[beforeIndex].startIndex : blocks.count
            dataController.moveBlock(from: sourceIndex, to: destIndex)

        case .insertInRow(let rowIndex, let hoveredItemIndex):
            guard rowIndex < rows.count else { break }
            let row = rows[rowIndex]
            let isSameRow = sourceRowIndex == rowIndex

            if isSameRow {
                var destIndex = hoveredItemIndex
                if destIndex > sourceIndex { destIndex += 1 }
                dataController.moveBlock(from: sourceIndex, to: destIndex)

                let updatedBlocks = dataController.blocks
                for i in row.startIndex...row.endIndex {
                    guard i < updatedBlocks.count else { break }
                    updatedBlocks[i].notebookInline = (i != row.startIndex)
                }
            } else {
                promoteNextInlineBlock(after: sourceIndex, in: blocks)

                let locationInCollection = collectionView.convert(event.locationInWindow, from: nil)
                let hoveredAttrs = layout?.layoutAttributesForItem(at: IndexPath(item: hoveredItemIndex, section: 0))
                let insertBefore = locationInCollection.x < (hoveredAttrs?.frame.midX ?? 0)
                let targetIndex = insertBefore ? hoveredItemIndex : min(hoveredItemIndex + 1, row.endIndex + 1)

                if targetIndex == row.startIndex {
                    sourceBlock.notebookInline = false
                    blocks[row.startIndex].notebookInline = true
                } else {
                    sourceBlock.notebookInline = true
                }
                dataController.moveBlock(from: sourceIndex, to: targetIndex)
            }
        }

        let newIds = dataController.blocks.map(\.id)

        cleanupDrag()

        collectionView.performBatchUpdates {
            var working = oldIds
            for (newIndex, id) in newIds.enumerated() {
                guard let currentIndex = working.firstIndex(of: id) else { continue }
                if currentIndex != newIndex {
                    working.remove(at: currentIndex)
                    working.insert(id, at: newIndex)
                    self.collectionView.moveItem(
                        at: IndexPath(item: currentIndex, section: 0),
                        to: IndexPath(item: newIndex, section: 0)
                    )
                }
            }
        } completionHandler: { [weak self] _ in
            guard let self else { return }
            self.previousBlockIds = newIds
            self.collectionView.collectionViewLayout?.invalidateLayout()
            self.collectionView.layoutSubtreeIfNeeded()
            self.updateCollectionHeight()
            self.loadVisibleBlockData()
        }
    }

    private func promoteNextInlineBlock(after sourceIndex: Int, in blocks: [NotebookBlock]) {
        let sourceBlock = blocks[sourceIndex]
        guard !sourceBlock.notebookInline, sourceIndex + 1 < blocks.count else { return }
        let nextBlock = blocks[sourceIndex + 1]
        if nextBlock.notebookInline {
            nextBlock.notebookInline = false
        }
    }

    private func cleanupDrag() {
        var needsLayoutReset = false
        if let layout = collectionView.collectionViewLayout as? NotebookGridLayout {
            if layout.insertRowGapBeforeIndex != nil {
                layout.insertRowGapBeforeIndex = nil
                needsLayoutReset = true
            }
            if layout.insertBarBeforeRowIndex != nil {
                layout.insertBarBeforeRowIndex = nil
                needsLayoutReset = true
            }
        }
        expandedGapIndex = nil
        inlineActionBar?.removeFromSuperview()
        inlineActionBar = nil

        if let sourceIndex = dragController.dragSourceIndex,
           let item = collectionView.item(at: IndexPath(item: sourceIndex, section: 0)) {
            item.view.alphaValue = 1
        }

        dragController.cleanup()

        dimOverlayLayer?.removeFromSuperlayer()
        dimOverlayLayer = nil
        dropIndicatorLayer?.removeFromSuperlayer()
        dropIndicatorLayer = nil
        BlockDragController.removeLayers(&itemHighlightLayers)
        BlockDragController.removeLayers(&divisionPreviewLayers)
        currentDropIntent = nil

        actionBarContainer.isHidden = false
        insertionIndicators.forEach { $0.isHidden = false }

        if needsLayoutReset {
            collectionView.collectionViewLayout?.invalidateLayout()
            collectionView.layoutSubtreeIfNeeded()
            updateCollectionHeight()
        }
    }

    // MARK: - Drop Intent

    private func rowIndex(containing itemIndex: Int, in rows: [NotebookRowInfo]) -> Int? {
        rows.firstIndex { itemIndex >= $0.startIndex && itemIndex <= $0.endIndex }
    }

    private func computeDropIntent(at point: NSPoint, sourceIndex: Int) -> NotebookDropIntent? {
        guard let layout = collectionView.collectionViewLayout as? NotebookGridLayout else { return nil }
        let rows = layout.cachedRows
        guard !rows.isEmpty else { return nil }

        if let gapFrame = layout.insertGapFrame, let gapIndex = layout.insertRowGapBeforeIndex {
            let expandedGap = gapFrame.insetBy(dx: 0, dy: -layout.lineSpacing / 2)
            if expandedGap.contains(point) {
                return validatedIntent(.insertRow(beforeIndex: gapIndex), sourceIndex: sourceIndex, rows: rows)
            }
        }

        let lineSpacing = layout.lineSpacing

        for (rowIndex, row) in rows.enumerated() {
            if point.y < row.frame.minY, point.y >= row.frame.minY - lineSpacing / 2 {
                return validatedIntent(.insertRow(beforeIndex: rowIndex), sourceIndex: sourceIndex, rows: rows)
            }

            if point.y >= row.frame.minY, point.y <= row.frame.maxY {
                let blocks = dataController.blocks
                let isSVRow = blocks[row.startIndex].blockType == .singleValue
                let sourceIsSV = blocks[sourceIndex].blockType == .singleValue
                if isSVRow, sourceIsSV {
                    let hoveredItem = findHoveredItemIndex(in: row, at: point.x, layout: layout)
                    return validatedIntent(.insertInRow(rowIndex: rowIndex, hoveredItemIndex: hoveredItem), sourceIndex: sourceIndex, rows: rows)
                } else {
                    let insertBefore = point.y < row.frame.midY
                    let beforeIdx = insertBefore ? rowIndex : rowIndex + 1
                    return validatedIntent(.insertRow(beforeIndex: beforeIdx), sourceIndex: sourceIndex, rows: rows)
                }
            }

            if rowIndex + 1 < rows.count {
                let nextRow = rows[rowIndex + 1]
                if point.y > row.frame.maxY, point.y < nextRow.frame.minY {
                    return validatedIntent(.insertRow(beforeIndex: rowIndex + 1), sourceIndex: sourceIndex, rows: rows)
                }
            }
        }

        if point.y > rows.last!.frame.maxY {
            return validatedIntent(.insertRow(beforeIndex: rows.count), sourceIndex: sourceIndex, rows: rows)
        }

        if point.y < rows.first!.frame.minY {
            return validatedIntent(.insertRow(beforeIndex: 0), sourceIndex: sourceIndex, rows: rows)
        }

        return nil
    }

    private func validatedIntent(_ intent: NotebookDropIntent, sourceIndex: Int, rows: [NotebookRowInfo]) -> NotebookDropIntent? {
        isNoOp(intent, sourceIndex: sourceIndex, rows: rows) ? nil : intent
    }

    private func findHoveredItemIndex(in row: NotebookRowInfo, at x: CGFloat, layout: NotebookGridLayout) -> Int {
        var closest = row.endIndex
        var closestDist = CGFloat.greatestFiniteMagnitude
        for i in row.startIndex...row.endIndex {
            guard let attrs = layout.layoutAttributesForItem(at: IndexPath(item: i, section: 0)) else { continue }
            if x >= attrs.frame.minX, x <= attrs.frame.maxX {
                return i
            }
            let dist = min(abs(x - attrs.frame.minX), abs(x - attrs.frame.maxX))
            if dist < closestDist {
                closestDist = dist
                closest = i
            }
        }
        return closest
    }

    private func isNoOp(_ intent: NotebookDropIntent, sourceIndex: Int, rows: [NotebookRowInfo]) -> Bool {
        let sourceRow = rowIndex(containing: sourceIndex, in: rows)

        switch intent {
        case .insertRow(let beforeIndex):
            guard let srcRow = sourceRow else { return false }
            let isAlone = rows[srcRow].startIndex == rows[srcRow].endIndex
            return isAlone && (beforeIndex == srcRow || beforeIndex == srcRow + 1)

        case .insertInRow(_, let hoveredItemIndex):
            return hoveredItemIndex == sourceIndex
        }
    }

    // MARK: - Drop Indicator

    private func updateDropIndicator(for intent: NotebookDropIntent?) {
        BlockDragController.removeLayers(&divisionPreviewLayers)
        BlockDragController.removeLayers(&itemHighlightLayers)
        guard let indicator = dropIndicatorLayer else { return }
        guard let layout = collectionView.collectionViewLayout as? NotebookGridLayout else { return }

        let newGapIndex: Int? = if case .insertRow(let beforeIndex) = intent { beforeIndex } else { nil }

        if layout.insertRowGapBeforeIndex != newGapIndex {
            layout.insertRowGapBeforeIndex = newGapIndex
            collectionView.collectionViewLayout?.invalidateLayout()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                self.collectionView.layoutSubtreeIfNeeded()
                self.updateCollectionHeight()
            }
        }

        let rows = layout.cachedRows

        guard let intent else {
            indicator.isHidden = true
            dimOverlayLayer?.isHidden = true
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch intent {
        case .insertRow:
            if let gapFrame = layout.insertGapFrame {
                let rect = gapFrame.insetBy(dx: 0.75, dy: 0.75)
                BlockDragController.applyDashedStyle(to: indicator, rect: rect, fillAlpha: 0.04, strokeAlpha: 0.3)
                indicator.isHidden = false
            }
            dimOverlayLayer?.isHidden = true

        case .insertInRow(let rowIndex, let hoveredItemIndex):
            guard rowIndex < rows.count, let sourceIndex = dragController.dragSourceIndex else {
                indicator.isHidden = true
                dimOverlayLayer?.isHidden = true
                break
            }

            let row = rows[rowIndex]
            let sourceRowIndex = self.rowIndex(containing: sourceIndex, in: rows)
            let isSameRow = sourceRowIndex == rowIndex

            dimOverlayLayer?.frame = contentRect(for: row, layout: layout)
            dimOverlayLayer?.isHidden = false

            if isSameRow {
                addItemHighlights(row: row, layout: layout)

                guard let hoveredRect = contentRect(forItemAt: hoveredItemIndex, layout: layout) else {
                    indicator.isHidden = true
                    break
                }

                let rect = hoveredRect.insetBy(dx: -0.5, dy: -0.5)
                BlockDragController.applyDashedStyle(to: indicator, rect: rect, fillAlpha: 0.06, strokeAlpha: 0.35)
                indicator.isHidden = false
            } else {
                indicator.isHidden = true
                showDivisionPreview(row: row, hoveredItemIndex: hoveredItemIndex, layout: layout)
            }
        }

        CATransaction.commit()
    }

    private func addItemHighlights(row: NotebookRowInfo, layout: NotebookGridLayout) {
        for i in row.startIndex...row.endIndex {
            guard i != dragController.dragSourceIndex else { continue }
            guard let rect = contentRect(forItemAt: i, layout: layout) else { continue }

            let shape = BlockDragController.makeDashedShape(
                rect: rect.insetBy(dx: -0.5, dy: -0.5),
                fillAlpha: nil,
                strokeAlpha: 0.25
            )
            collectionView.layer?.addSublayer(shape)
            itemHighlightLayers.append(shape)
        }
    }

    private func showDivisionPreview(row: NotebookRowInfo, hoveredItemIndex: Int, layout: NotebookGridLayout) {
        guard let hoveredAttrs = layout.layoutAttributesForItem(at: IndexPath(item: hoveredItemIndex, section: 0)) else { return }

        let insertBefore = dragController.lastDragPoint.x < hoveredAttrs.frame.midX
        let insertionCol = insertBefore
            ? hoveredItemIndex - row.startIndex
            : hoveredItemIndex - row.startIndex + 1

        let itemCount = row.endIndex - row.startIndex + 1
        var fractions = Array(repeating: 1.0 / Double(itemCount), count: itemCount)
        fractions.insert(1.0 / Double(itemCount + 1), at: insertionCol)

        let total = fractions.reduce(0, +)
        let normalized = fractions.map { $0 / total }

        var columns: [BlockDragController.DivisionColumn] = []
        for (col, fraction) in normalized.enumerated() {
            columns.append(.init(fraction: fraction, isInsertionTarget: col == insertionCol))
        }

        let insets = layout.sectionInsets
        let rowContentRect = contentRect(for: row, layout: layout)
        let containerRect = NSRect(
            x: insets.left,
            y: rowContentRect.minY,
            width: collectionView.bounds.width - insets.left - insets.right,
            height: rowContentRect.height
        )

        let shapes = BlockDragController.divisionPreviewShapes(columns: columns, containerRect: containerRect)
        for shape in shapes {
            collectionView.layer?.addSublayer(shape)
            divisionPreviewLayers.append(shape)
        }
    }
}

// MARK: - NSPopoverDelegate

extension NotebookBlocksController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        let closedPopover = notification.object as? NSPopover
        if closedPopover === blockMenuPopover {
            blockMenuItemRef?.isMenuForceHovered = false
            blockMenuItemRef?.forceActionBarVisible = false
            blockMenuItemRef = nil
            blockMenuPopover = nil
        } else if closedPopover === configPopover {
            configPopoverItemRef?.isConfigForceHovered = false
            configPopoverItemRef?.forceActionBarVisible = false
            configPopoverItemRef = nil
            configPopover = nil
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension NotebookBlocksController: NSCollectionViewDataSource {

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataController.blocks.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let block = dataController.blocks[indexPath.item]

        switch block.blockType {
        case .chart:
            let item = collectionView.makeItem(withIdentifier: NotebookChartItem.identifier, for: indexPath) as! NotebookChartItem
            let controller = blockController(for: block) as! ChartBlockController
            item.configure(block: block, controller: controller)
            wireItemCallbacks(on: item)
            wireMenuCallback(on: item, block: block)
            wireRunCallback(on: item) { await controller.viewModel.runChart() }
            return item

        case .text:
            let item = collectionView.makeItem(withIdentifier: NotebookTextItem.identifier, for: indexPath) as! NotebookTextItem
            let controller = blockController(for: block) as! TextBlockController
            item.configure(block: block, controller: controller)
            wireItemCallbacks(on: item)
            wireMenuCallback(on: item, block: block)
            return item

        case .singleValue:
            let item = collectionView.makeItem(withIdentifier: NotebookSingleValueItem.identifier, for: indexPath) as! NotebookSingleValueItem
            let controller = blockController(for: block) as! SingleValueBlockController
            item.configure(block: block, controller: controller)
            wireItemCallbacks(on: item)
            wireMenuCallback(on: item, block: block)
            wireRunCallback(on: item) { await controller.viewModel.fetchSingleValue() }
            item.onConfigTapped = { [weak self, weak item] sender in
                guard let self, let item else { return }
                let popoverVC = SingleValueConfigPopoverController(
                    viewModel: controller.viewModel,
                    connections: self.dataController.connections,
                    dataController: self.dataController
                )
                item.isConfigForceHovered = true
                item.forceActionBarVisible = true
                let pop = NSPopover()
                pop.contentViewController = popoverVC
                pop.behavior = .transient
                pop.delegate = self
                pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
                self.configPopover = pop
                self.configPopoverItemRef = item
            }
            return item

        case .query:
            let item = collectionView.makeItem(withIdentifier: NotebookQueryItem.identifier, for: indexPath) as! NotebookQueryItem
            let controller = blockController(for: block) as! QueryBlockController
            item.configure(block: block, controller: controller)
            wireItemCallbacks(on: item)
            wireMenuCallback(on: item, block: block)
            wireRunCallback(on: item) { await controller.viewModel.executeQuery() }
            return item
        }
    }
}
