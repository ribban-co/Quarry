import SwiftData
import Foundation

@Model
final class AgentChat {
    var id: UUID = UUID()
    var notebookId: UUID = UUID()
    var title: String = "New Chat"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(notebookId: UUID, title: String = "New Chat") {
        self.notebookId = notebookId
        self.title = title
    }
}
