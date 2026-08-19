import Foundation

struct CanvasDocument: Codable, Equatable {
    var nodes: [CanvasNode]
    var edges: [CanvasEdge]
    var viewport: CanvasViewport

    init(
        nodes: [CanvasNode] = [],
        edges: [CanvasEdge] = [],
        viewport: CanvasViewport = CanvasViewport()
    ) {
        self.nodes = nodes
        self.edges = edges
        self.viewport = viewport
    }

    func node(withId id: UUID) -> CanvasNode? {
        nodes.first { $0.id == id }
    }

    mutating func updateNodePosition(_ nodeId: UUID, to position: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[index].position = position
    }

    mutating func removeNode(_ nodeId: UUID) {
        nodes.removeAll { $0.id == nodeId }
        edges.removeAll { $0.sourceNodeId == nodeId || $0.targetNodeId == nodeId }
    }

    mutating func bringToFront(_ nodeId: UUID) {
        let maxZ = nodes.map(\.zIndex).max() ?? 0
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[index].zIndex = maxZ + 1
    }

    mutating func updateEdgeMidXOffset(_ edgeId: UUID, offset: CGFloat) {
        guard let index = edges.firstIndex(where: { $0.id == edgeId }) else { return }
        edges[index].midXOffset = offset
    }
}
