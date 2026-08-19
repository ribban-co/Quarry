import SwiftData
import Foundation

enum AgentMessageRole: String, Codable {
    case user
    case assistant
}

enum AgentMessageFeedback: String, Codable {
    case up
    case down
}

@Model
final class AgentMessage {
    var id: UUID = UUID()
    var chatId: UUID = UUID()
    var role: AgentMessageRole = AgentMessageRole.user
    var content: String = ""
    var createdAt: Date = Date()
    var feedbackRaw: String? = nil

    var feedback: AgentMessageFeedback? {
        get { feedbackRaw.flatMap(AgentMessageFeedback.init(rawValue:)) }
        set { feedbackRaw = newValue?.rawValue }
    }

    init(chatId: UUID, role: AgentMessageRole, content: String) {
        self.chatId = chatId
        self.role = role
        self.content = content
    }
}
