import AppKit

private final class DashboardFlippedView: NSView {
    override var isFlipped: Bool { true }
}


final class DashboardGridController: NSViewController {

    private let dataController: NotebookDataController
    private let headerView: NSView?
    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!
    private var collectionHeightConstraint: NSLayoutConstraint?
    nonisolated(unsafe) private var scrollBoundsObserver: NSObjectProtocol?

    private let dragController = BlockDragController()
    private var currentDropIntent: DashboardDropIntent?
    private var dropIndicatorLayer: CAShapeLayer?
    private var dimOverlayLayer: CALayer?
    private var itemHighlightLayers: [CAShapeLayer] = []
    private var divisionPreviewLayers: [CAShapeLayer] = []
    private var isLayoutFrozen = false
    private var lastKnownWidth: CGFloat = 0

    var onScrollOffsetChanged: ((CGFloat) -> Void)?

    init(dataController: NotebookDataController, headerView: NSView? = nil) {
        self.dataController = dataController
        self.headerView = headerView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        setupCollectionView()
        observeState()

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

    deinit {
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
        NotificationCenter.default.removeObserver(self)
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
        scrollView.scrollerInsets.top = inset
    }

    var currentScrollOffset: CGFloat {
        max(0, scrollView.contentView.bounds.origin.y)
    }

    /// Flushes a reload deferred while the pane was off screen, so the grid is
    /// already correct by the time it fades in.
    func prepareForDisplay() {
        guard needsReloadOnVisible, view.window != nil, collectionView.bounds.width > 0 else { return }
        needsReloadOnVisible = false
        collectionView.reloadData()
        updateCollectionHeight()
    }

    private func setupCollectionView() {
        let layout = DashboardGridLayout()
        layout.dataController = dataController

        collectionView = NonRecyclingCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(DashboardChartItem.self, forItemWithIdentifier: DashboardChartItem.identifier)
        collectionView.register(DashboardTextItem.self, forItemWithIdentifier: DashboardTextItem.identifier)
        collectionView.register(DashboardSingleValueItem.self, forItemWithIdentifier: DashboardSingleValueItem.identifier)
        collectionView.register(DashboardQueryItem.self, forItemWithIdentifier: DashboardQueryItem.identifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = DashboardFlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

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

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: collectionTopAnchor),
            collectionView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            heightConstraint,

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
            }
        }
    }

    private func updateCollectionHeight() {
        guard let layout = collectionView.collectionViewLayout else { return }
        collectionView.layoutSubtreeIfNeeded()
        collectionHeightConstraint?.constant = layout.collectionViewContentSize.height
    }

    // MARK: - Resize

    private var availableContentWidth: CGFloat {
        let insets = (collectionView.collectionViewLayout as? DashboardGridLayout)?.sectionInsets ?? NSEdgeInsets()
        return collectionView.bounds.width - insets.left - insets.right
    }

    private func invalidateLayoutAndHeight() {
        collectionView.collectionViewLayout?.invalidateLayout()
        updateCollectionHeight()
    }

    private func handleBlockResize(block: NotebookBlock, newHeight: CGFloat) {
        block.blockHeight = newHeight
        invalidateLayoutAndHeight()
    }

    private func handleBlockWidthResize(block: NotebookBlock, delta: CGFloat) {
        let availableWidth = availableContentWidth
        guard availableWidth > 0 else { return }

        let dashBlocks = dataController.cachedDashboardBlocks
        guard let blockIndex = dashBlocks.firstIndex(where: { $0.id == block.id }) else { return }

        let rowBlocks = blocksInSameRow(as: blockIndex, in: dashBlocks)
        let others = rowBlocks.filter { $0.id != block.id }
        let fractionDelta = delta / availableWidth
        let minFraction = max(200 / availableWidth, 0.2)

        block.blockWidthFraction = min(max(block.blockWidthFraction + fractionDelta, minFraction), 1.0)

        if !others.isEmpty {
            let total = rowBlocks.reduce(0.0) { $0 + $1.blockWidthFraction }
            if total > 1.0 {
                let excess = total - 1.0
                let otherTotal = others.reduce(0.0) { $0 + $1.blockWidthFraction }
                let shrinkable = otherTotal - Double(others.count) * minFraction

                if shrinkable > 0 {
                    let shrinkAmount = min(excess, shrinkable)
                    for other in others {
                        let proportion = (other.blockWidthFraction - minFraction) / shrinkable
                        other.blockWidthFraction = max(minFraction, other.blockWidthFraction - shrinkAmount * proportion)
                    }
                }

                let remainingOther = others.reduce(0.0) { $0 + $1.blockWidthFraction }
                block.blockWidthFraction = min(block.blockWidthFraction, 1.0 - remainingOther)
            }
        }

        invalidateLayoutAndHeight()
    }

    private func blocksInSameRow(as blockIndex: Int, in dashBlocks: [NotebookBlock]) -> [NotebookBlock] {
        var start = blockIndex
        while start > 0, dashBlocks[start].dashboardInline {
            start -= 1
        }
        var end = blockIndex
        while end + 1 < dashBlocks.count, dashBlocks[end + 1].dashboardInline {
            end += 1
        }
        return Array(dashBlocks[start...end])
    }

    // MARK: - Observation

    private var needsReloadOnVisible = false

    override func viewDidLayout() {
        super.viewDidLayout()

        if needsReloadOnVisible, view.window != nil, collectionView.bounds.width > 0 {
            needsReloadOnVisible = false
            collectionView.reloadData()
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

    private func observeState() {
        // Deliberately not tracking `viewMode`: switching panes doesn't change
        // what the grid renders, and reloading there flashes every card.
        withObservationTracking {
            _ = self.dataController.cachedDashboardBlocks
            _ = self.dataController.isDashboardPublished
            _ = self.dataController.isPublishPreviewing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.dragController.isDragging else {
                    self.observeState()
                    return
                }
                if self.view.window != nil, self.collectionView.bounds.width > 0 {
                    self.collectionView.reloadData()
                    self.updateCollectionHeight()
                } else {
                    self.needsReloadOnVisible = true
                }
                self.observeState()
            }
        }
    }

    // MARK: - Custom Drag

    private enum DashboardDropIntent: Equatable {
        case insertRow(beforeIndex: Int)
        case insertInRow(rowIndex: Int, hoveredItemIndex: Int)
    }

    private func wireItemCallbacks(on item: DashboardBaseItem, block: NotebookBlock) {
        item.onResize = { [weak self] block, newHeight in
            self?.handleBlockResize(block: block, newHeight: newHeight)
        }
        item.onWidthResize = { [weak self] block, delta in
            self?.handleBlockWidthResize(block: block, delta: delta)
        }
        item.onDragBegan = { [weak self, weak item] event in
            guard let self, let item, let index = self.currentItemIndex(for: item) else { return }
            self.beginDrag(itemIndex: index, event: event)
        }
        item.onDragMoved = { [weak self] event in self?.updateDrag(event: event) }
        item.onDragEnded = { [weak self] event in self?.endDrag(event: event) }
        item.onDragCancelled = { [weak self] in self?.cleanupDrag() }
        item.onToggleDashboardVisibility = { [weak self] in
            self?.dataController.toggleBlockDashboardVisibility(block)
        }
    }

    private func currentItemIndex(for item: DashboardBaseItem) -> Int? {
        guard let blockID = item.currentBlock?.id else { return nil }
        return dataController.cachedDashboardBlocks.firstIndex { $0.id == blockID }
    }

    private func beginDrag(itemIndex: Int, event: NSEvent) {
        guard !dataController.isDashboardPublished, !dataController.isPublishPreviewing else { return }

        let block = dataController.cachedDashboardBlocks[itemIndex]
        let previewFrame: NSRect?
        if block.blockType == .singleValue,
           let layout = collectionView.collectionViewLayout as? DashboardGridLayout {
            previewFrame = contentRect(forItemAt: itemIndex, layout: layout)
        } else {
            previewFrame = nil
        }
        dragController.beginDrag(
            sourceIndex: itemIndex,
            block: block,
            event: event,
            snapshotContainer: collectionView,
            dimContainer: collectionView,
            previewFrame: previewFrame
        )

        if let item = collectionView.item(at: itemIndex) {
            item.view.alphaValue = 0.15
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
    }

    // MARK: - Layer Helpers

    private static let titleOffset: CGFloat = 30
    private static let resizeOffset: CGFloat = 12
    private static let handleWidth: CGFloat = 12

    private func contentRect(from frame: NSRect) -> NSRect {
        NSRect(
            x: frame.minX,
            y: frame.minY + Self.titleOffset,
            width: frame.width - Self.handleWidth,
            height: frame.height - Self.titleOffset - Self.resizeOffset
        )
    }

    private func contentRect(forItemAt itemIndex: Int, layout: DashboardGridLayout) -> NSRect? {
        if let item = collectionView.item(at: itemIndex) as? DashboardBaseItem {
            return item.blockContainer.convert(item.blockContainer.bounds, to: collectionView)
        }

        guard let attrs = layout.layoutAttributesForItem(at: IndexPath(item: itemIndex, section: 0)) else {
            return nil
        }

        return contentRect(from: attrs.frame)
    }

    private func contentRect(for row: DashboardRowInfo, layout: DashboardGridLayout) -> NSRect {
        var rowRect: NSRect?

        for itemIndex in row.startIndex...row.endIndex {
            guard let itemRect = contentRect(forItemAt: itemIndex, layout: layout) else { continue }
            rowRect = rowRect?.union(itemRect) ?? itemRect
        }

        if let rowRect {
            return rowRect
        }

        return contentRect(from: row.frame)
    }

    private func applyDashedStyle(
        to shape: CAShapeLayer,
        rect: NSRect,
        fillAlpha: CGFloat?,
        strokeAlpha: CGFloat,
        color: NSColor = .controlAccentColor
    ) {
        BlockDragController.applyDashedStyle(to: shape, rect: rect, fillAlpha: fillAlpha, strokeAlpha: strokeAlpha, color: color)
    }

    private func makeDashedShape(
        rect: NSRect,
        fillAlpha: CGFloat?,
        strokeAlpha: CGFloat,
        color: NSColor = .controlAccentColor
    ) -> CAShapeLayer {
        BlockDragController.makeDashedShape(rect: rect, fillAlpha: fillAlpha, strokeAlpha: strokeAlpha, color: color)
    }

    private func addItemHighlights(onlyRange: ClosedRange<Int>? = nil) {
        guard let layout = collectionView.collectionViewLayout as? DashboardGridLayout else { return }

        for i in 0..<dataController.cachedDashboardBlocks.count {
            guard i != dragController.dragSourceIndex else { continue }
            if let only = onlyRange, !only.contains(i) { continue }
            guard let rect = contentRect(forItemAt: i, layout: layout) else { continue }

            let shape = makeDashedShape(rect: rect.insetBy(dx: -0.5, dy: -0.5), fillAlpha: nil, strokeAlpha: 0.25)
            collectionView.layer?.addSublayer(shape)
            itemHighlightLayers.append(shape)
        }
    }

    private func updateDrag(event: NSEvent) {
        guard dragController.isDragging else { return }

        dragController.updateSnapshotPosition(event: event, containerView: collectionView)

        dragController.updateAutoScroll(scrollView: scrollView, sourceView: collectionView) {
            // no-op: auto-scroll tick doesn't need to recompute drop for dashboard
        }

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

        let dashBlocks = dataController.cachedDashboardBlocks
        guard sourceIndex < dashBlocks.count else {
            cleanupDrag()
            return
        }

        let oldIds = dashBlocks.map(\.id)

        let sourceBlock = dashBlocks[sourceIndex]

        guard let intent = currentDropIntent else {
            cleanupDrag()
            return
        }

        let layout = collectionView.collectionViewLayout as? DashboardGridLayout
        let rows = layout?.cachedRows ?? []

        let sourceRowIndex = rowIndex(containing: sourceIndex, in: rows)

        switch intent {
        case .insertRow(let beforeIndex):
            promoteNextInlineBlock(after: sourceIndex, in: dashBlocks)
            sourceBlock.dashboardInline = false
            let destDashIndex = beforeIndex < rows.count ? rows[beforeIndex].startIndex : dashBlocks.count
            dataController.moveDashboardBlock(from: sourceIndex, to: destDashIndex)

        case .insertInRow(let rowIndex, let hoveredItemIndex):
            guard rowIndex < rows.count else { break }
            let row = rows[rowIndex]
            let isSameRow = sourceRowIndex == rowIndex

            if !isSameRow {
                promoteNextInlineBlock(after: sourceIndex, in: dashBlocks)
                let usedFraction = (row.startIndex...row.endIndex).reduce(0.0) { $0 + dashBlocks[$1].blockWidthFraction }
                sourceBlock.blockWidthFraction = max(0.2, 1.0 - usedFraction)
            }

            let targetDashIndex: Int
            if isSameRow {
                targetDashIndex = hoveredItemIndex
            } else {
                let locationInCollection = collectionView.convert(event.locationInWindow, from: nil)
                let hoveredAttrs = (collectionView.collectionViewLayout as? DashboardGridLayout)?
                    .layoutAttributesForItem(at: IndexPath(item: hoveredItemIndex, section: 0))
                let insertBefore = locationInCollection.x < (hoveredAttrs?.frame.midX ?? 0)
                targetDashIndex = insertBefore ? hoveredItemIndex : min(hoveredItemIndex + 1, row.endIndex + 1)
            }

            if isSameRow {
                var destIndex = targetDashIndex
                if destIndex > sourceIndex { destIndex += 1 }
                dataController.moveDashboardBlock(from: sourceIndex, to: destIndex)

                let updatedDashBlocks = dataController.cachedDashboardBlocks
                for i in row.startIndex...row.endIndex {
                    guard i < updatedDashBlocks.count else { break }
                    updatedDashBlocks[i].dashboardInline = (i != row.startIndex)
                }
            } else {
                if targetDashIndex == row.startIndex {
                    sourceBlock.dashboardInline = false
                    dashBlocks[row.startIndex].dashboardInline = true
                } else {
                    sourceBlock.dashboardInline = true
                }

                dataController.moveDashboardBlock(from: sourceIndex, to: targetDashIndex)
            }
        }

        let newIds = dataController.cachedDashboardBlocks.map(\.id)

        collectionView.performBatchUpdates {
            for (oldIndex, id) in oldIds.enumerated() {
                guard let newIndex = newIds.firstIndex(of: id), oldIndex != newIndex else { continue }
                self.collectionView.moveItem(
                    at: IndexPath(item: oldIndex, section: 0),
                    to: IndexPath(item: newIndex, section: 0)
                )
            }
        } completionHandler: { [weak self] _ in
            self?.updateCollectionHeight()
        }

        cleanupDrag()
    }

    private func promoteNextInlineBlock(after sourceIndex: Int, in dashBlocks: [NotebookBlock]) {
        let sourceBlock = dashBlocks[sourceIndex]
        guard !sourceBlock.dashboardInline, sourceIndex + 1 < dashBlocks.count else { return }
        let nextBlock = dashBlocks[sourceIndex + 1]
        if nextBlock.dashboardInline {
            nextBlock.dashboardInline = false
        }
    }

    private func cleanupDrag() {
        if let gridLayout = collectionView.collectionViewLayout as? DashboardGridLayout,
           gridLayout.insertRowGapBeforeIndex != nil {
            gridLayout.insertRowGapBeforeIndex = nil
            collectionView.collectionViewLayout?.invalidateLayout()
            collectionView.layoutSubtreeIfNeeded()
            updateCollectionHeight()
        }

        if let sourceIndex = dragController.dragSourceIndex,
           let item = collectionView.item(at: sourceIndex) {
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
    }

    // MARK: - Drop Intent

    private func rowIndex(containing itemIndex: Int, in rows: [DashboardRowInfo]) -> Int? {
        rows.firstIndex { itemIndex >= $0.startIndex && itemIndex <= $0.endIndex }
    }

    private func computeDropIntent(at point: NSPoint, sourceIndex: Int) -> DashboardDropIntent? {
        guard let layout = collectionView.collectionViewLayout as? DashboardGridLayout else { return nil }
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
                let hoveredItem = findHoveredItemIndex(in: row, at: point.x, layout: layout)
                return validatedIntent(.insertInRow(rowIndex: rowIndex, hoveredItemIndex: hoveredItem), sourceIndex: sourceIndex, rows: rows)
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

    private func validatedIntent(_ intent: DashboardDropIntent, sourceIndex: Int, rows: [DashboardRowInfo]) -> DashboardDropIntent? {
        isNoOp(intent, sourceIndex: sourceIndex, rows: rows) ? nil : intent
    }

    private func findHoveredItemIndex(in row: DashboardRowInfo, at x: CGFloat, layout: DashboardGridLayout) -> Int {
        var closest = row.endIndex
        var closestDist = CGFloat.greatestFiniteMagnitude
        for i in row.startIndex...row.endIndex {
            guard i != dragController.dragSourceIndex else { continue }
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

    private func isNoOp(_ intent: DashboardDropIntent, sourceIndex: Int, rows: [DashboardRowInfo]) -> Bool {
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

    private func removeLayers(_ layers: inout [CAShapeLayer]) {
        BlockDragController.removeLayers(&layers)
    }

    private func updateDropIndicator(for intent: DashboardDropIntent?) {
        removeLayers(&divisionPreviewLayers)
        removeLayers(&itemHighlightLayers)
        guard let indicator = dropIndicatorLayer else { return }
        guard let layout = collectionView.collectionViewLayout as? DashboardGridLayout else { return }

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
        let insets = layout.sectionInsets

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
                applyDashedStyle(to: indicator, rect: rect, fillAlpha: 0.04, strokeAlpha: 0.3)
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
                addItemHighlights(onlyRange: row.startIndex...row.endIndex)

                guard let hoveredRect = contentRect(forItemAt: hoveredItemIndex, layout: layout) else {
                    indicator.isHidden = true
                    break
                }

                applyDashedStyle(
                    to: indicator,
                    rect: hoveredRect.insetBy(dx: -0.5, dy: -0.5),
                    fillAlpha: 0.06,
                    strokeAlpha: 0.35
                )
                indicator.isHidden = false
            } else {
                indicator.isHidden = true
                showDivisionPreview(row: row, hoveredItemIndex: hoveredItemIndex, insets: insets)
            }
        }

        CATransaction.commit()
    }

    private func showDivisionPreview(row: DashboardRowInfo, hoveredItemIndex: Int, insets: NSEdgeInsets) {
        guard let layout = collectionView.collectionViewLayout as? DashboardGridLayout,
              let hoveredAttrs = layout.layoutAttributesForItem(at: IndexPath(item: hoveredItemIndex, section: 0)) else {
            return
        }

        let insertBefore = dragController.lastDragPoint.x < hoveredAttrs.frame.midX
        let insertionCol = insertBefore
            ? hoveredItemIndex - row.startIndex
            : hoveredItemIndex - row.startIndex + 1

        let dashBlocks = dataController.cachedDashboardBlocks
        var existingFractions = (row.startIndex...row.endIndex).map { dashBlocks[$0].blockWidthFraction }
        let usedFraction = existingFractions.reduce(0, +)
        let newFraction = max(0.2, 1.0 - usedFraction)
        existingFractions.insert(newFraction, at: insertionCol)

        var columns: [BlockDragController.DivisionColumn] = []
        for (col, fraction) in existingFractions.enumerated() {
            columns.append(.init(fraction: fraction, isInsertionTarget: col == insertionCol))
        }

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

// MARK: - NSCollectionViewDataSource

extension DashboardGridController: NSCollectionViewDataSource {

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        dataController.cachedDashboardBlocks.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let block = dataController.cachedDashboardBlocks[indexPath.item]
        let published = dataController.isDashboardPublished || dataController.isPublishPreviewing

        switch block.blockType {
        case .chart:
            let item = collectionView.makeItem(withIdentifier: DashboardChartItem.identifier, for: indexPath) as! DashboardChartItem
            let vm = dataController.chartViewModel(for: block)
            vm.loadDataIfNeeded()
            item.configure(block: block, viewModel: vm, isPublished: published)
            wireItemCallbacks(on: item, block: block)
            item.onRun = { Task { await vm.runChart() } }
            return item
        case .text:
            let item = collectionView.makeItem(withIdentifier: DashboardTextItem.identifier, for: indexPath) as! DashboardTextItem
            item.configure(block: block, isPublished: published)
            wireItemCallbacks(on: item, block: block)
            return item
        case .singleValue:
            let item = collectionView.makeItem(withIdentifier: DashboardSingleValueItem.identifier, for: indexPath) as! DashboardSingleValueItem
            let vm = dataController.singleValueViewModel(for: block)
            vm.loadDataIfNeeded()
            item.configure(block: block, viewModel: vm, isPublished: published)
            wireItemCallbacks(on: item, block: block)
            item.onRun = { Task { await vm.fetchSingleValue() } }
            return item
        case .query:
            let item = collectionView.makeItem(withIdentifier: DashboardQueryItem.identifier, for: indexPath) as! DashboardQueryItem
            let vm = dataController.queryViewModel(for: block)
            vm.loadDataIfNeeded()
            item.configure(block: block, viewModel: vm, isPublished: published)
            wireItemCallbacks(on: item, block: block)
            item.onRun = { Task { await vm.executeQuery() } }
            return item
        }
    }
}
