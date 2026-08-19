import Foundation

final class SidebarItemRegistry: @unchecked Sendable {
    static let shared = SidebarItemRegistry()

    private(set) var items: [SidebarItem] = []

    private init() {}

    func addConnection(_ id: UUID) {
        let item = SidebarItem.connection(id)
        guard !items.contains(item) else { return }
        items.append(item)
        postDidChange()
    }

    func removeConnection(_ id: UUID) {
        items.removeAll { $0 == .connection(id) }
        postDidChange()
    }

    func addNotebook(id: UUID, title: String) {
        let item = SidebarItem.notebook(id, title: title)
        guard !items.contains(item) else { return }
        items.append(item)
        postDidChange()
    }

    func removeNotebook(_ id: UUID) {
        items.removeAll {
            if case .notebook(let itemId, _) = $0 { return itemId == id }
            return false
        }
        postDidChange()
    }

    private func postDidChange() {
        NotificationCenter.default.post(name: .sidebarItemsDidChange, object: nil)
    }
}
