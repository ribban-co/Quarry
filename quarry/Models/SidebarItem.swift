import Foundation

enum SidebarItem: Identifiable, Equatable {
    case connection(UUID)
    case notebook(UUID, title: String)

    var id: String {
        switch self {
        case .connection(let uuid): "connection-\(uuid.uuidString)"
        case .notebook(let uuid, _): "notebook-\(uuid.uuidString)"
        }
    }

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        switch (lhs, rhs) {
        case (.connection(let a), .connection(let b)):
            a == b
        case (.notebook(let a, _), .notebook(let b, _)):
            a == b
        default:
            false
        }
    }
}
