import AppKit

struct ERDEdgeRenderer {
    static let bendRadius: CGFloat = 8
    static let hitTestThreshold: CGFloat = 6
    static let portRadius: CGFloat = 4.5

    private static let accent = ERDNodeRenderer.accent

    private static let lineColorDark = NSColor(white: 0.32, alpha: 1)
    private static let lineColorLight = NSColor(white: 0.76, alpha: 1)
    private static let portBgColorDark = NSColor.windowBackgroundColor.blended(withFraction: 0.30, of: .black) ?? NSColor.windowBackgroundColor

    struct ResolvedEdge {
        let edgeId: UUID
        let startPoint: CGPoint
        let endPoint: CGPoint
        let midX: CGFloat
    }

    static func resolveEdge(_ edge: CanvasEdge, nodeLookup: [UUID: CanvasNode]) -> ResolvedEdge? {
        guard let sourceNode = nodeLookup[edge.sourceNodeId],
              let targetNode = nodeLookup[edge.targetNodeId],
              case .erdTable(let sourceData) = sourceNode.kind,
              case .erdTable(let targetData) = targetNode.kind else {
            return nil
        }

        let padding: CGFloat = 30
        let sourceFrame = sourceNode.frame
        let targetFrame = targetNode.frame

        let gapSourceToTarget = targetFrame.minX - sourceFrame.maxX
        let gapTargetToSource = sourceFrame.minX - targetFrame.maxX

        let sourceSide: ERDNodeRenderer.PortSide
        let targetSide: ERDNodeRenderer.PortSide

        if gapSourceToTarget >= padding {
            sourceSide = .right
            targetSide = .left
        } else if gapTargetToSource >= padding {
            sourceSide = .left
            targetSide = .right
        } else {
            sourceSide = .right
            targetSide = .right
        }

        guard let startPoint = ERDNodeRenderer.portPosition(for: edge.sourcePort, in: sourceNode, tableData: sourceData, side: sourceSide),
              let endPoint = ERDNodeRenderer.portPosition(for: edge.targetPort, in: targetNode, tableData: targetData, side: targetSide) else {
            return nil
        }

        let midX: CGFloat
        if sourceSide == targetSide {
            if sourceSide == .right {
                midX = max(sourceFrame.maxX, targetFrame.maxX) + padding + edge.midXOffset
            } else {
                midX = min(sourceFrame.minX, targetFrame.minX) - padding + edge.midXOffset
            }
        } else {
            midX = (startPoint.x + endPoint.x) / 2 + edge.midXOffset
        }

        return ResolvedEdge(edgeId: edge.id, startPoint: startPoint, endPoint: endPoint, midX: midX)
    }

    static func hitTest(point: CGPoint, edge: CanvasEdge, nodeLookup: [UUID: CanvasNode]) -> Bool {
        guard let resolved = resolveEdge(edge, nodeLookup: nodeLookup) else { return false }

        let s = resolved.startPoint
        let e = resolved.endPoint
        let m = resolved.midX

        if distanceToSegment(point: point, a: s, b: CGPoint(x: m, y: s.y)) < hitTestThreshold {
            return true
        }
        let minY = min(s.y, e.y)
        let maxY = max(s.y, e.y)
        if distanceToSegment(point: point, a: CGPoint(x: m, y: minY), b: CGPoint(x: m, y: maxY)) < hitTestThreshold {
            return true
        }
        if distanceToSegment(point: point, a: CGPoint(x: m, y: e.y), b: e) < hitTestThreshold {
            return true
        }
        return false
    }

    static func draw(
        edge: CanvasEdge,
        nodeLookup: [UUID: CanvasNode],
        in context: CGContext,
        isSelected: Bool,
        isAnimated: Bool = false,
        dashPhase: CGFloat = 0,
        isDark: Bool
    ) {
        guard let resolved = resolveEdge(edge, nodeLookup: nodeLookup) else { return }

        let startPoint = resolved.startPoint
        let endPoint = resolved.endPoint
        let midX = resolved.midX

        let lineColor: NSColor
        let lineWidth: CGFloat
        if isSelected {
            lineColor = accent
            lineWidth = 2.0
        } else if isAnimated {
            lineColor = accent.withAlphaComponent(0.7)
            lineWidth = 1.5
        } else {
            lineColor = isDark ? lineColorDark : lineColorLight
            lineWidth = 1.25
        }

        context.setStrokeColor(lineColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: isAnimated ? dashPhase : 0, lengths: [6, 4])

        let path = CGMutablePath()
        path.move(to: startPoint)

        let hDist = abs(midX - startPoint.x)
        let vDist = abs(endPoint.y - startPoint.y)

        if vDist < 2 {
            path.addLine(to: endPoint)
        } else if hDist < bendRadius * 2 || vDist < bendRadius * 2 {
            path.addLine(to: CGPoint(x: midX, y: startPoint.y))
            path.addLine(to: CGPoint(x: midX, y: endPoint.y))
            path.addLine(to: endPoint)
        } else {
            let corner1 = CGPoint(x: midX, y: startPoint.y)
            let corner2 = CGPoint(x: midX, y: endPoint.y)
            path.addArc(tangent1End: corner1, tangent2End: corner2, radius: bendRadius)
            path.addArc(tangent1End: corner2, tangent2End: endPoint, radius: bendRadius)
            path.addLine(to: endPoint)
        }

        context.addPath(path)
        context.strokePath()

        context.setLineDash(phase: 0, lengths: [])

        let portFill = (isSelected || isAnimated) ? accent : (isDark ? portBgColorDark : NSColor.white)
        drawPortCircle(at: endPoint, radius: portRadius, strokeColor: lineColor, fillColor: portFill, in: context)
    }

    private static func drawPortCircle(
        at center: CGPoint,
        radius: CGFloat,
        strokeColor: NSColor,
        fillColor: NSColor,
        in context: CGContext
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.setFillColor(fillColor.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect)
    }

    private static func distanceToSegment(point p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy

        if lenSq < 0.001 {
            return hypot(p.x - a.x, p.y - a.y)
        }

        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
