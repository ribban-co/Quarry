enum StreamingPart: Equatable {
    case thinking(String)
    case text(String)
    case toolCall(id: String, name: String, displayText: String, iconName: String?, isComplete: Bool, round: Int)
}
