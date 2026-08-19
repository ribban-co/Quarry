import Foundation

struct CanvasViewport: Codable, Equatable {
    var offset: CGPoint = .zero
    var zoomLevel: CGFloat = 0.5

    static let minZoom: CGFloat = 0.25
    static let maxZoom: CGFloat = 4.0
    static let zoomStep: CGFloat = 0.1

    func canvasPoint(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - offset.x) / zoomLevel,
            y: (screenPoint.y - offset.y) / zoomLevel
        )
    }

    func screenPoint(from canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * zoomLevel + offset.x,
            y: canvasPoint.y * zoomLevel + offset.y
        )
    }

    mutating func zoom(by delta: CGFloat, centeredAt screenPoint: CGPoint) {
        let canvasPt = canvasPoint(from: screenPoint)
        zoomLevel = max(Self.minZoom, min(Self.maxZoom, zoomLevel + delta))
        offset = CGPoint(
            x: screenPoint.x - canvasPt.x * zoomLevel,
            y: screenPoint.y - canvasPt.y * zoomLevel
        )
    }

    mutating func pan(by delta: CGPoint) {
        offset = CGPoint(
            x: offset.x + delta.x,
            y: offset.y + delta.y
        )
    }

    mutating func zoomToFit(nodes: [CanvasNode], in viewSize: CGSize, padding: CGFloat = 60) {
        guard !nodes.isEmpty else { return }

        let minX = nodes.map(\.position.x).min()!
        let minY = nodes.map(\.position.y).min()!
        let maxX = nodes.map { $0.position.x + $0.size.width }.max()!
        let maxY = nodes.map { $0.position.y + $0.size.height }.max()!

        let contentWidth = maxX - minX + padding * 2
        let contentHeight = maxY - minY + padding * 2

        guard contentWidth > 0, contentHeight > 0 else { return }

        let scaleX = viewSize.width / contentWidth
        let scaleY = viewSize.height / contentHeight
        zoomLevel = max(Self.minZoom, min(Self.maxZoom, min(scaleX, scaleY)))

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        offset = CGPoint(
            x: viewSize.width / 2 - centerX * zoomLevel,
            y: viewSize.height / 2 - centerY * zoomLevel
        )
    }
}
