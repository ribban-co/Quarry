import SwiftUI

@MainActor
@Observable class SidebarViewModel {
    @ObservationIgnored
    private let connectionService: ConnectionService
    @ObservationIgnored
    private weak var windowConnectionInstance: ConnectionInstance?

    enum SidebarNavItem: Hashable {
        case home
        case connection(UUID)
    }

    var activeSidebarItem: SidebarNavItem = .home
    var searchText: String = ""
    var sidebarViewMode: SidebarViewMode = .tables
    var isShowingAdvancedHistory: Bool = false

    var activeConnection: ConnectionInstance? {
        windowConnectionInstance ?? connectionService.activeConnectionInstance
    }

    init(connectionService: ConnectionService = .shared, windowConnectionInstance: ConnectionInstance? = nil) {
        self.connectionService = connectionService
        self.windowConnectionInstance = windowConnectionInstance

        if let windowInstance = windowConnectionInstance {
            self.activeSidebarItem = .connection(windowInstance.id)
        }
    }

    func changeActiveSidebarItem(_ item: SidebarNavItem) {
        activeSidebarItem = item

        switch item {
        case .home:
            WindowController.switchToTab(.home)
        case .connection(let instanceId):
            WindowController.switchToTab(.connection(instanceId))
        }
    }

    func createNewConnectionInstance(for connection: Connection) -> UUID {
        connectionService.createNewConnectionInstance(for: connection)
    }

    func disconnectConnectionInstance(_ instanceId: UUID) async {
        await connectionService.removeConnectionInstance(instanceId)
    }

    func connectionInstance(for id: UUID) -> ConnectionInstance? {
        connectionService.getInstance(id)
    }

    func createCollection(withName: String) async throws {
        guard let activeConnection else { return }
        try await activeConnection.databaseService.createCollection(named: withName)
    }

    func loadActiveConnection() async {
        try? await activeConnection?.connect()
    }
}
