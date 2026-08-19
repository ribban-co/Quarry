import Foundation
import SwiftData

@Observable
@MainActor
final class AgentChatController {

    private(set) var messages: [AgentMessage] = []
    private(set) var chats: [AgentChat] = []
    private(set) var currentChat: AgentChat?
    private(set) var isStreaming = false
    private(set) var streamingParts: [StreamingPart] = []
    private(set) var error: String?

    var selectedConnections: [Connection] = []

    /// Persistence scope for `AgentChat` records (stored in `AgentChat.notebookId`).
    /// The notebook agent passes the notebook id; the table chat sidebar passes a
    /// stable per-connection id so each connection keeps its own chat history.
    private let scopeId: UUID
    private let modelContainer: ModelContainer
    private weak var notebookDataController: NotebookDataController?
    /// Supplies the currently open table for table-chat mode. Nil when this
    /// controller serves the notebook agent panel.
    private let tableContextProvider: (@MainActor () -> TableAgentContext?)?
    let engine = NotebookAgentEngine()
    private var streamingTask: Task<Void, Never>?
    private var streamingTaskID = UUID()
    private var reasoningStartTime: Date?
    private var conversationSummary: String?
    private var summarizedMessageCount = 0
    private var cachedTotalCharacters = 0

    private let summaryTriggerMessageCount = 18
    private let recentMessageWindow = 10
    private let summaryCharacterThreshold = 12_000

    init(
        scopeId: UUID,
        modelContainer: ModelContainer,
        notebookDataController: NotebookDataController? = nil,
        tableContextProvider: (@MainActor () -> TableAgentContext?)? = nil
    ) {
        self.scopeId = scopeId
        self.modelContainer = modelContainer
        self.notebookDataController = notebookDataController
        self.tableContextProvider = tableContextProvider
    }

    deinit {
        MainActor.assumeIsolated {
            streamingTask?.cancel()
        }
    }

    func load() {
        let context = modelContainer.mainContext
        let id = scopeId
        let chatDescriptor = FetchDescriptor<AgentChat>(
            predicate: #Predicate { $0.notebookId == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        chats = (try? context.fetch(chatDescriptor)) ?? []

        if let unused = unusedChat {
            selectChat(unused)
        } else {
            createNewChat()
        }
    }

    func createNewChat() {
        cancelStreamingTask()
        streamingParts = []
        isStreaming = false
        resetConversationSummary()
        notebookDataController?.isAgentStreaming = false

        if let unused = unusedChat {
            selectChat(unused)
            return
        }

        selectChat(insertChat())
    }

    /// Guarantees an unused chat sits at the top of `chats` so the history list
    /// always offers a "New Chat" entry to switch into. Unlike `createNewChat()`
    /// this never changes the current selection, and it refreshes the unused
    /// chat's timestamp so it stays grouped under Today.
    func ensureUnusedChatExists() {
        if let unused = unusedChat {
            unused.updatedAt = Date()
            save()
            return
        }
        _ = insertChat()
    }

    /// The newest chat when it has no messages yet. Only the newest can be
    /// unused — `createNewChat()` reuses it rather than stacking empties.
    private var unusedChat: AgentChat? {
        guard let latest = chats.first else { return nil }
        let chatId = latest.id
        let descriptor = FetchDescriptor<AgentMessage>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        let count = (try? modelContainer.mainContext.fetchCount(descriptor)) ?? 0
        return count == 0 ? latest : nil
    }

    private func insertChat() -> AgentChat {
        let chat = AgentChat(notebookId: scopeId)
        modelContainer.mainContext.insert(chat)
        save()
        chats.insert(chat, at: 0)
        return chat
    }

    func selectChat(_ chat: AgentChat) {
        currentChat = chat
        loadMessages(for: chat)
    }

    func deleteChat(_ chat: AgentChat) {
        let chatId = chat.id
        let messageDescriptor = FetchDescriptor<AgentMessage>(
            predicate: #Predicate { $0.chatId == chatId }
        )
        if let messages = try? modelContainer.mainContext.fetch(messageDescriptor) {
            for msg in messages {
                modelContainer.mainContext.delete(msg)
            }
        }
        modelContainer.mainContext.delete(chat)
        save()
        chats.removeAll { $0.id == chatId }

        if currentChat?.id == chatId {
            if let next = chats.first {
                selectChat(next)
            } else {
                createNewChat()
            }
        }
    }

    @discardableResult
    func send(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chat = currentChat, !isStreaming else { return false }

        if messages.isEmpty {
            chat.title = String(trimmed.prefix(60))
            chat.updatedAt = Date()
            save()
        }

        let userMessage = AgentMessage(chatId: chat.id, role: .user, content: text)
        modelContainer.mainContext.insert(userMessage)
        save()
        messages.append(userMessage)
        trackMessageCharacters(userMessage)

        isStreaming = true
        notebookDataController?.isAgentStreaming = true
        startStreamingTask(for: chat)
        return true
    }

    func cancelStreaming() {
        cancelStreamingTask()
        let finalContent = buildFinalContent()
        if !finalContent.isEmpty, let chat = currentChat {
            let msg = AgentMessage(chatId: chat.id, role: .assistant, content: finalContent)
            modelContainer.mainContext.insert(msg)
            save()
            messages.append(msg)
            trackMessageCharacters(msg)
        }
        streamingParts = []
        isStreaming = false
        notebookDataController?.isAgentStreaming = false
    }

    func retry(from messageId: UUID) {
        guard !isStreaming else { return }
        guard let chat = currentChat else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

        let toDelete = Array(messages[index...])
        for msg in toDelete {
            modelContainer.mainContext.delete(msg)
        }
        messages.removeSubrange(index...)
        resetConversationSummary()
        save()

        isStreaming = true
        notebookDataController?.isAgentStreaming = true
        startStreamingTask(for: chat)
    }

    func setFeedback(_ feedback: AgentMessageFeedback?, for messageId: UUID) {
        guard let msg = messages.first(where: { $0.id == messageId }) else { return }
        msg.feedback = feedback
        save()
    }

    // MARK: - Agent Loop

    private func cancelStreamingTask() {
        streamingTaskID = UUID()
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func startStreamingTask(for chat: AgentChat) {
        cancelStreamingTask()

        let taskID = UUID()
        streamingTaskID = taskID
        streamingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.streamingTaskID == taskID {
                    self.streamingTask = nil
                }
            }
            await self.performAgentLoop(chat: chat, taskID: taskID)
        }
    }

    private func performAgentLoop(chat: AgentChat, taskID: UUID) async {
        streamingParts = []
        error = nil
        engine.clearPendingCreations()

        // Pre-fetch Convex deployments so the agent knows available environments
        await engine.prefetchConvexDeployments(connections: selectedConnections)

        var accumulatedAssistantText = ""

        do {
            try await refreshConversationSummaryIfNeeded()

            var llmMessages = buildLLMMessages()
            var roundNumber = 0

            for _ in 0..<100 {
                guard !Task.isCancelled else { break }

                roundNumber += 1

                let currentBlocks = notebookDataController?.blocks ?? []
                let surface: AgentSurface = if let tableContextProvider {
                    .table(tableContextProvider())
                } else {
                    .notebook(blocks: currentBlocks)
                }
                let round = try await engine.performRound(
                    messages: llmMessages,
                    connections: selectedConnections,
                    surface: surface,
                    conversationSummary: conversationSummary,
                    onToken: { [weak self] token in
                        guard let self, self.streamingTaskID == taskID else { return }
                        self.appendOrUpdateText(token)
                    },
                    onThinking: { [weak self] token in
                        guard let self, self.streamingTaskID == taskID else { return }
                        self.appendOrUpdateThinking(token)
                    }
                )

                if let tokenUsage = round.tokenUsage {
                    LLMTokenUsageService.shared.record(tokenUsage)
                }
                let thinkingSerialized = serializeThinking(from: round.responseContent)

                if round.toolCalls.isEmpty {
                    accumulatedAssistantText += thinkingSerialized
                    accumulatedAssistantText += round.text
                    break
                }

                accumulatedAssistantText += thinkingSerialized
                accumulatedAssistantText += round.text

                llmMessages.append(round.assistantMessage)

                // Show all tool calls as active in the UI and serialize inputs for display
                var toolCallMeta: [(id: String, name: String, argumentsJSON: String)] = []
                for toolCall in round.toolCalls {
                    let argumentsJSON = serializeToolInput(toolCall.input)
                    let activeInfo = ToolMetadata.displayInfo(for: toolCall.name, arguments: argumentsJSON)
                    appendToolCall(id: toolCall.id, name: toolCall.name, displayText: activeInfo.text, iconName: activeInfo.icon, round: roundNumber)
                    toolCallMeta.append((id: toolCall.id, name: toolCall.name, argumentsJSON: argumentsJSON))
                }

                // Execute all tool calls concurrently (Tasks inherit @MainActor).
                // The tasks are unstructured, so cancel them explicitly when the
                // loop is cancelled — otherwise Stop leaves queries running and
                // the loop suspended on their results.
                let tasks = round.toolCalls.enumerated().map { (i, toolCall) in
                    let blocks = currentBlocks
                    let conns = selectedConnections
                    return (index: i, task: Task {
                        await engine.executeToolCall(toolCall, connections: conns, blocks: blocks)
                    })
                }
                let toolResults: [(index: Int, result: String)] = await withTaskCancellationHandler {
                    var results: [(index: Int, result: String)] = []
                    for entry in tasks {
                        results.append((index: entry.index, result: await entry.task.value))
                    }
                    return results
                } onCancel: {
                    for entry in tasks { entry.task.cancel() }
                }

                // Process side effects after all tools complete
                for creation in engine.pendingBlockCreations {
                    handleBlockCreation(creation)
                }
                if let infoUpdate = engine.pendingNotebookInfoUpdate {
                    handleNotebookInfoUpdate(infoUpdate)
                }
                if let arrangement = engine.pendingDashboardArrangement {
                    handleDashboardArrangement(arrangement)
                }
                engine.clearPendingCreations()

                // Build messages in original tool call order
                for toolResult in toolResults {
                    guard !Task.isCancelled else { break }

                    let meta = toolCallMeta[toolResult.index]
                    let completeInfo = ToolMetadata.displayInfo(for: meta.name, arguments: meta.argumentsJSON)
                    markToolCallComplete(id: meta.id, displayText: completeInfo.text)
                    if !accumulatedAssistantText.isEmpty && !accumulatedAssistantText.hasSuffix("\n") {
                        accumulatedAssistantText += "\n"
                    }
                    accumulatedAssistantText += "<tool_call name=\"\(meta.name)\">\(completeInfo.text)</tool_call>\n"

                    llmMessages.append(LLMChatMessage(
                        role: .tool,
                        content: toolResult.result,
                        toolCallId: meta.id,
                        name: meta.name
                    ))
                }
            }
        } catch {
            if !Task.isCancelled && streamingTaskID == taskID {
                self.error = error.localizedDescription
            }
        }

        // A superseded loop resuming late must not touch shared streaming
        // state — a newer stream owns the UI now.
        guard streamingTaskID == taskID else { return }

        guard !Task.isCancelled else {
            isStreaming = false
            notebookDataController?.isAgentStreaming = false
            streamingParts = []
            return
        }

        if !accumulatedAssistantText.isEmpty {
            let assistantMessage = AgentMessage(chatId: chat.id, role: .assistant, content: accumulatedAssistantText)
            modelContainer.mainContext.insert(assistantMessage)
            save()
            messages.append(assistantMessage)
            trackMessageCharacters(assistantMessage)
        }

        streamingParts = []
        isStreaming = false
        notebookDataController?.isAgentStreaming = false
    }

    // MARK: - Streaming Parts Helpers

    private func appendOrUpdateText(_ token: String) {
        if case .text(let existing) = streamingParts.last {
            streamingParts[streamingParts.count - 1] = .text(existing + token)
        } else {
            streamingParts.append(.text(token))
        }
    }

    private func appendOrUpdateThinking(_ token: String) {
        if case .thinking(let existing) = streamingParts.last {
            streamingParts[streamingParts.count - 1] = .thinking(existing + token)
        } else {
            reasoningStartTime = Date()
            streamingParts.append(.thinking(token))
        }
    }

    private func appendToolCall(id: String, name: String, displayText: String, iconName: String?, round: Int) {
        streamingParts.append(.toolCall(
            id: id,
            name: name,
            displayText: displayText,
            iconName: iconName,
            isComplete: false,
            round: round
        ))
    }

    private func markToolCallComplete(id: String, displayText: String) {
        guard let idx = streamingParts.lastIndex(where: {
            if case .toolCall(let tcId, _, _, _, _, _) = $0 { return tcId == id }
            return false
        }),
        case .toolCall(let tcId, let name, _, let icon, _, let round) = streamingParts[idx] else {
            return
        }
        streamingParts[idx] = .toolCall(id: tcId, name: name, displayText: displayText, iconName: icon, isComplete: true, round: round)
    }

    private func buildFinalContent() -> String {
        streamingParts.map { part in
            switch part {
            case .thinking(let text):
                let duration = reasoningStartTime.map { max(1, Int(Date().timeIntervalSince($0))) } ?? 1
                return "<thinking duration=\"\(duration)\">\n\(text)\n</thinking>\n"
            case .text(let text):
                return text
            case .toolCall(_, let name, let displayText, _, _, _):
                return "<tool_call name=\"\(name)\">\(displayText)</tool_call>\n"
            }
        }.joined()
    }

    // MARK: - Block Creation

    private func handleBlockCreation(_ request: BlockCreationRequest) {
        if let targetId = request.targetBlockId {
            handleBlockUpdate(request, targetId: targetId)
            return
        }

        guard let dataController = notebookDataController else { return }

        switch request.kind {
        case .chart:
            dataController.addChartBlock()
            if let block = dataController.blocks.last, var config = request.config {
                block.title = request.title
                block.isHiddenInDashboard = true

                if let outputName = request.sourceQueryOutputName,
                   let queryBlock = dataController.blocks.first(where: {
                       $0.blockType == .query && $0.queryBlockConfig()?.outputName == outputName
                   }) {
                    config.sourceQueryBlockId = queryBlock.id.uuidString
                }

                block.saveChartConfig(config)
                dataController.updateBlock(block)
            }
        case .text:
            dataController.addTextBlock()
            if let block = dataController.blocks.last {
                block.title = request.title
                block.isHiddenInDashboard = true
                block.textContent = request.textContent ?? ""
                dataController.updateBlock(block)
            }
        case .singleValue:
            let insertIndex = dataController.blocks.lastIndex(where: { $0.blockType == .singleValue })
                .map { $0 + 1 } ?? 0
            dataController.insertSingleValueBlock(at: insertIndex)
            if let block = dataController.blocks[safe: insertIndex], let config = request.singleValueConfig {
                block.title = request.title
                block.isHiddenInDashboard = true
                if insertIndex > 0, dataController.blocks[insertIndex - 1].blockType == .singleValue {
                    block.notebookInline = true
                }
                block.saveSingleValueConfig(config)
                dataController.updateBlock(block)
            }
        case .query:
            dataController.addQueryBlock()
            if let block = dataController.blocks.last, let config = request.queryBlockConfig {
                block.title = request.title
                block.isHiddenInDashboard = true
                block.saveQueryBlockConfig(config)
                dataController.updateBlock(block)
            }
        }

        dataController.invalidateDashboardBlocks()
    }

    private func handleNotebookInfoUpdate(_ update: NotebookInfoUpdate) {
        guard let dataController = notebookDataController else { return }
        dataController.title = update.title
        if !update.description.isEmpty {
            dataController.descriptionText = update.description
        }
    }

    private func handleBlockUpdate(_ request: BlockCreationRequest, targetId: UUID) {
        guard let dataController = notebookDataController,
              let block = dataController.blocks.first(where: { $0.id == targetId }) else { return }

        switch request.kind {
        case .chart:
            guard var config = request.config else { return }
            if let outputName = request.sourceQueryOutputName,
               let queryBlock = dataController.blocks.first(where: {
                   $0.blockType == .query && $0.queryBlockConfig()?.outputName == outputName
               }) {
                config.sourceQueryBlockId = queryBlock.id.uuidString
            }
            if !request.title.isEmpty { block.title = request.title }
            block.saveChartConfig(config)
            dataController.updateBlock(block)
            dataController.refreshChartViewModel(for: targetId, config: config)

        case .text:
            block.textContent = request.textContent ?? ""
            dataController.updateBlock(block)

        case .singleValue:
            guard let config = request.singleValueConfig else { return }
            if !request.title.isEmpty { block.title = request.title }
            block.saveSingleValueConfig(config)
            dataController.updateBlock(block)
            dataController.refreshSingleValueViewModel(for: targetId)

        case .query:
            guard let config = request.queryBlockConfig else { return }
            if !request.title.isEmpty { block.title = request.title }
            block.saveQueryBlockConfig(config)
            dataController.updateBlock(block)
            dataController.refreshQueryViewModel(for: targetId)
        }
    }

    private func handleDashboardArrangement(_ arrangement: DashboardArrangementRequest) {
        guard let dataController = notebookDataController else { return }

        var blocksToReveal: [NotebookBlock] = []

        for (sortOrder, layout) in arrangement.layouts.enumerated() {
            guard let blockId = UUID(uuidString: layout.blockId),
                  let block = dataController.blocks.first(where: { $0.id == blockId }) else { continue }

            block.dashboardSortOrder = sortOrder
            if let width = layout.widthFraction {
                block.blockWidthFraction = max(0.1, min(1.0, width))
            }
            if let height = layout.height {
                block.blockHeight = max(80, height)
            }
            if let inline = layout.inline {
                block.dashboardInline = inline
            }

            let shouldBeHidden = layout.hidden ?? false
            if block.isHiddenInDashboard && !shouldBeHidden {
                blocksToReveal.append(block)
            } else if let hidden = layout.hidden {
                block.isHiddenInDashboard = hidden
            }
        }

        if !blocksToReveal.isEmpty {
            let sorted = blocksToReveal.sorted { $0.dashboardSortOrder < $1.dashboardSortOrder }
            sorted.first?.isHiddenInDashboard = false
        }

        if arrangement.switchToDashboard {
            dataController.viewMode = .dashboard
        }

        dataController.invalidateDashboardBlocks()
        dataController.saveContext()

        if !blocksToReveal.isEmpty {
            let sorted = blocksToReveal.sorted { $0.dashboardSortOrder < $1.dashboardSortOrder }
            let remaining = Array(sorted.dropFirst())
            if !remaining.isEmpty {
                revealBlocksSequentially(remaining, dataController: dataController)
            }
        }
    }

    private func revealBlocksSequentially(_ blocks: [NotebookBlock], dataController: NotebookDataController) {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            for block in blocks {
                block.isHiddenInDashboard = false
                dataController.invalidateDashboardBlocks()
                dataController.saveContext()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // MARK: - Message Building

    private func buildLLMMessages() -> [LLMChatMessage] {
        let visibleMessages: ArraySlice<AgentMessage>
        if conversationSummary != nil && summarizedMessageCount > 0 {
            visibleMessages = messages.dropFirst(summarizedMessageCount)
        } else {
            visibleMessages = messages[...]
        }

        return visibleMessages.compactMap { msg in
            switch msg.role {
            case .user:
                return LLMChatMessage(role: .user, content: msg.content)
            case .assistant:
                let strippedContent = stripSerializedTags(from: msg.content)
                guard !strippedContent.isEmpty else { return nil }
                return LLMChatMessage(role: .assistant, content: strippedContent)
            }
        }
    }

    private func serializeToolInput(_ input: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: input),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func serializeThinking(from responseContent: [ResponseContentBlock]) -> String {
        var result = ""
        for content in responseContent {
            if case .thinking(let text, _) = content {
                let duration = reasoningStartTime.map { max(1, Int(Date().timeIntervalSince($0))) } ?? 1
                result += "<thinking duration=\"\(duration)\">\n\(text)\n</thinking>\n"
                reasoningStartTime = nil
            }
        }
        return result
    }

    private static let toolCallTagRegex = try! Regex("<tool_call[^>]*>[^<]*</tool_call>\\n*")
    private static let thinkingTagRegex = try! Regex("<thinking[^>]*>[\\s\\S]*?</thinking>\\n*")

    private func stripSerializedTags(from text: String) -> String {
        text.replacing(Self.toolCallTagRegex, with: "")
            .replacing(Self.thinkingTagRegex, with: "")
    }

    private func refreshConversationSummaryIfNeeded() async throws {
        guard shouldSummarizeConversation else { return }

        let targetCount = max(0, messages.count - recentMessageWindow)
        guard targetCount > summarizedMessageCount else { return }

        let sourceMessages = Array(messages[summarizedMessageCount..<targetCount])
        let transcript = buildTranscript(from: sourceMessages)
        guard !transcript.isEmpty else {
            summarizedMessageCount = targetCount
            return
        }

        let systemPrompt = """
        You maintain compact memory for Quarry AI notebook conversations.

        Return plain text only under these headings:
        Goals:
        Database facts:
        Notebook progress:
        Open questions:
        Constraints:

        Rules:
        1. Keep only durable facts that matter for future turns.
        2. Preserve exact table names, column names, block titles, tool names, and connection names when they appear.
        3. Preserve unresolved user requests and decisions already made.
        4. Exclude chain-of-thought, temporary speculation, and conversational filler.
        5. If a previous summary exists, merge it with the new transcript into one refreshed summary.
        6. Keep the result concise and factual.
        7. Use short bullet-style lines under each heading, not paragraphs.
        8. If a name or value is uncertain, omit it rather than paraphrasing it.
        """

        let userPrompt = """
        <previous_summary>
        \(conversationSummary ?? "None")
        </previous_summary>

        <new_transcript>
        \(transcript)
        </new_transcript>
        """

        let summary = try await LLM.chatCompletion(
            messages: [LLMChatMessage(role: .user, content: userPrompt)],
            systemPrompt: systemPrompt,
            maxTokens: 1200,
            thinkingMode: .disabled
        )
        if let tokenUsage = summary.tokenUsage {
            LLMTokenUsageService.shared.record(tokenUsage)
        }

        let normalizedSummary = summary.assistantMessage.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedSummary, !normalizedSummary.isEmpty {
            conversationSummary = normalizedSummary
            summarizedMessageCount = targetCount
        }
    }

    private var shouldSummarizeConversation: Bool {
        messages.count > summaryTriggerMessageCount || cachedTotalCharacters > summaryCharacterThreshold
    }

    private func trackMessageCharacters(_ message: AgentMessage) {
        cachedTotalCharacters += normalizedMessageContent(for: message).count
    }

    private func buildTranscript(from messages: [AgentMessage]) -> String {
        messages.compactMap { message in
            let normalized = normalizedMessageContent(for: message)
            guard !normalized.isEmpty else { return nil }
            return "\(message.role == .user ? "User" : "Assistant"): \(normalized)"
        }
        .joined(separator: "\n")
    }

    private func normalizedMessageContent(for message: AgentMessage) -> String {
        switch message.role {
        case .user:
            message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        case .assistant:
            stripSerializedTags(from: message.content).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func resetConversationSummary() {
        conversationSummary = nil
        summarizedMessageCount = 0
        cachedTotalCharacters = 0
    }

    // MARK: - Persistence

    private func loadMessages(for chat: AgentChat) {
        let chatId = chat.id
        let descriptor = FetchDescriptor<AgentMessage>(
            predicate: #Predicate { $0.chatId == chatId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        messages = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        resetConversationSummary()
        for msg in messages { trackMessageCharacters(msg) }
    }

    private func save() {
        try? modelContainer.mainContext.save()
    }
}
