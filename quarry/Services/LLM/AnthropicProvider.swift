//
//  AnthropicProvider.swift
//  Quarry
//

import Foundation

/// Direct Anthropic Messages API backend. Auth is the user's own API key, and
/// streaming is plain SSE text rather than Bedrock's binary event-stream framing.
final class AnthropicProvider: LLMProvider, Sendable {

    static let shared = AnthropicProvider()

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    private init() {}

    var kind: LLMProviderKind { .anthropic }

    // MARK: - LLMProvider

    func chatCompletion(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        tools: [LLMToolDefinition],
        maxTokens: Int,
        model: String,
        thinkingMode: LLMThinkingMode
    ) async throws -> LLMChatResult {
        let request = try await buildRequest(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            model: model,
            thinkingMode: thinkingMode,
            stream: false
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        let decoded = try Foundation.JSONDecoder().decode(AnthropicResponse.self, from: data)
        return toLLMChatResult(decoded)
    }

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
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            model: model,
            thinkingMode: thinkingMode,
            stream: true
        )

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var errorData = Data()
            for try await byte in asyncBytes { errorData.append(byte) }
            let errorBody = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("[AnthropicProvider] HTTP \(httpResponse.statusCode): \(errorBody)")
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        var responseId = ""
        var responseRole = "assistant"
        var stopReason: String?
        var inputTokens = 0
        var outputTokens = 0
        var cacheCreationInputTokens: Int?
        var cacheReadInputTokens: Int?
        var textBlocks: [Int: String] = [:]
        var thinkingBlocks: [Int: (text: String, signature: String)] = [:]
        var toolUseBlocks: [Int: (id: String, name: String, inputJSON: String)] = [:]

        // SSE: each event is an `event:` line followed by a `data:` line with the
        // JSON payload. The payload's `type` repeats the event name, so `event:`
        // lines and blanks carry no extra information and are skipped.
        for try await line in asyncBytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = Data(line.dropFirst("data: ".count).utf8)
            guard let event = try? Foundation.JSONDecoder().decode(AnthropicStreamEvent.self, from: payload) else {
                continue
            }

            switch event.type {
            case "message_start":
                if let msg = event.message {
                    responseId = msg.id ?? responseId
                    responseRole = msg.role ?? responseRole
                    if let u = msg.usage {
                        inputTokens = u.input_tokens ?? inputTokens
                        if let cc = u.cache_creation_input_tokens { cacheCreationInputTokens = cc }
                        if let cr = u.cache_read_input_tokens { cacheReadInputTokens = cr }
                    }
                }
            case "content_block_start":
                if let idx = event.index, let block = event.content_block {
                    switch block.type {
                    case "text": textBlocks[idx] = ""
                    case "thinking": thinkingBlocks[idx] = (text: "", signature: "")
                    case "tool_use": toolUseBlocks[idx] = (id: block.id ?? "", name: block.name ?? "", inputJSON: "")
                    default: break
                    }
                }
            case "content_block_delta":
                if let idx = event.index, let delta = event.delta {
                    switch delta.type {
                    case "text_delta":
                        if let text = delta.text {
                            textBlocks[idx, default: ""] += text
                            await onTextDelta(text)
                        }
                    case "thinking_delta":
                        if let thinking = delta.thinking {
                            if var existing = thinkingBlocks[idx] {
                                existing.text += thinking
                                thinkingBlocks[idx] = existing
                            }
                            await onThinkingDelta(thinking)
                        }
                    case "signature_delta":
                        if let sig = delta.signature, var existing = thinkingBlocks[idx] {
                            existing.signature += sig
                            thinkingBlocks[idx] = existing
                        }
                    case "input_json_delta":
                        if let json = delta.partial_json, var existing = toolUseBlocks[idx] {
                            existing.inputJSON += json
                            toolUseBlocks[idx] = existing
                        }
                    default:
                        print("[AnthropicProvider] unhandled delta type: \(delta.type ?? "nil") at index \(idx)")
                    }
                }
            case "message_delta":
                if let delta = event.delta {
                    stopReason = delta.stop_reason ?? stopReason
                }
                if let u = event.usage {
                    outputTokens = u.output_tokens ?? outputTokens
                }
            default:
                break
            }
        }

        let content = buildResponseContent(
            textBlocks: textBlocks,
            thinkingBlocks: thinkingBlocks,
            toolUseBlocks: toolUseBlocks
        )

        if let cacheRead = cacheReadInputTokens, cacheRead > 0 {
            print("[AnthropicProvider] Cache hit: \(cacheRead) tokens read from cache")
        }
        if let cacheWrite = cacheCreationInputTokens, cacheWrite > 0 {
            print("[AnthropicProvider] Cache write: \(cacheWrite) tokens written to cache")
        }

        let response2 = AnthropicResponse(
            id: responseId,
            type: "message",
            role: responseRole,
            content: content,
            stopReason: stopReason,
            usage: AnthropicResponse.Usage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationInputTokens: cacheCreationInputTokens,
                cacheReadInputTokens: cacheReadInputTokens
            )
        )

        return toLLMChatResult(response2)
    }

    // MARK: - Request Building

    private func buildRequest(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        tools: [LLMToolDefinition],
        maxTokens: Int,
        model: String,
        thinkingMode: LLMThinkingMode,
        stream: Bool
    ) async throws -> URLRequest {
        let apiKey = try await LLMSettings.shared.requireAPIKey(for: .anthropic)

        // No temperature/top_p/top_k and no budget_tokens — current models
        // reject them; adaptive thinking is the only knob we send.
        let requestBody = AnthropicRequest(
            model: model,
            maxTokens: maxTokens,
            system: systemPrompt.map { [SystemContentBlock(text: $0)] } ?? [],
            messages: try messages.map(toAnthropicMessage),
            tools: tools.map(toAnthropicTool),
            thinking: thinkingMode == .enabled ? .adaptive : nil,
            stream: stream ? true : nil
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 300
        request.httpBody = try Foundation.JSONEncoder().encode(requestBody)

        return request
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[AnthropicProvider] HTTP \(httpResponse.statusCode): \(errorBody)")
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }
    }

    // MARK: - Neutral ↔ Anthropic Conversions

    private func toAnthropicTool(_ tool: LLMToolDefinition) -> AnthropicToolDefinition {
        AnthropicToolDefinition(name: tool.name, description: tool.description, inputSchema: tool.inputSchema)
    }

    private func toAnthropicMessage(_ message: LLMChatMessage) throws -> AnthropicMessage {
        switch message.role {
        case .system:
            return AnthropicMessage(role: .user, content: .text(message.content ?? ""))
        case .user:
            return AnthropicMessage(role: .user, content: .text(message.content ?? ""))
        case .tool:
            return AnthropicMessage(role: .user, content: .blocks([
                .toolResult(toolUseId: message.toolCallId ?? "", content: message.content ?? "")
            ]))
        case .assistant:
            var blocks: [ContentBlock] = []
            if let content = message.content, !content.isEmpty {
                blocks.append(.text(content))
            }
            for toolCall in message.toolCalls ?? [] {
                blocks.append(.toolUse(
                    id: toolCall.id,
                    name: toolCall.name,
                    input: try decodeToolArguments(toolCall)
                ))
            }
            if blocks.isEmpty {
                return AnthropicMessage(role: .assistant, content: .text(""))
            }
            return AnthropicMessage(role: .assistant, content: .blocks(blocks))
        }
    }

    private func decodeToolArguments(_ toolCall: LLMToolCall) throws -> [String: JSONValue] {
        guard let data = toolCall.arguments.data(using: .utf8),
              let json = try? Foundation.JSONDecoder().decode([String: JSONValue].self, from: data) else {
            throw LLMError.invalidToolArguments(name: toolCall.name, arguments: toolCall.arguments)
        }
        return json
    }

    private func toLLMChatResult(_ response: AnthropicResponse) -> LLMChatResult {
        let text = response.content.compactMap { content -> String? in
            guard case .text(let text) = content else { return nil }
            return text
        }.joined()

        let reasoning = response.content.compactMap { content -> String? in
            guard case .thinking(let thinking, _) = content else { return nil }
            return thinking
        }.joined()

        let toolCalls = response.content.compactMap { content -> LLMToolCall? in
            guard case .toolUse(let id, let name, let input) = content else { return nil }
            let jsonInput = input.mapValues { JSONValue.fromAny($0) }
            let data = try? Foundation.JSONEncoder().encode(jsonInput)
            let arguments = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return LLMToolCall(id: id, name: name, arguments: arguments)
        }

        let assistantMessage = LLMChatMessage(
            role: .assistant,
            content: text.isEmpty ? nil : text,
            reasoningContent: reasoning.isEmpty ? nil : reasoning,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )

        return LLMChatResult(
            assistantMessage: assistantMessage,
            content: response.content,
            stopReason: response.stopReason,
            tokenUsage: tokenUsage(from: response.usage)
        )
    }

    private func tokenUsage(from usage: AnthropicResponse.Usage?) -> LLMTokenUsage? {
        guard let usage else { return nil }
        return LLMTokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheCreationInputTokens: usage.cacheCreationInputTokens ?? 0,
            cacheReadInputTokens: usage.cacheReadInputTokens ?? 0
        )
    }

    // MARK: - Response Content Building

    private func buildResponseContent(
        textBlocks: [Int: String],
        thinkingBlocks: [Int: (text: String, signature: String)],
        toolUseBlocks: [Int: (id: String, name: String, inputJSON: String)]
    ) -> [ResponseContentBlock] {
        let allIndices = Set(textBlocks.keys).union(thinkingBlocks.keys).union(toolUseBlocks.keys).sorted()
        return allIndices.map { idx -> ResponseContentBlock in
            if let thinking = thinkingBlocks[idx] {
                return .thinking(thinking.text, signature: thinking.signature)
            } else if let text = textBlocks[idx] {
                return .text(text)
            } else if let tool = toolUseBlocks[idx] {
                let inputData = Data(tool.inputJSON.utf8)
                let inputDict: [String: any Sendable]
                if let parsed = try? JSONSerialization.jsonObject(with: inputData) as? [String: any Sendable] {
                    inputDict = parsed
                } else {
                    inputDict = [:]
                }
                return .toolUse(id: tool.id, name: tool.name, input: inputDict)
            } else {
                return .text("")
            }
        }
    }
}

// MARK: - Streaming Event Types (SSE payloads)

private struct AnthropicStreamEvent: Decodable {
    let type: String
    let index: Int?
    let message: StreamMessage?
    let content_block: StreamContentBlock?
    let delta: StreamDelta?
    let usage: StreamUsage?
}

private struct StreamMessage: Decodable {
    let id: String?
    let role: String?
    let usage: StreamUsage?
}

private struct StreamContentBlock: Decodable {
    let type: String
    let id: String?
    let name: String?
    let text: String?
}

private struct StreamDelta: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let signature: String?
    let partial_json: String?
    let stop_reason: String?
}

private struct StreamUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}
