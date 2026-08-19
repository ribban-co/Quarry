import Foundation

struct CanvasNode: Identifiable, Codable, Equatable {
    let id: UUID
    var position: CGPoint
    var size: CGSize
    var kind: NodeKind
    var zIndex: Int

    init(
        id: UUID = UUID(),
        position: CGPoint,
        size: CGSize = CGSize(width: 220, height: 100),
        kind: NodeKind,
        zIndex: Int = 0
    ) {
        self.id = id
        self.position = position
        self.size = size
        self.kind = kind
        self.zIndex = zIndex
    }

    var frame: CGRect {
        CGRect(origin: position, size: size)
    }

    func contains(point: CGPoint) -> Bool {
        frame.contains(point)
    }
}

enum NodeKind: Codable, Equatable {
    case erdTable(ERDTableData)

    // Future expansion:
    // case shape(ShapeData)
    // case text(TextData)
    // case freeformPath(PathData)
}

struct ERDTableData: Codable, Equatable {
    let schemaName: String?
    let tableName: String
    var columns: [ERDColumnInfo]
}

struct ERDColumnInfo: Codable, Equatable {
    let name: String
    let dataType: String
    let isPrimaryKey: Bool
    let isForeignKey: Bool
    let isNullable: Bool
    let foreignKeyTarget: ForeignKeyRef?
}

struct ForeignKeyRef: Codable, Equatable {
    let schema: String?
    let table: String
    let column: String
}
