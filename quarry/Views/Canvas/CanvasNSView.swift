import AppKit

protocol CanvasNSViewDelegate: AnyObject {
    func canvasDidChangeSelection(_ selectedNodeIds: Set<UUID>)
    func canvasDidDoubleClickNode(_ node: CanvasNode)
    func canvasDidFinishDraggingNode()
    func canvasDidChangeZoom()
}

final class CanvasNSView: NSView {
    weak var delegate: CanvasNSViewDelegate?

    var document: CanvasDocument = CanvasDocument() {
        didSet {
            invalidateNodeCaches()
            needsDisplay = true
        }
    }

    private var cachedSortedNodes: [CanvasNode]?
    private var cachedNodeLookup: [UUID: CanvasNode]?

    private var sortedNodes: [CanvasNode] {
        if let cached = cachedSortedNodes { return cached }
        let sorted = document.nodes.sorted { $0.zIndex < $1.zIndex }
        cachedSortedNodes = sorted
        return sorted
    }

    private var nodeLookup: [UUID: CanvasNode] {
        if let cached = cachedNodeLookup { return cached }
        let lookup = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        cachedNodeLookup = lookup
        return lookup
    }

    private func invalidateNodeCaches() {
        cachedSortedNodes = nil
        cachedNodeLookup = nil
    }

    var selectedNodeIds: Set<UUID> = [] {
        didSet {
            needsDisplay = true
            updateAnimationTimer()
        }
    }

    var selectedEdgeIds: Set<UUID> = [] {
        didSet { needsDisplay = true }
    }

    // Node dragging
    private var isDraggingNode = false
    private var draggedNodeId: UUID?
    private var dragStartPoint: CGPoint = .zero
    private var dragNodeStartPosition: CGPoint = .zero

    // Edge dragging
    private var isDraggingEdge = false
    private var draggedEdgeId: UUID?
    private var dragEdgeStartMidXOffset: CGFloat = 0

    // Panning
    private var isPanning = false
    private var panStartPoint: CGPoint = .zero
    private var panStartOffset: CGPoint = .zero

    // Rubber-band selection
    private var isRubberBanding = false
    private var rubberBandOrigin: CGPoint = .zero
    private var rubberBandCurrent: CGPoint = .zero

    // Hover
    private var hoveredNodeId: UUID?
    private var hoveredColumnIndex: Int?
    private var trackingArea: NSTrackingArea?

    private var dashPhase: CGFloat = 0
    private var animationTimer: Timer?
    private static let animationFrameInterval: TimeInterval = 1.0 / 15.0

    private let gridSpacing: CGFloat = 30
    private let gridDotRadius: CGFloat = 1.0
    private static let gridDotColorDark = NSColor(white: 0.18, alpha: 1)
    private static let gridDotColorLight = NSColor(white: 0.88, alpha: 1)

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        updateTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let canvasPoint = document.viewport.canvasPoint(from: location)

        var foundNode: UUID?
        var foundColumn: Int?

        for node in document.nodes.reversed() {
            guard node.contains(point: canvasPoint),
                  case .erdTable(let data) = node.kind else { continue }

            foundNode = node.id
            let headerTop = node.frame.maxY
            let columnsTop = headerTop - ERDNodeRenderer.headerHeight - 8
            if canvasPoint.y < columnsTop {
                let offsetFromTop = columnsTop - canvasPoint.y
                let colIndex = Int(offsetFromTop / ERDNodeRenderer.rowHeight)
                if colIndex >= 0 && colIndex < data.columns.count {
                    foundColumn = colIndex
                }
            }
            break
        }

        if foundNode != hoveredNodeId || foundColumn != hoveredColumnIndex {
            hoveredNodeId = foundNode
            hoveredColumnIndex = foundColumn
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredNodeId != nil || hoveredColumnIndex != nil {
            hoveredNodeId = nil
            hoveredColumnIndex = nil
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            // Leaving the window (e.g. tab closed) with a selection would
            // otherwise leave the repeating timer firing forever.
            animationTimer?.invalidate()
            animationTimer = nil
        } else {
            updateAnimationTimer()
        }
    }

    isolated deinit {
        animationTimer?.invalidate()
    }

    private func updateAnimationTimer() {
        if !selectedNodeIds.isEmpty {
            guard animationTimer == nil else { return }
            animationTimer = Timer.scheduledTimer(withTimeInterval: Self.animationFrameInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.dashPhase += 0.5
                    self.needsDisplay = true
                }
            }
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
            dashPhase = 0
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        context.clear(bounds)
        let bgColor = isDark ? NSColor.black.withAlphaComponent(0.30) : NSColor.white
        context.setFillColor(bgColor.cgColor)
        context.fill(bounds)

        context.saveGState()
        context.translateBy(x: document.viewport.offset.x, y: document.viewport.offset.y)
        context.scaleBy(x: document.viewport.zoomLevel, y: document.viewport.zoomLevel)

        drawGrid(in: context, isDark: isDark)

        let lookup = nodeLookup

        for edge in document.edges {
            let connectedToSelected = selectedNodeIds.contains(edge.sourceNodeId) || selectedNodeIds.contains(edge.targetNodeId)
            ERDEdgeRenderer.draw(
                edge: edge,
                nodeLookup: lookup,
                in: context,
                isSelected: selectedEdgeIds.contains(edge.id),
                isAnimated: connectedToSelected,
                dashPhase: dashPhase,
                isDark: isDark
            )
        }

        for node in sortedNodes {
            switch node.kind {
            case .erdTable(let tableData):
                let hoverCol = (hoveredNodeId == node.id) ? hoveredColumnIndex : nil
                ERDNodeRenderer.draw(
                    node: node,
                    tableData: tableData,
                    in: context,
                    isSelected: selectedNodeIds.contains(node.id),
                    hoveredColumnIndex: hoverCol,
                    isDark: isDark
                )
            }
        }

        context.restoreGState()

        if isRubberBanding {
            drawRubberBand(in: context, isDark: isDark)
        }
    }

    private func drawGrid(in context: CGContext, isDark: Bool) {
        let viewport = document.viewport
        let visibleRect = CGRect(
            origin: viewport.canvasPoint(from: .zero),
            size: CGSize(
                width: bounds.width / viewport.zoomLevel,
                height: bounds.height / viewport.zoomLevel
            )
        )

        let dotColor = isDark ? Self.gridDotColorDark : Self.gridDotColorLight
        context.setFillColor(dotColor.cgColor)

        let startX = floor(visibleRect.minX / gridSpacing) * gridSpacing
        let startY = floor(visibleRect.minY / gridSpacing) * gridSpacing
        let diameter = gridDotRadius * 2

        var rects: [CGRect] = []
        var x = startX
        while x <= visibleRect.maxX {
            var y = startY
            while y <= visibleRect.maxY {
                rects.append(CGRect(
                    x: x - gridDotRadius,
                    y: y - gridDotRadius,
                    width: diameter,
                    height: diameter
                ))
                y += gridSpacing
            }
            x += gridSpacing
        }
        context.fill(rects)
    }

    private func drawRubberBand(in context: CGContext, isDark: Bool) {
        let rect = rubberBandRect()
        let fillColor = NSColor.controlAccentColor.withAlphaComponent(0.1)
        let strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.5)

        context.setFillColor(fillColor.cgColor)
        context.fill(rect)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
    }

    private func rubberBandRect() -> CGRect {
        CGRect(
            x: min(rubberBandOrigin.x, rubberBandCurrent.x),
            y: min(rubberBandOrigin.y, rubberBandCurrent.y),
            width: abs(rubberBandCurrent.x - rubberBandOrigin.x),
            height: abs(rubberBandCurrent.y - rubberBandOrigin.y)
        )
    }

    // MARK: - Hit Testing

    private func hitTestNode(at screenPoint: CGPoint) -> CanvasNode? {
        let canvasPoint = document.viewport.canvasPoint(from: screenPoint)
        return sortedNodes.reversed().first { $0.contains(point: canvasPoint) }
    }

    private func hitTestEdge(at screenPoint: CGPoint) -> CanvasEdge? {
        let canvasPoint = document.viewport.canvasPoint(from: screenPoint)
        let lookup = nodeLookup
        return document.edges.first { edge in
            ERDEdgeRenderer.hitTest(point: canvasPoint, edge: edge, nodeLookup: lookup)
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)

        // 1. Check node hit first
        if let node = hitTestNode(at: location) {
            selectedEdgeIds.removeAll()

            if event.clickCount == 2 {
                delegate?.canvasDidDoubleClickNode(node)
                return
            }

            if event.modifierFlags.contains(.command) {
                if selectedNodeIds.contains(node.id) {
                    selectedNodeIds.remove(node.id)
                } else {
                    selectedNodeIds.insert(node.id)
                }
            } else if !selectedNodeIds.contains(node.id) {
                selectedNodeIds = [node.id]
            }

            document.bringToFront(node.id)
            invalidateNodeCaches()
            delegate?.canvasDidChangeSelection(selectedNodeIds)

            isDraggingNode = true
            draggedNodeId = node.id
            dragStartPoint = location
            dragNodeStartPosition = node.position
            return
        }

        // 2. Check edge hit
        if let edge = hitTestEdge(at: location) {
            selectedNodeIds.removeAll()
            delegate?.canvasDidChangeSelection(selectedNodeIds)

            if event.modifierFlags.contains(.command) {
                if selectedEdgeIds.contains(edge.id) {
                    selectedEdgeIds.remove(edge.id)
                } else {
                    selectedEdgeIds.insert(edge.id)
                }
            } else {
                selectedEdgeIds = [edge.id]
            }

            isDraggingEdge = true
            draggedEdgeId = edge.id
            dragStartPoint = location
            dragEdgeStartMidXOffset = edge.midXOffset
            return
        }

        // 3. Empty canvas click
        if !event.modifierFlags.contains(.command) {
            selectedNodeIds.removeAll()
            selectedEdgeIds.removeAll()
            delegate?.canvasDidChangeSelection(selectedNodeIds)
        }

        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift) {
            isPanning = true
            panStartPoint = location
            panStartOffset = document.viewport.offset
        } else {
            isRubberBanding = true
            rubberBandOrigin = location
            rubberBandCurrent = location
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        if isDraggingNode, let nodeId = draggedNodeId {
            let delta = CGPoint(
                x: (location.x - dragStartPoint.x) / document.viewport.zoomLevel,
                y: (location.y - dragStartPoint.y) / document.viewport.zoomLevel
            )

            if selectedNodeIds.contains(nodeId) {
                document.updateNodePosition(nodeId, to: CGPoint(
                    x: dragNodeStartPosition.x + delta.x,
                    y: dragNodeStartPosition.y + delta.y
                ))
                invalidateNodeCaches()
            }

            needsDisplay = true
        } else if isDraggingEdge, let edgeId = draggedEdgeId {
            let deltaX = (location.x - dragStartPoint.x) / document.viewport.zoomLevel
            document.updateEdgeMidXOffset(edgeId, offset: dragEdgeStartMidXOffset + deltaX)
            needsDisplay = true
        } else if isPanning {
            let delta = CGPoint(
                x: location.x - panStartPoint.x,
                y: location.y - panStartPoint.y
            )
            document.viewport.offset = CGPoint(
                x: panStartOffset.x + delta.x,
                y: panStartOffset.y + delta.y
            )
            needsDisplay = true
        } else if isRubberBanding {
            rubberBandCurrent = location
            updateRubberBandSelection()
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let didDragNode = isDraggingNode

        isDraggingNode = false
        draggedNodeId = nil
        isDraggingEdge = false
        draggedEdgeId = nil
        isPanning = false

        if isRubberBanding {
            updateRubberBandSelection()
            isRubberBanding = false
            needsDisplay = true
        }

        if didDragNode {
            delegate?.canvasDidFinishDraggingNode()
        }
    }

    private func updateRubberBandSelection() {
        let screenRect = rubberBandRect()
        let topLeft = document.viewport.canvasPoint(from: CGPoint(x: screenRect.minX, y: screenRect.minY))
        let bottomRight = document.viewport.canvasPoint(from: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
        let canvasRect = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )

        selectedNodeIds = Set(
            document.nodes
                .filter { canvasRect.intersects($0.frame) }
                .map(\.id)
        )
        delegate?.canvasDidChangeSelection(selectedNodeIds)
    }

    // MARK: - Scroll / Zoom

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
            let location = convert(event.locationInWindow, from: nil)
            let delta = event.scrollingDeltaY * 0.008
            document.viewport.zoom(by: delta, centeredAt: location)
            delegate?.canvasDidChangeZoom()
        } else {
            document.viewport.pan(by: CGPoint(
                x: event.scrollingDeltaX,
                y: -event.scrollingDeltaY
            ))
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        document.viewport.zoom(by: event.magnification * 0.5, centeredAt: location)
        delegate?.canvasDidChangeZoom()
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            deleteSelected()
        default:
            super.keyDown(with: event)
        }
    }

    private func deleteSelected() {
        if !selectedNodeIds.isEmpty {
            for nodeId in selectedNodeIds {
                document.removeNode(nodeId)
            }
            invalidateNodeCaches()
            selectedNodeIds.removeAll()
            delegate?.canvasDidChangeSelection(selectedNodeIds)
        }
        selectedEdgeIds.removeAll()
        needsDisplay = true
    }

    // MARK: - Public API

    func zoomToFit() {
        document.viewport.zoomToFit(nodes: document.nodes, in: bounds.size)
        needsDisplay = true
    }

    func zoomIn() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        document.viewport.zoom(by: CanvasViewport.zoomStep * 2, centeredAt: center)
        needsDisplay = true
    }

    func zoomOut() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        document.viewport.zoom(by: -CanvasViewport.zoomStep * 2, centeredAt: center)
        needsDisplay = true
    }

    func resetZoom() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let delta = 1.0 - document.viewport.zoomLevel
        document.viewport.zoom(by: delta, centeredAt: center)
        needsDisplay = true
    }
}
