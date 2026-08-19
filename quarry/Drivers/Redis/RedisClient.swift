import Foundation
import Network
import os

// MARK: - RESP Value

enum RedisValue: Sendable {
    case simpleString(String)
    case error(String)
    case integer(Int64)
    case bulkString(Data?)
    case array([RedisValue]?)

    var stringValue: String? {
        switch self {
        case .simpleString(let value):
            return value
        case .bulkString(let data):
            guard let data else { return nil }
            return String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        case .integer(let value):
            return String(value)
        case .error, .array:
            return nil
        }
    }

    var intValue: Int64? {
        switch self {
        case .integer(let value):
            return value
        case .simpleString(let value), .error(let value):
            return Int64(value)
        case .bulkString:
            return stringValue.flatMap { Int64($0) }
        case .array:
            return nil
        }
    }

    var arrayValue: [RedisValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var isNull: Bool {
        switch self {
        case .bulkString(nil), .array(nil):
            return true
        default:
            return false
        }
    }
}

// MARK: - RESP Parser

private struct RESPParser {
    var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// Attempts to parse one complete reply from the buffer, consuming it on success.
    mutating func parseReply() -> RedisValue? {
        var offset = buffer.startIndex
        guard let value = parse(at: &offset) else { return nil }
        buffer.removeSubrange(buffer.startIndex..<offset)
        return value
    }

    private func parse(at offset: inout Data.Index) -> RedisValue? {
        guard offset < buffer.endIndex else { return nil }
        let marker = buffer[offset]
        guard let line = readLine(after: offset) else { return nil }

        switch marker {
        case UInt8(ascii: "+"):
            offset = line.next
            return .simpleString(line.text)
        case UInt8(ascii: "-"):
            offset = line.next
            return .error(line.text)
        case UInt8(ascii: ":"):
            offset = line.next
            return .integer(Int64(line.text) ?? 0)
        case UInt8(ascii: "$"):
            guard let length = Int(line.text) else { return nil }
            if length < 0 {
                offset = line.next
                return .bulkString(nil)
            }
            let dataStart = line.next
            let dataEnd = buffer.index(dataStart, offsetBy: length + 2, limitedBy: buffer.endIndex)
            guard let dataEnd, dataEnd <= buffer.endIndex else { return nil }
            let payload = buffer.subdata(in: dataStart..<buffer.index(dataStart, offsetBy: length))
            offset = dataEnd
            return .bulkString(payload)
        case UInt8(ascii: "*"):
            guard let count = Int(line.text) else { return nil }
            if count < 0 {
                offset = line.next
                return .array(nil)
            }
            var elements: [RedisValue] = []
            elements.reserveCapacity(count)
            var cursor = line.next
            for _ in 0..<count {
                guard let element = parse(at: &cursor) else { return nil }
                elements.append(element)
            }
            offset = cursor
            return .array(elements)
        default:
            return nil
        }
    }

    /// Reads a CRLF-terminated line starting right after the type marker at `offset`.
    private func readLine(after offset: Data.Index) -> (text: String, next: Data.Index)? {
        let start = buffer.index(after: offset)
        var index = start
        while index < buffer.endIndex {
            if buffer[index] == UInt8(ascii: "\r"),
               buffer.index(after: index) < buffer.endIndex,
               buffer[buffer.index(after: index)] == UInt8(ascii: "\n") {
                let text = String(data: buffer.subdata(in: start..<index), encoding: .utf8) ?? ""
                return (text, buffer.index(index, offsetBy: 2))
            }
            index = buffer.index(after: index)
        }
        return nil
    }
}

// MARK: - Client

/// Minimal RESP2 client over Network.framework. Commands are serialized by the
/// actor; `pipeline` batches round-trips for per-key metadata fetches.
actor RedisClient {
    struct Endpoint: Sendable {
        let host: String
        let port: Int
        let username: String?
        let password: String?
        let database: Int
        let useTLS: Bool
    }

    private var connection: NWConnection?
    private var parser = RESPParser()
    private let endpoint: Endpoint

    init(endpoint: Endpoint) {
        self.endpoint = endpoint
    }

    func connect() async throws {
        disconnectSync()

        let parameters: NWParameters
        if endpoint.useTLS {
            parameters = NWParameters(tls: NWProtocolTLS.Options())
        } else {
            parameters = .tcp
        }

        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: endpoint.port)) else {
            throw DatabaseError.invalidConnectionString("Invalid Redis port \(endpoint.port)")
        }

        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            connection.stateUpdateHandler = { state in
                let shouldResume: (Result<Void, Error>)?
                switch state {
                case .ready:
                    shouldResume = .success(())
                case .failed(let error):
                    shouldResume = .failure(DatabaseError.connectionFailed("Could not connect to Redis at \(self.endpoint.host):\(self.endpoint.port)", details: error.localizedDescription))
                case .cancelled:
                    shouldResume = .failure(DatabaseError.connectionFailed("Redis connection cancelled"))
                default:
                    shouldResume = nil
                }
                if let shouldResume {
                    let first = resumed.withLock { (alreadyResumed: inout Bool) -> Bool in
                        if alreadyResumed { return false }
                        alreadyResumed = true
                        return true
                    }
                    if first {
                        continuation.resume(with: shouldResume)
                    }
                }
            }
            connection.start(queue: DispatchQueue(label: "quarry.redis.connection"))
        }
        connection.stateUpdateHandler = nil

        try await authenticateAndSelect()
    }

    private func authenticateAndSelect() async throws {
        if let password = endpoint.password, !password.isEmpty {
            let command: [String]
            if let username = endpoint.username, !username.isEmpty, username != "default" {
                command = ["AUTH", username, password]
            } else {
                command = ["AUTH", password]
            }
            let reply = try await send(command)
            if case .error(let message) = reply {
                throw DatabaseError.authenticationFailed(message)
            }
        }

        if endpoint.database != 0 {
            let reply = try await send(["SELECT", String(endpoint.database)])
            if case .error(let message) = reply {
                throw DatabaseError.operationFailed("Could not select database \(endpoint.database): \(message)")
            }
        }
    }

    func disconnect() {
        disconnectSync()
    }

    private func disconnectSync() {
        connection?.cancel()
        connection = nil
        parser = RESPParser()
    }

    var isConnected: Bool {
        connection?.state == .ready
    }

    // MARK: - Commands

    /// Sends one command and returns its reply. Redis errors are returned as
    /// `.error`, not thrown — callers decide which errors are fatal.
    func send(_ arguments: [String]) async throws -> RedisValue {
        let replies = try await pipeline([arguments])
        guard let reply = replies.first else {
            throw DatabaseError.operationFailed("Empty reply from Redis")
        }
        return reply
    }

    /// Sends one command and throws if Redis replies with an error.
    @discardableResult
    func command(_ arguments: [String]) async throws -> RedisValue {
        let reply = try await send(arguments)
        if case .error(let message) = reply {
            throw DatabaseError.operationFailed(message, query: arguments.joined(separator: " "))
        }
        return reply
    }

    /// Sends several commands in one write and reads one reply per command.
    func pipeline(_ commands: [[String]]) async throws -> [RedisValue] {
        guard let connection, connection.state == .ready else {
            throw DatabaseError.notConnected("Not connected to Redis")
        }
        guard !commands.isEmpty else { return [] }

        var payload = Data()
        for arguments in commands {
            payload.append(Self.encode(arguments))
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: DatabaseError.operationFailed("Redis send failed", details: error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }

        var replies: [RedisValue] = []
        replies.reserveCapacity(commands.count)
        while replies.count < commands.count {
            if let reply = parser.parseReply() {
                replies.append(reply)
                continue
            }
            let data = try await receiveChunk(on: connection)
            parser.append(data)
        }
        return replies
    }

    private func receiveChunk(on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: DatabaseError.operationFailed("Redis receive failed", details: error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: DatabaseError.notConnected("Redis closed the connection"))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private static func encode(_ arguments: [String]) -> Data {
        var data = Data()
        data.append("*\(arguments.count)\r\n".data(using: .utf8)!)
        for argument in arguments {
            let bytes = Data(argument.utf8)
            data.append("$\(bytes.count)\r\n".data(using: .utf8)!)
            data.append(bytes)
            data.append("\r\n".data(using: .utf8)!)
        }
        return data
    }
}
