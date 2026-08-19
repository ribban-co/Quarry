//
//  ConnectionURLParser.swift
//  Quarry
//
//  URL parsing logic based on Vapor's MySQLKit and PostgresKit implementations.
//  Uses URLComponents which automatically handles percent-decoding of credentials.
//

import Foundation

enum ConnectionURLParserError: Error, LocalizedError {
    case invalidURL
    case missingScheme
    case unsupportedScheme(String)
    case missingHost
    case missingUsername
    case invalidSSLMode(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid connection URL format"
        case .missingScheme:
            return "Connection URL must include a scheme (e.g., mysql://, postgresql://)"
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme)"
        case .missingHost:
            return "Connection URL must include a hostname"
        case .missingUsername:
            return "Connection URL must include a username"
        case .invalidSSLMode(let mode):
            return "Invalid SSL mode: \(mode)"
        }
    }
}

struct ParsedConnectionURL {
    let scheme: String
    let hostname: String
    let port: Int
    let username: String
    let password: String?
    let database: String?
    let sslMode: SSLMode
    let isUnixSocket: Bool
    let unixSocketPath: String?

    enum SSLMode: String {
        case disable
        case allow
        case prefer
        case require
        case verifyCa = "verify-ca"
        case verifyFull = "verify-full"

        var postgresValue: String {
            rawValue
        }

        var mysqlValue: String {
            switch self {
            case .disable: return "DISABLED"
            case .allow, .prefer: return "PREFERRED"
            case .require, .verifyCa, .verifyFull: return "REQUIRED"
            }
        }
    }
}

struct ConnectionURLParser {

    // MARK: - MySQL Parsing (based on vapor/mysql-kit)

    static func parseMySQL(_ urlString: String) throws -> ParsedConnectionURL {
        guard let url = URL(string: urlString) else {
            throw ConnectionURLParserError.invalidURL
        }
        return try parseMySQL(url)
    }

    static func parseMySQL(_ url: URL) throws -> ParsedConnectionURL {
        guard let comp = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw ConnectionURLParserError.invalidURL
        }

        // URLComponents.user and .password automatically decode percent-encoded values
        guard let username = comp.user else {
            throw ConnectionURLParserError.missingUsername
        }

        let scheme = comp.scheme?.lowercased() ?? "mysql"

        switch scheme {
        case "mysql", "mysql+tcp":
            guard let hostname = comp.host, !hostname.isEmpty else {
                throw ConnectionURLParserError.missingHost
            }

            let sslMode = try parseSSLMode(
                from: comp.queryItems ?? [],
                defaultMode: "require"
            )

            let database = extractDatabase(from: url)

            return ParsedConnectionURL(
                scheme: "mysql",
                hostname: hostname,
                port: comp.port ?? 3306,
                username: username,
                password: comp.password,
                database: database,
                sslMode: sslMode,
                isUnixSocket: false,
                unixSocketPath: nil
            )

        case "mysql+uds":
            // Unix domain socket
            guard (comp.host?.isEmpty ?? true || comp.host == "localhost"),
                  comp.port == nil,
                  !comp.path.isEmpty,
                  comp.path != "/" else {
                throw ConnectionURLParserError.invalidURL
            }

            let sslMode = try parseSSLMode(
                from: comp.queryItems ?? [],
                defaultMode: "disable"
            )

            return ParsedConnectionURL(
                scheme: "mysql",
                hostname: "localhost",
                port: 3306,
                username: username,
                password: comp.password,
                database: comp.fragment,
                sslMode: sslMode,
                isUnixSocket: true,
                unixSocketPath: comp.path
            )

        default:
            throw ConnectionURLParserError.unsupportedScheme(scheme)
        }
    }

    // MARK: - Helpers

    private static func parseSSLMode(
        from queryItems: [URLQueryItem],
        defaultMode: String
    ) throws -> ParsedConnectionURL.SSLMode {
        let sslKeys = ["ssl-mode", "sslmode", "tls-mode", "tlsmode", "ssl", "tls"]

        let modeString = queryItems
            .last { sslKeys.contains($0.name.lowercased()) }?
            .value ?? defaultMode

        switch modeString.lowercased() {
        case "disable", "disabled", "false":
            return .disable
        case "allow":
            return .allow
        case "prefer", "preferred", "true":
            return .prefer
        case "require", "required":
            return .require
        case "verify-ca", "verify_ca":
            return .verifyCa
        case "verify-full", "verify_full", "verify-identity":
            return .verifyFull
        default:
            throw ConnectionURLParserError.invalidSSLMode(modeString)
        }
    }

    private static func extractDatabase(from url: URL) -> String? {
        let path = url.lastPathComponent
        guard !path.isEmpty, path != "/" else {
            return nil
        }
        return path
    }
}
