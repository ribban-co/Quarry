//
//  AnthropicTypes.swift
//  Quarry
//

import Foundation

// MARK: - JSONValue

enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByNilLiteral {
    init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Cache Control

struct CacheControl: Codable, Sendable {
    let type: String
    var ttl: String?

    static let ephemeral = CacheControl(type: "ephemeral")
    static let ephemeralLong = CacheControl(type: "ephemeral", ttl: "1h")

    enum CodingKeys: String, CodingKey {
        case type, ttl
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(ttl, forKey: .ttl)
    }
}

// MARK: - System Content Block

struct SystemContentBlock: Codable, Sendable {
    let type: String
    let text: String
    var cacheControl: CacheControl?

    init(text: String, cacheControl: CacheControl? = nil) {
        self.type = "text"
        self.text = text
        self.cacheControl = cacheControl
    }

    enum CodingKeys: String, CodingKey {
        case type, text
        case cacheControl = "cache_control"
    }
}

// MARK: - Tool Definition

struct AnthropicToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: [String: JSONValue]
    var cacheControl: CacheControl?

    init(name: String, description: String, inputSchema: [String: JSONValue], cacheControl: CacheControl? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.cacheControl = cacheControl
    }
}

extension AnthropicToolDefinition: Codable {
    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
        case cacheControl = "cache_control"
    }
}

// MARK: - Message

struct AnthropicMessage: Sendable {
    let role: Role
    let content: MessageContent

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    enum MessageContent: Sendable {
        case text(String)
        case blocks([ContentBlock])
    }
}

extension AnthropicMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case role, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(Role.self, forKey: .role)
        if let text = try? container.decode(String.self, forKey: .content) {
            content = .text(text)
        } else {
            let blocks = try container.decode([ContentBlock].self, forKey: .content)
            content = .blocks(blocks)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        switch content {
        case .text(let s):
            try container.encode(s, forKey: .content)
        case .blocks(let blocks):
            try container.encode(blocks, forKey: .content)
        }
    }
}

// MARK: - ContentBlock (request-side)

enum ContentBlock: Sendable {
    case text(String, cacheControl: CacheControl? = nil)
    case thinking(String, signature: String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(toolUseId: String, content: String, cacheControl: CacheControl? = nil)
}

extension ContentBlock: Codable {
    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, thinking, signature
        case toolUseId = "tool_use_id"
        case content
        case cacheControl = "cache_control"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            let cc = try container.decodeIfPresent(CacheControl.self, forKey: .cacheControl)
            self = .text(text, cacheControl: cc)
        case "thinking":
            let thinking = try container.decode(String.self, forKey: .thinking)
            let signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
            self = .thinking(thinking, signature: signature)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode([String: JSONValue].self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let content = try container.decode(String.self, forKey: .content)
            let cc = try container.decodeIfPresent(CacheControl.self, forKey: .cacheControl)
            self = .toolResult(toolUseId: toolUseId, content: content, cacheControl: cc)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content block type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text, let cacheControl):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
        case .thinking(let thinking, let signature):
            try container.encode("thinking", forKey: .type)
            try container.encode(thinking, forKey: .thinking)
            try container.encode(signature, forKey: .signature)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let cacheControl):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
        }
    }
}

// MARK: - ResponseContentBlock (response-side)

// @unchecked Sendable: [String: any Sendable] existential isn't statically Sendable.
// All values originate from JSONSerialization (NSString, NSNumber, etc.) which are all Sendable.
enum ResponseContentBlock: @unchecked Sendable {
    case text(String)
    case thinking(String, signature: String)
    case toolUse(id: String, name: String, input: [String: any Sendable])
}

extension ResponseContentBlock: Codable {
    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, thinking, signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "thinking":
            let thinking = try container.decode(String.self, forKey: .thinking)
            let signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
            self = .thinking(thinking, signature: signature)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let jsonInput = try container.decode([String: JSONValue].self, forKey: .input)
            let sendableInput: [String: any Sendable] = jsonInput.mapValues { $0.toSendable() }
            self = .toolUse(id: id, name: name, input: sendableInput)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown response block type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .thinking(let thinking, let signature):
            try container.encode("thinking", forKey: .type)
            try container.encode(thinking, forKey: .thinking)
            try container.encode(signature, forKey: .signature)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            let jsonInput = input.mapValues { JSONValue.fromAny($0) }
            try container.encode(jsonInput, forKey: .input)
        }
    }
}

// MARK: - Extended Thinking Config

enum ThinkingConfig: Sendable {
    case enabled(budgetTokens: Int = 10_000)
    case adaptive
}

extension ThinkingConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "adaptive":
            self = .adaptive
        default:
            let budget = try container.decode(Int.self, forKey: .budgetTokens)
            self = .enabled(budgetTokens: budget)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .enabled(let budgetTokens):
            try container.encode("enabled", forKey: .type)
            try container.encode(budgetTokens, forKey: .budgetTokens)
        case .adaptive:
            try container.encode("adaptive", forKey: .type)
        }
    }
}

// MARK: - Request/Response Bodies

struct AnthropicRequest: Codable, Sendable {
    let model: String
    let maxTokens: Int
    let system: [SystemContentBlock]
    let messages: [AnthropicMessage]
    let tools: [AnthropicToolDefinition]
    let thinking: ThinkingConfig?
    let stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system, messages, tools, thinking, stream
    }
}

struct AnthropicResponse: Codable, Sendable {
    let id: String
    let type: String
    let role: String
    let content: [ResponseContentBlock]
    let stopReason: String?
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content
        case stopReason = "stop_reason"
        case usage
    }

    struct Usage: Codable, Sendable {
        let inputTokens: Int
        let outputTokens: Int
        var cacheCreationInputTokens: Int?
        var cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}

// MARK: - JSONValue Conversion

extension JSONValue {
    func toSendable() -> any Sendable {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let arr): return arr.map { $0.toSendable() }
        case .object(let obj): return obj.mapValues { $0.toSendable() }
        }
    }

    static func fromAny(_ value: Any) -> JSONValue {
        switch value {
        case is NSNull: return .null
        case let b as Bool: return .bool(b)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let s as String: return .string(s)
        case let arr as [Any]: return .array(arr.map { fromAny($0) })
        case let dict as [String: Any]: return .object(dict.mapValues { fromAny($0) })
        default: return .string("\(value)")
        }
    }
}
