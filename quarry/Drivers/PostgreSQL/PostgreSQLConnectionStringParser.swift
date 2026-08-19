//
//  PostgreSQLConnectionStringParser.swift
//  Quarry
//
//  Created by Fauzaan on 9/20/25.
//

import Foundation
import PostgresNIO
import NIOSSL

/// Parsed representation of a PostgreSQL connection string.
/// This mirrors the behavior of the popular `pg-connection-string` package,
/// adapted for Swift.
public struct PostgreSQLParsedConfig: Equatable {
    public struct SSLConfig: Equatable {
        /// Whether TLS is enabled or disabled (optional because other fields might imply TLS)
        public var enabled: Bool?
        /// If provided, sets certificate verification requirement
        public var rejectUnauthorized: Bool?
        /// PEM contents of client certificate
        public var cert: String?
        /// PEM contents of client private key
        public var key: String?
        /// PEM contents of root CA
        public var ca: String?
        /// Raw sslmode value (disable, prefer, require, verify-ca, verify-full, no-verify)
        public var mode: String?
        public var tunneled: Bool?
        public var tlsServerName: String?
    }

    public var host: String?
    public var port: Int?
    public var user: String?
    public var password: String?
    public var database: String?
    public var clientEncoding: String?
    public var ssl: SSLConfig?
}

public enum PostgreSQLConnectionStringParserError: Error, LocalizedError {
    case invalidURL
    case invalidHost

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid PostgreSQL connection string"
        case .invalidHost: return "Invalid PostgreSQL connection string: host is missing"
        }
    }
}

/// Options that influence parsing semantics
public struct PostgreSQLParseOptions: Equatable {
    /// If true, map `sslmode` according to libpq semantics, similar to `uselibpqcompat`
    public var useLibpqCompat: Bool

    public init(useLibpqCompat: Bool = false) {
        self.useLibpqCompat = useLibpqCompat
    }
}

public enum PostgreSQLConnectionStringParser {
    /// Parse a PostgreSQL connection string into a structured `PostgreSQLParsedConfig`.
    public static func parse(_ input: String, options: PostgreSQLParseOptions = .init()) throws -> PostgreSQLParsedConfig {
        // 1) Unix socket short form: "/path/to/socket dbname"
        if let first = input.first, first == "/" {
            let parts = input.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let host = String(parts.first ?? Substring(""))
            let database = parts.count > 1 ? String(parts[1]) : nil
            return PostgreSQLParsedConfig(host: host, port: nil, user: nil, password: nil, database: database, clientEncoding: nil, ssl: nil)
        }

        // 2) Normalize and handle spaces/percent-encoding similar to encodeURI
        var str = input
        if str.contains(" ") { // Only replace spaces to %20; leave existing %xx sequences intact
            str = str.replacingOccurrences(of: " ", with: "%20")
        }

        // 3) Ensure a scheme for URL parsing. If missing, prefix with postgres://
        if !str.contains("://") {
            str = "postgres://" + str
        }

        // 4) Try regular parse first, fallback to dummy host trick for '@/'
        var usedDummyHost = false
        var url: URL
        if let u = URL(string: str) {
            url = u
        } else {
            let replaced = str.replacingOccurrences(of: "@/", with: "@___DUMMY___/")
            guard let u = URL(string: replaced) else { throw PostgreSQLConnectionStringParserError.invalidURL }
            url = u
            usedDummyHost = true
        }

        // Build result config
        var config = PostgreSQLParsedConfig()

        // Query params first (searchParams)
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let items = comps.queryItems {
                for item in items {
                    // Favor later values if keys repeat
                    setQueryParam(item, into: &config)
                }
            }
        }

        // User/Password (only if not set by query params)
        // URLComponents.user and .password automatically decode percent-encoded values (Vapor approach)
        if (config.user == nil || config.password == nil),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            if config.user == nil { config.user = comps.user }
            if config.password == nil { config.password = comps.password }
        }

        // Socket protocol handling (scheme == socket)
        if (url.scheme?.lowercased() == "socket") {
            config.host = url.path.removingPercentEncoding
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                config.database = comps.queryItems?.first(where: { $0.name == "db" })?.value
                config.clientEncoding = comps.queryItems?.first(where: { $0.name == "encoding" })?.value
            }
            return postProcessSSL(in: config, options: options)
        }

        // Host and port
        let hostname = usedDummyHost ? "" : (url.host ?? "")
        if config.host == nil {
            config.host = hostname.removingPercentEncoding
        } else if !hostname.isEmpty, hostname.lowercased().hasPrefix("%2f") {
            // Prepend hostname to pathname if hostname is an URL-encoded Unix socket host
            if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let existingPath = comps.path
                comps.path = hostname + existingPath
                if let rebuilt = comps.url { url = rebuilt }
            }
        }
        if config.port == nil {
            if let portStr = url.port.map({ String($0) }), let port = Int(portStr) {
                config.port = port
            }
        }

        // Database from pathname
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        config.database = path.isEmpty ? nil : path.removingPercentEncoding

        // SSL values coercion similar to JS version
        config = postProcessSSL(in: config, options: options)
        return config
    }

    /// Parse a PostgreSQL connection string directly into PostgresNIO configuration
    public static func parseConfiguration(_ input: String, options: PostgreSQLParseOptions = .init()) throws -> PostgresConnection.Configuration {
        let parsed = try parse(input, options: options)

        guard let host = (parsed.host?.isEmpty == false ? parsed.host : nil) else {
            throw PostgreSQLConnectionStringParserError.invalidHost
        }

        let port = parsed.port ?? 5432
        let username = (parsed.user?.isEmpty == false ? parsed.user : nil) ?? "postgres"
        let password = (parsed.password?.isEmpty == false ? parsed.password : nil)
        let database = (parsed.database?.isEmpty == false ? parsed.database : nil) ?? ""

        // TLS mapping
        var tls: PostgresConnection.Configuration.TLS = .disable

        if let ssl = parsed.ssl {
            // Determine if TLS should be enabled
            var enableTLS = ssl.enabled ?? (ssl.mode?.lowercased() != "disable")

            // Local endpoints default to plaintext, but an explicit ssl mode wins --
            // e.g. a port-forward to an RDS instance with rds.force_ssl enabled.
            if isLocalEndpoint(host), ssl.tunneled != true, ssl.mode == nil, ssl.enabled == nil {
                enableTLS = false
            }

            if enableTLS {
                var tlsConfig = TLSConfiguration.makeClientConfiguration()

                if let mode = ssl.mode?.lowercased() {
                    switch mode {
                    case "disable":
                        enableTLS = false
                    case "prefer":
                        tlsConfig.certificateVerification = .none
                    case "require":
                        tlsConfig.certificateVerification = (ssl.ca == nil || ssl.rejectUnauthorized == false) ? .none : .noHostnameVerification
                    case "verify-ca":
                        tlsConfig.certificateVerification = .noHostnameVerification
                    case "verify-full":
                        tlsConfig.certificateVerification = .fullVerification
                    case "no-verify":
                        tlsConfig.certificateVerification = .none
                    default:
                        break
                    }
                } else if ssl.rejectUnauthorized == false {
                    tlsConfig.certificateVerification = .none
                }

                if enableTLS {
                    do {
                        try applySSLMaterials(from: ssl, to: &tlsConfig)
                        let context = try NIOSSLContext(configuration: tlsConfig)
                        if (ssl.mode?.lowercased() == "prefer") || (ssl.rejectUnauthorized == false) {
                            tls = .prefer(context)
                        } else {
                            tls = .require(context)
                        }
                    } catch {
                        throw error
                    }
                }
            }
        }

        var configuration = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: tls
        )
        configuration.options.tlsServerName = parsed.ssl?.tlsServerName
        return configuration
    }

    /// Parse a PostgreSQL connection string into PostgresClient.Configuration (connection pool)
    public static func parseClientConfiguration(_ input: String, options: PostgreSQLParseOptions = .init()) throws -> PostgresClient.Configuration {
        let parsed = try parse(input, options: options)

        guard let host = (parsed.host?.isEmpty == false ? parsed.host : nil) else {
            throw PostgreSQLConnectionStringParserError.invalidHost
        }

        let port = parsed.port ?? 5432
        let username = (parsed.user?.isEmpty == false ? parsed.user : nil) ?? "postgres"
        let password = (parsed.password?.isEmpty == false ? parsed.password : nil)
        let database = (parsed.database?.isEmpty == false ? parsed.database : nil) ?? ""

        var tls: PostgresClient.Configuration.TLS = .disable

        if let ssl = parsed.ssl {
            var enableTLS = ssl.enabled ?? (ssl.mode?.lowercased() != "disable")

            // Local endpoints default to plaintext, but an explicit ssl mode wins.
            if isLocalEndpoint(host), ssl.tunneled != true, ssl.mode == nil, ssl.enabled == nil {
                enableTLS = false
            }

            if enableTLS {
                var tlsConfig = TLSConfiguration.makeClientConfiguration()

                if let mode = ssl.mode?.lowercased() {
                    switch mode {
                    case "disable":
                        enableTLS = false
                    case "prefer":
                        tlsConfig.certificateVerification = .none
                    case "require":
                        tlsConfig.certificateVerification = (ssl.ca == nil || ssl.rejectUnauthorized == false) ? .none : .noHostnameVerification
                    case "verify-ca":
                        tlsConfig.certificateVerification = .noHostnameVerification
                    case "verify-full":
                        tlsConfig.certificateVerification = .fullVerification
                    case "no-verify":
                        tlsConfig.certificateVerification = .none
                    default:
                        break
                    }
                } else if ssl.rejectUnauthorized == false {
                    tlsConfig.certificateVerification = .none
                }

                if enableTLS {
                    try applySSLMaterials(from: ssl, to: &tlsConfig)
                    if (ssl.mode?.lowercased() == "prefer") || (ssl.rejectUnauthorized == false) {
                        tls = .prefer(tlsConfig)
                    } else {
                        tls = .require(tlsConfig)
                    }
                }
            }
        }

        var configuration = PostgresClient.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: tls
        )
        configuration.options.tlsServerName = parsed.ssl?.tlsServerName
        return configuration
    }

    // MARK: - Helpers

    private static func setQueryParam(_ item: URLQueryItem, into config: inout PostgreSQLParsedConfig) {
        guard let value = item.value else { return }
        switch item.name.lowercased() {
        case "host":
            config.host = value
        case "port":
            if let p = Int(value) { config.port = p }
        case "user":
            config.user = value
        case "password":
            config.password = value
        case "db", "database":
            config.database = value
        case "encoding", "client_encoding":
            config.clientEncoding = value
        case "ssl":
            var ssl = config.ssl ?? .init()
            if value == "true" || value == "1" { ssl.enabled = true }
            if value == "0" { ssl.enabled = false }
            config.ssl = ssl
        case "sslcert":
            var ssl = config.ssl ?? .init(); ssl.cert = readFileIfExists(value) ?? value; config.ssl = ssl
        case "sslkey":
            var ssl = config.ssl ?? .init(); ssl.key = readFileIfExists(value) ?? value; config.ssl = ssl
        case "sslrootcert":
            var ssl = config.ssl ?? .init(); ssl.ca = readFileIfExists(value) ?? value; config.ssl = ssl
        case "sslmode":
            var ssl = config.ssl ?? .init(); ssl.mode = value; config.ssl = ssl
        case "no-verify":
            var ssl = config.ssl ?? .init(); ssl.rejectUnauthorized = false; config.ssl = ssl
        case "quarry-ssh-tunnel", "pluk-ssh-tunnel":
            var ssl = config.ssl ?? .init()
            ssl.tunneled = value == "true" || value == "1"
            config.ssl = ssl
        case "quarry-tls-server-name", "pluk-tls-server-name":
            var ssl = config.ssl ?? .init()
            ssl.tlsServerName = value.isEmpty ? nil : value
            config.ssl = ssl
        case "uselibpqcompat":
            // handled later in postProcess
            break
        default:
            break
        }
    }

    private static func hasUnescapedWhitespaceOrBadPercents(_ s: String) -> Bool {
        // Rough equivalent of JS: / |%[^a-f0-9]|%[a-f0-9][^a-f0-9]/i
        if s.contains(" ") { return true }
        let scalars = Array(s.unicodeScalars)
        let hexScalars: Set<Unicode.Scalar> = Set("0123456789abcdefABCDEF".unicodeScalars)
        for i in 0..<scalars.count {
            if scalars[i] == "%" {
                if i + 2 >= scalars.count { return true }
                let a = scalars[i+1]; let b = scalars[i+2]
                if !hexScalars.contains(a) || !hexScalars.contains(b) { return true }
            }
        }
        return false
    }

    private static func isLocalEndpoint(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func encodeURICompat(_ s: String) -> String {
        // Encode spaces and leave valid %xx sequences intact
        // Simple approach: replace spaces with %20 and collapse %25NN -> %NN
        var encoded = s.replacingOccurrences(of: " ", with: "%20")
        // Replace %25NN with %NN
        let pattern = "%25([0-9A-Fa-f]{2})"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(encoded.startIndex..<encoded.endIndex, in: encoded)
            encoded = regex.stringByReplacingMatches(in: encoded, options: [], range: range, withTemplate: "%$1")
        }
        return encoded
    }

    private static func readFileIfExists(_ path: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        return nil
    }

    private static func applySSLMaterials(from ssl: PostgreSQLParsedConfig.SSLConfig, to tlsConfig: inout TLSConfiguration) throws {
        if let ca = ssl.ca, !ca.isEmpty {
            tlsConfig.trustRoots = .certificates(try NIOSSLCertificate.fromPEMBytes(Array(ca.utf8)))
        }

        if let cert = ssl.cert, !cert.isEmpty {
            let certificates = try NIOSSLCertificate.fromPEMBytes(Array(cert.utf8))
            tlsConfig.certificateChain = certificates.map { .certificate($0) }
        }

        if let key = ssl.key, !key.isEmpty {
            let emptyPassphrase: [UInt8] = []
            tlsConfig.privateKey = .privateKey(try NIOSSLPrivateKey(bytes: Array(key.utf8), format: .pem) { setter in
                setter(emptyPassphrase)
            })
        }
    }

    private static func postProcessSSL(in config: PostgreSQLParsedConfig, options: PostgreSQLParseOptions) -> PostgreSQLParsedConfig {
        var cfg = config
        // If any ssl* field exists and ssl is nil, create an object to hold options
        if var ssl = cfg.ssl {
            // Map sslmode semantics
            if options.useLibpqCompat || queryRequestedLibpqCompat(in: cfg) {
                switch ssl.mode?.lowercased() {
                case "disable":
                    ssl.enabled = false
                case "prefer":
                    // libpq semantics: attempt non-TLS first; we represent as enabled=false but keep rejectUnauthorized false
                    ssl.enabled = nil
                    ssl.rejectUnauthorized = false
                case "require":
                    if ssl.ca != nil {
                        // Treat like verify-ca (no hostname check)
                        // Represented by leaving rejectUnauthorized true but not enforcing hostname; we do not model hostname here
                    } else {
                        ssl.rejectUnauthorized = false
                    }
                    ssl.enabled = true
                case "verify-ca":
                    // Requires CA; if missing, the caller should validate
                    ssl.enabled = true
                case "verify-full":
                    ssl.enabled = true
                default:
                    break
                }
            } else {
                switch ssl.mode?.lowercased() {
                case "disable":
                    ssl.enabled = false
                case "prefer", "require", "verify-ca", "verify-full":
                    // Keep enabled as-is; warn behavior differences are handled upstream
                    break
                case "no-verify":
                    ssl.rejectUnauthorized = false
                    ssl.enabled = true
                default:
                    break
                }
            }
            cfg.ssl = ssl
        }
        return cfg
    }

    private static func queryRequestedLibpqCompat(in config: PostgreSQLParsedConfig) -> Bool {
        // We do not keep the raw query map, so infer by mode only (callers can pass options)
        return false
    }
}
