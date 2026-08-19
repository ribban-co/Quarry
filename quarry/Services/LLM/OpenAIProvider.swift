//
//  OpenAIProvider.swift
//  Quarry
//

import Foundation

/// OpenAI Chat Completions backend. Same wire format the Bedrock
/// OpenAI-compatible endpoint spoke, minus the AWS auth — the user's own key
/// goes in the Authorization header.
final class OpenAIProvider: LLMProvider, Sendable {

    static let shared = OpenAIProvider()

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private init() {}

    var kind: LLMProviderKind { .openAI }

    // MARK: - Streaming

    func chatCompletionStream(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        tools: [LLMToolDefinition],
        maxTokens: Int,
        model: String,
        thinkingMode: LLMThinkingMode,
        onTextDelta: @MainActor @Sendable (String) -> Void,
        onThinkingDelta: @MainActor @Sendable (String) -> Void
    ) async throws -> LLMChatResult {
        let request = try await buildRequest(
            messages: messages, systemPrompt: systemPrompt, tools: tools,
            maxTokens: maxTokens, model: model, stream: true,
            thinkingMode: thinkingMode
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        var fullText = ""
        var toolCallsByIndex: [Int: StreamingToolCall] = [:]
        var stopReason: String?
        var tokenUsage: LLMTokenUsage?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let chunkData = payload.data(using: .utf8),
                  let chunk = try? Foundation.JSONDecoder().decode(StreamChunk.self, from: chunkData) else { continue }

            // The usage chunk arrives last, with an empty choices array.
            if let usage = chunk.usage {
                tokenUsage = usage.toTokenUsage()
            }

            guard let choice = chunk.choices.first else { continue }

            if let reason = choice.finishReason, !reason.isEmpty {
                stopReason = reason
            }

            if let content = choice.delta.content, !content.isEmpty {
                fullText += content
                await onTextDelta(content)
            }

            if let toolCalls = choice.delta.toolCalls {
                for partialCall in toolCalls {
                    let index = partialCall.index ?? 0
                    var existing = toolCallsByIndex[index] ?? StreamingToolCall()
                    if let id = partialCall.id, !id.isEmpty { existing.id = id }
                    if let function = partialCall.function {
                        if let name = function.name, !name.isEmpty { existing.name = name }
                        if let arguments = function.arguments, !arguments.isEmpty { existing.arguments += arguments }
                    }
                    toolCallsByIndex[index] = existing
                }
            }
        }

        let toolCalls = toolCallsByIndex.keys.sorted().compactMap { index -> LLMToolCall? in
            guard let call = toolCallsByIndex[index], !call.name.isEmpty else { return nil }
            return LLMToolCall(id: call.id.isEmpty ? "tool_\(index)" : call.id, name: call.name, arguments: call.arguments)
        }

        let assistantMessage = LLMChatMessage(
            role: .assistant,
            content: fullText.isEmpty ? nil : fullText,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )

        return LLMChatResult(
            assistantMessage: assistantMessage,
            content: buildResponseContent(from: assistantMessage),
            stopReason: stopReason,
            tokenUsage: tokenUsage
        )
    }

    // MARK: - Non-streaming

    func chatCompletion(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        tools: [LLMToolDefinition],
        maxTokens: Int,
        model: String,
        thinkingMode: LLMThinkingMode
    ) async throws -> LLMChatResult {
        let request = try await buildRequest(
            messages: messages, systemPrompt: systemPrompt, tools: tools,
            maxTokens: maxTokens, model: model, stream: false,
            thinkingMode: thinkingMode
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.httpError(statusCode: code, body: errorBody)
        }

        let completion = try Foundation.JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = completion.choices.first else {
            throw LLMError.missingMessage
        }

        let assistantMessage = LLMChatMessage(
            role: .assistant,
            content: choice.message.content,
            toolCalls: choice.message.toolCalls?.map {
                LLMToolCall(id: $0.id, name: $0.function.name, arguments: $0.function.arguments)
            }
        )

        return LLMChatResult(
            assistantMessage: assistantMessage,
            content: buildResponseContent(from: assistantMessage),
            stopReason: choice.finishReason,
            tokenUsage: completion.usage?.toTokenUsage()
        )
    }

    // MARK: - Request Building

    private func buildRequest(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        tools: [LLMToolDefinition],
        maxTokens: Int,
        model: String,
        stream: Bool,
        thinkingMode: LLMThinkingMode
    ) async throws -> URLRequest {
        let apiKey = try await LLMSettings.shared.requireAPIKey(for: .openAI)

        // thinkingMode has no chat-completions equivalent; OpenAI reasons on its own terms.
        _ = thinkingMode

        var requestMessages: [OpenAIMessage] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            requestMessages.append(OpenAIMessage(role: LLMChatMessage.Role.system.rawValue, content: systemPrompt))
        }

        for msg in messages {
            var m = OpenAIMessage(role: msg.role.rawValue, content: msg.content)
            m.toolCallId = msg.toolCallId
            m.name = msg.name
            if let toolCalls = msg.toolCalls {
                m.toolCalls = toolCalls.map {
                    OpenAIToolCall(id: $0.id, type: "function", function: .init(name: $0.name, arguments: $0.arguments))
                }
            }
            requestMessages.append(m)
        }

        let openAITools: [OpenAIToolDef]? = tools.isEmpty ? nil : tools.map {
            OpenAIToolDef(function: .init(name: $0.name, description: $0.description, parameters: $0.inputSchema))
        }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: requestMessages,
            tools: openAITools,
            stream: stream,
            streamOptions: stream ? StreamOptions(includeUsage: true) : nil,
            maxCompletionTokens: maxTokens
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300
        request.httpBody = try Foundation.JSONEncoder().encode(requestBody)

        return request
    }

    // MARK: - Response Content Building

    private func buildResponseContent(from message: LLMChatMessage) -> [ResponseContentBlock] {
        var content: [ResponseContentBlock] = []

        if let text = message.content, !text.isEmpty {
            content.append(.text(text))
        }
        for toolCall in message.toolCalls ?? [] {
            let inputData = Data(toolCall.arguments.utf8)
            if let parsed = try? Foundation.JSONDecoder().decode([String: JSONValue].self, from: inputData) {
                content.append(.toolUse(id: toolCall.id, name: toolCall.name, input: parsed.mapValues { $0.toSendable() }))
            } else {
                content.append(.toolUse(id: toolCall.id, name: toolCall.name, input: [:]))
            }
        }

        return content
    }
}

// MARK: - Request Types

private struct OpenAIMessage: Encodable {
    let role: String
    let content: String?
    var toolCalls: [OpenAIToolCall]?
    var toolCallId: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

private struct OpenAIToolCall: Encodable {
    let id: String
    let type: String
    let function: OpenAIFunction

    struct OpenAIFunction: Encodable {
        let name: String
        let arguments: String
    }
}

private struct OpenAIToolDef: Encodable {
    let type = "function"
    let function: FunctionDef

    struct FunctionDef: Encodable {
        let name: String
        let description: String
        let parameters: [String: JSONValue]
    }
}

private struct StreamOptions: Encodable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [OpenAIToolDef]?
    let stream: Bool
    let streamOptions: StreamOptions?
    // Current OpenAI models reject the legacy max_tokens parameter.
    let maxCompletionTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream
        case streamOptions = "stream_options"
        case maxCompletionTokens = "max_completion_tokens"
    }
}

// MARK: - Response Types

private struct Usage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let promptTokensDetails: PromptTokensDetails?

    struct PromptTokensDetails: Decodable {
        let cachedTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptTokensDetails = "prompt_tokens_details"
    }

    func toTokenUsage() -> LLMTokenUsage {
        // OpenAI caches implicitly and reports no creation count.
        LLMTokenUsage(
            inputTokens: promptTokens,
            outputTokens: completionTokens,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: promptTokensDetails?.cachedTokens ?? 0
        )
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Decodable {
        let content: String?
        let toolCalls: [ResponseToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ResponseToolCall: Decodable {
        let id: String
        let function: ResponseFunction
    }

    struct ResponseFunction: Decodable {
        let name: String
        let arguments: String
    }
}

private struct StreamChunk: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
}

private struct Delta: Decodable {
    let content: String?
    let toolCalls: [DeltaToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

private struct DeltaToolCall: Decodable {
    let index: Int?
    let id: String?
    let function: DeltaToolFunction?
}

private struct DeltaToolFunction: Decodable {
    let name: String?
    let arguments: String?
}

private struct StreamingToolCall {
    var id = ""
    var name = ""
    var arguments = ""
}
