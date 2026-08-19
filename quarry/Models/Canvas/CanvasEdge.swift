import Foundation

struct CanvasEdge: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceNodeId: UUID
    let sourcePort: String
    let targetNodeId: UUID
    let targetPort: String
    var kind: EdgeKind
    var label: String?
    var midXOffset: CGFloat

    init(
        id: UUID = UUID(),
        sourceNodeId: UUID,
        sourcePort: String,
        targetNodeId: UUID,
        targetPort: String,
        kind: EdgeKind = .foreignKey,
        label: String? = nil,
        midXOffset: CGFloat = 0
    ) {
        self.id = id
        self.sourceNodeId = sourceNodeId
        self.sourcePort = sourcePort
        self.targetNodeId = targetNodeId
        self.targetPort = targetPort
        self.kind = kind
        self.label = label
        self.midXOffset = midXOffset
    }
}

enum EdgeKind: Codable, Equatable {
    case foreignKey

    // Future expansion:
    // case line
    // case arrow
    // case dashed
}
