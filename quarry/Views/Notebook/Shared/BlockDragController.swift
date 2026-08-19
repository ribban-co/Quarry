import AppKit

final class BlockDragController {

    private(set) var isDragging = false
    private(set) var dragSourceIndex: Int?
    private(set) var lastDragPoint: NSPoint = .zero

    private var dragSnapshotLayer: CALayer?
    private var dragOffset: NSPoint = .zero
    private var dimOverlayLayer: CALayer?
    private var autoScrollTimer: Timer?
    private weak var autoScrollScrollView: NSScrollView?
    private var autoScrollDelta: CGFloat = 0
    private var autoScrollOnTick: (@MainActor () -> Void)?

    deinit {
        autoScrollTimer?.invalidate()
    }

    // MARK: - Snapshot

    @MainActor
    func beginDrag(
        sourceIndex: Int,
        block: NotebookBlock,
        event: NSEvent,
        snapshotContainer: NSView,
        dimContainer: NSView,
        previewFrame: NSRect? = nil
    ) {
        isDragging = true
        dragSourceIndex = sourceIndex

        let iconName = NotebookDragVisuals.dragIconName(for: block.blockType, filled: true)
        let title = block.title.isEmpty ? block.blockType.displayName : block.title
        let card = NotebookDragVisuals.dragCard(title: title, iconName: iconName, size: previewFrame?.size)

        let location = snapshotContainer.convert(event.locationInWindow, from: nil)
        if let previewFrame {
            card.frame.origin = previewFrame.origin
            dragOffset = NSPoint(
                x: location.x - previewFrame.minX,
                y: location.y - previewFrame.minY
            )
        } else {
            card.frame.origin = NSPoint(
                x: location.x + 4,
                y: location.y - card.frame.height / 2
            )
            dragOffset = NSPoint(x: -4, y: card.frame.height / 2)
        }

        snapshotContainer.layer?.addSublayer(card)
        dragSnapshotLayer = card

        let overlay = CALayer()
        overlay.frame = dimContainer.bounds
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0).cgColor
        dimContainer.layer?.addSublayer(overlay)
        dimOverlayLayer = overlay
    }

    @MainActor
    func updateSnapshotPosition(event: NSEvent, containerView: NSView) {
        guard let snapshot = dragSnapshotLayer else { return }
        let location = containerView.convert(event.locationInWindow, from: nil)
        lastDragPoint = location

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        snapshot.frame.origin = NSPoint(
            x: location.x - dragOffset.x,
            y: location.y - dragOffset.y
        )
        CATransaction.commit()
    }

    // MARK: - Auto-scroll

    @MainActor
    func updateAutoScroll(
        scrollView: NSScrollView,
        sourceView: NSView? = nil,
        onTick: @escaping @MainActor () -> Void
    ) {
        let locationInScroll = scrollView.convert(lastDragPoint, from: sourceView ?? scrollView.superview)
        let visibleHeight = scrollView.bounds.height
        let scrollDelta = NotebookDragVisuals.autoScrollDelta(
            for: locationInScroll,
            visibleHeight: visibleHeight
        )

        if abs(scrollDelta) > 0.5 {
            autoScrollScrollView = scrollView
            autoScrollDelta = scrollDelta
            autoScrollOnTick = onTick
            if autoScrollTimer == nil {
                autoScrollTimer = Timer.scheduledTimer(
                    timeInterval: 1.0 / 60.0,
                    target: self,
                    selector: #selector(handleAutoScrollTick),
                    userInfo: nil,
                    repeats: true
                )
            }
        } else {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
            autoScrollScrollView = nil
            autoScrollOnTick = nil
            autoScrollDelta = 0
        }
    }

    // MARK: - Cleanup

    @MainActor
    func cleanup() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollScrollView = nil
        autoScrollOnTick = nil
        autoScrollDelta = 0

        dragSnapshotLayer?.removeFromSuperlayer()
        dragSnapshotLayer = nil

        dimOverlayLayer?.removeFromSuperlayer()
        dimOverlayLayer = nil

        isDragging = false
        dragSourceIndex = nil
        lastDragPoint = .zero
    }

    @MainActor
    @objc private func handleAutoScrollTick() {
        guard let scrollView = autoScrollScrollView else {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
            autoScrollOnTick = nil
            autoScrollDelta = 0
            return
        }

        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clipView.bounds.height)
        origin.y = min(max(origin.y + autoScrollDelta, 0), maxY)
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
        autoScrollOnTick?()
    }

    // MARK: - Indicator Helpers

    static func makeDashedShape(
        rect: NSRect,
        fillAlpha: CGFloat?,
        strokeAlpha: CGFloat,
        color: NSColor = .controlAccentColor
    ) -> CAShapeLayer {
        let shape = CAShapeLayer()
        applyDashedStyle(to: shape, rect: rect, fillAlpha: fillAlpha, strokeAlpha: strokeAlpha, color: color)
        return shape
    }

    static func applyDashedStyle(
        to shape: CAShapeLayer,
        rect: NSRect,
        fillAlpha: CGFloat?,
        strokeAlpha: CGFloat,
        color: NSColor = .controlAccentColor
    ) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        shape.path = path.cgPath
        shape.fillColor = fillAlpha.map { color.withAlphaComponent($0).cgColor }
        shape.strokeColor = color.withAlphaComponent(strokeAlpha).cgColor
        shape.lineWidth = 1.5
        shape.lineDashPattern = [4, 3]
    }

    static func removeLayers(_ layers: inout [CAShapeLayer]) {
        for layer in layers { layer.removeFromSuperlayer() }
        layers.removeAll()
    }

    // MARK: - Division Preview

    struct DivisionColumn {
        let fraction: Double
        let isInsertionTarget: Bool
    }

    static func divisionPreviewShapes(
        columns: [DivisionColumn],
        containerRect: NSRect,
        insetDx: CGFloat = 4,
        insetDy: CGFloat = 0.75
    ) -> [CAShapeLayer] {
        guard !columns.isEmpty else { return [] }

        let totalFraction = columns.reduce(0.0) { $0 + $1.fraction }
        let normalized: [DivisionColumn] = totalFraction > 1.0
            ? columns.map { DivisionColumn(fraction: $0.fraction / totalFraction, isInsertionTarget: $0.isInsertionTarget) }
            : columns

        let colCount = normalized.count
        let handleWidth: CGFloat = 12
        let totalHandleWidth = handleWidth * CGFloat(colCount)
        let distributableWidth = containerRect.width - totalHandleWidth

        var shapes: [CAShapeLayer] = []
        var xOffset = containerRect.minX

        for column in normalized {
            let colWidth = distributableWidth * column.fraction + handleWidth
            let rect = NSRect(
                x: xOffset,
                y: containerRect.minY,
                width: colWidth,
                height: containerRect.height
            ).insetBy(dx: insetDx, dy: insetDy)

            let shape = makeDashedShape(
                rect: rect,
                fillAlpha: column.isInsertionTarget ? 0.04 : nil,
                strokeAlpha: column.isInsertionTarget ? 0.3 : 0.15
            )
            shapes.append(shape)

            xOffset += colWidth
        }

        return shapes
    }
}
