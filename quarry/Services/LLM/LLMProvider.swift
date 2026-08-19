//
//  LLMProvider.swift
//  Quarry
//

import Foundation

/// Which vendor a request is routed to. Quarry is BYOK — every request uses the
/// user's own key, and there is no Quarry-hosted inference.
enum LLMProviderKind: String, CaseIterable, Sendable, Codable {
    case anthropic
    case openAI

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        }
    }

    /// Where the user creates a key, surfaced in Settings.
    var consoleURL: URL {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        }
    }

    /// Shown as a hint next to the key field so a wrong key is obvious early.
    var keyPrefix: String {
        switch self {
        case .anthropic: "sk-ant-"
        case .openAI: "sk-"
        }
    }

    /// Curated starting points. The user can type any model id instead, and
    /// Settings can replace these with a live list from the provider.
    var suggestedModels: [String] {
        switch self {
        case .anthropic:
            ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]
        case .openAI:
            ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        }
    }

    var defaultModel: String {
        suggestedModels[0]
    }
}

enum LLMError: LocalizedError {
    case missingAPIKey(LLMProviderKind)
    case invalidResponse
    case missingMessage
    case httpError(statusCode: Int, body: String)
    case invalidToolArguments(name: String, arguments: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "No \(provider.displayName) API key configured. Add one in Settings → AI."
        case .invalidResponse:
            "The model returned an invalid response."
        case .missingMessage:
            "The model returned no assistant message."
        case .httpError(let statusCode, let body):
            "Request failed with HTTP \(statusCode): \(body)"
        case .invalidToolArguments(let name, let arguments):
            "The model returned invalid arguments for \(name): \(arguments)"
        }
    }
}

// MARK: - Neutral wire types

struct LLMToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: [String: JSONValue]
}

struct LLMToolCall: Sendable {
    let id: String
    let name: String
    /// Raw JSON string, parsed by the caller.
    let arguments: String
}

enum LLMThinkingMode: String, Sendable {
    case enabled
    case disabled
}

struct LLMChatMessage: Sendable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    var content: String?
    var reasoningContent: String?
    var toolCalls: [LLMToolCall]?
    var toolCallId: String?
    var name: String?
}

struct LLMChatResult: Sendable {
    let assistantMessage: LLMChatMessage
    let content: [ResponseContentBlock]
    var stopReason: String? = nil
    var tokenUsage: LLMTokenUsage? = nil
}

struct LLMTokenUsage: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }
}

// MARK: - Provider

/// A vendor-specific backend. Both implementations speak the neutral types
/// above so callers never branch on which provider is active.
protocol LLMProvider: Sendable {
    var kind: LLMProviderKind { get }

    func chatCompletion(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        tools: [LLMToolDefinition],
        maxTokens: Int,
        model: String,
        thinkingMode: LLMThinkingMode
    ) async throws -> LLMChatResult

    func chatCompletionStream(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        tools: [LLMToolDefinition],
        maxTokens: Int,
        model: String,
        thinkingMode: LLMThinkingMode,
        onTextDelta: @MainActor @Sendable (String) -> Void,
        onThinkingDelta: @MainActor @Sendable (String) -> Void
    ) async throws -> LLMChatResult
}

/// Entry point for all model calls. Resolves the user's configured provider and
/// forwards to it, so callers pass a model id and nothing else.
enum LLM {
    @MainActor
    static var activeProvider: any LLMProvider {
        switch LLMSettings.shared.provider {
        case .anthropic: AnthropicProvider.shared
        case .openAI: OpenAIProvider.shared
        }
    }

    @MainActor
    static var isConfigured: Bool {
        LLMSettings.shared.apiKey(for: LLMSettings.shared.provider)?.isEmpty == false
    }

    /// Settings live on the main actor; the request itself does not. Resolve
    /// both in one hop so callers can stay wherever they are.
    @MainActor
    private static func resolve(_ model: String?) -> (any LLMProvider, String) {
        (activeProvider, model ?? LLMSettings.shared.model)
    }

    static func chatCompletion(
        messages: [LLMChatMessage],
        systemPrompt: String? = nil,
        tools: [LLMToolDefinition] = [],
        maxTokens: Int = 16_000,
        model: String? = nil,
        thinkingMode: LLMThinkingMode = .enabled
    ) async throws -> LLMChatResult {
        let (provider, resolvedModel) = await resolve(model)
        return try await provider.chatCompletion(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            model: resolvedModel,
            thinkingMode: thinkingMode
        )
    }

    static func chatCompletionStream(
        messages: [LLMChatMessage],
        systemPrompt: String? = nil,
        tools: [LLMToolDefinition] = [],
        maxTokens: Int = 64_000,
        model: String? = nil,
        thinkingMode: LLMThinkingMode = .enabled,
        onTextDelta: @MainActor @Sendable (String) -> Void,
        onThinkingDelta: @MainActor @Sendable (String) -> Void = { _ in }
    ) async throws -> LLMChatResult {
        let (provider, resolvedModel) = await resolve(model)
        return try await provider.chatCompletionStream(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            model: resolvedModel,
            thinkingMode: thinkingMode,
            onTextDelta: onTextDelta,
            onThinkingDelta: onThinkingDelta
        )
    }
}
