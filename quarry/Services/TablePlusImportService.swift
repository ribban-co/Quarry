import Foundation
import SwiftUI

/// A TablePlus connection parsed from its Connections.plist, ready to preview
/// and turn into a Quarry `Connection`.
struct TablePlusImportCandidate: Identifiable, Sendable {
    let id: String
    let name: String
    let groupName: String?
    let driverName: String
    let databaseType: DatabaseType?
    let host: String
    let port: String
    let username: String
    let database: String
    let environment: ConnectionEnvironment?
    let color: ConnectionColor
    let sqlitePath: String?

    let sshEnabled: Bool
    let sshHost: String
    let sshPort: String
    let sshUsername: String
    let sshUsesPrivateKey: Bool
    let sshPrivateKeyPath: String

    let unsupportedReason: String?

    var isSupported: Bool { unsupportedReason == nil && databaseType != nil }

    var displayDetail: String {
        if let sqlitePath, !sqlitePath.isEmpty {
            return sqlitePath
        }
        var detail = host.isEmpty ? "localhost" : host
        if !port.isEmpty { detail += ":\(port)" }
        if !database.isEmpty { detail += "/\(database)" }
        return detail
    }
}

enum TablePlusImportService {

    static var dataDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.tinyapp.TablePlus/Data", isDirectory: true)
    }

    static var isTablePlusDataAvailable: Bool {
        FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("Connections.plist").path)
    }

    // MARK: - Parsing

    static func loadCandidates() throws -> [TablePlusImportCandidate] {
        let connectionsURL = dataDirectory.appendingPathComponent("Connections.plist")
        let data = try Data(contentsOf: connectionsURL)
        guard let entries = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw DatabaseError.operationFailed("Could not read TablePlus connections file")
        }

        let groupNames = loadGroupNames()
        return entries.map { candidate(from: $0, groupNames: groupNames) }
    }

    private static func loadGroupNames() -> [String: String] {
        let groupsURL = dataDirectory.appendingPathComponent("ConnectionGroups.plist")
        guard let data = try? Data(contentsOf: groupsURL),
              let groups = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            return [:]
        }
        var names: [String: String] = [:]
        for group in groups {
            if let id = group["ID"] as? String, let name = group["Name"] as? String {
                names[id] = name
            }
        }
        return names
    }

    private static func candidate(from entry: [String: Any], groupNames: [String: String]) -> TablePlusImportCandidate {
        func string(_ key: String) -> String {
            (entry[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let driverName = string("Driver")
        let databaseType = mapDriver(driverName)
        let usesSocket = (entry["isUseSocket"] as? Bool) ?? false

        var unsupportedReason: String?
        if databaseType == nil {
            unsupportedReason = "\(driverName) is not supported in Quarry yet"
        } else if usesSocket {
            unsupportedReason = "Socket connections are not supported"
        }

        let host = string("DatabaseHost")
        let port = string("DatabasePort")

        return TablePlusImportCandidate(
            id: string("ID").isEmpty ? UUID().uuidString : string("ID"),
            name: string("ConnectionName").isEmpty ? "Untitled" : string("ConnectionName"),
            groupName: groupNames[string("GroupID")],
            driverName: driverName,
            databaseType: databaseType,
            host: host,
            port: port.isEmpty ? defaultPort(for: databaseType) : port,
            username: string("DatabaseUser"),
            database: string("DatabaseName"),
            environment: mapEnvironment(string("Enviroment")),
            color: mapColor(string("statusColor")),
            sqlitePath: databaseType == .sqlite ? string("DatabasePath") : nil,
            sshEnabled: (entry["isOverSSH"] as? Bool) ?? false,
            sshHost: string("ServerAddress"),
            sshPort: string("ServerPort"),
            sshUsername: string("ServerUser"),
            sshUsesPrivateKey: (entry["isUsePrivateKey"] as? Bool) ?? false,
            sshPrivateKeyPath: string("ServerPrivateKeyName"),
            unsupportedReason: unsupportedReason
        )
    }

    private static func mapDriver(_ driver: String) -> DatabaseType? {
        switch driver.lowercased() {
        case "postgresql", "cockroachdb":
            return .postgres
        case "mysql", "mariadb":
            return .mysql
        case "sqlite":
            return .sqlite
        case "mongodb":
            return .mongodb
        case "redis":
            return .redis
        default:
            return nil
        }
    }

    private static func defaultPort(for databaseType: DatabaseType?) -> String {
        switch databaseType {
        case .postgres, .supabase, .convex:
            return "5432"
        case .mysql:
            return "3306"
        case .mongodb:
            return "27017"
        case .redis:
            return "6379"
        case .sqlite, nil:
            return ""
        }
    }

    private static func mapEnvironment(_ value: String) -> ConnectionEnvironment? {
        ConnectionEnvironment.allCases.first { $0.rawValue.lowercased() == value.lowercased() }
    }

    /// TablePlus stores a pastel hex; pick the nearest Quarry palette color, and
    /// fall back to dark gray for the near-white "no color" default.
    private static func mapColor(_ hex: String) -> ConnectionColor {
        guard hex.count == 7, hex.hasPrefix("#"),
              let value = UInt32(hex.dropFirst(), radix: 16) else {
            return .darkGray
        }
        let r = Double((value >> 16) & 0xFF)
        let g = Double((value >> 8) & 0xFF)
        let b = Double(value & 0xFF)

        let maxChannel = max(r, g, b)
        let saturation = maxChannel == 0 ? 0 : (maxChannel - min(r, g, b)) / maxChannel
        guard saturation > 0.12 else { return .darkGray }

        var best: (color: ConnectionColor, distance: Double) = (.darkGray, .greatestFiniteMagnitude)
        for candidate in ConnectionColor.allCases {
            let resolved = NSColor(candidate.color).usingColorSpace(.sRGB) ?? .gray
            let distance = pow(Double(resolved.redComponent) * 255 - r, 2)
                + pow(Double(resolved.greenComponent) * 255 - g, 2)
                + pow(Double(resolved.blueComponent) * 255 - b, 2)
            if distance < best.distance {
                best = (candidate, distance)
            }
        }
        return best.color
    }

    // MARK: - Import

    @MainActor
    static func makeConnection(from candidate: TablePlusImportCandidate) -> Connection? {
        guard let databaseType = candidate.databaseType, candidate.isSupported else { return nil }

        let connection: Connection
        if databaseType == .sqlite {
            connection = Connection(
                databaseType: .sqlite,
                url: sqliteURL(for: candidate.sqlitePath),
                name: candidate.name,
                color: candidate.color,
                environment: candidate.environment ?? .local
            )
        } else {
            connection = Connection(
                databaseType: databaseType,
                name: candidate.name,
                color: candidate.color,
                environment: candidate.environment,
                hostname: candidate.host.isEmpty ? "localhost" : candidate.host,
                port: candidate.port,
                username: candidate.username,
                database: candidate.database.isEmpty ? nil : candidate.database,
                sslMode: databaseType == .postgres ? "prefer" : nil
            )
        }

        if candidate.sshEnabled, !candidate.sshHost.isEmpty {
            connection.sshEnabled = true
            connection.sshHost = candidate.sshHost
            connection.sshPort = candidate.sshPort.isEmpty ? nil : candidate.sshPort
            connection.sshUsername = candidate.sshUsername
            if candidate.sshUsesPrivateKey {
                connection.sshAuthMethod = .privateKey
                if candidate.sshPrivateKeyPath.contains("/") {
                    connection.sshPrivateKeyPath = candidate.sshPrivateKeyPath
                }
            }
        }

        return connection
    }

    /// SQLite connections need a security-scoped bookmark to open; create one
    /// from the TablePlus path so the import is connectable right away.
    private static func sqliteURL(for path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        let fileURL = URL(fileURLWithPath: path)
        if let bookmarkData = try? BookmarkManager.shared.createBookmark(from: fileURL) {
            return BookmarkManager.shared.encodeBookmark(bookmarkData, withPath: path)
        }
        return "file:\(path)"
    }
}
