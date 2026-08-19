//
//  QueryAlertPolicy.swift
//  Quarry
//

import Foundation

/// Decides whether a query needs user confirmation before it is sent to the server,
/// based on the `QueryAlertMode` setting.
enum QueryAlertPolicy {
    static var currentMode: QueryAlertMode {
        guard let raw = UserDefaults.standard.string(forKey: QueryAlertMode.storageKey),
              let mode = QueryAlertMode(rawValue: raw) else {
            return .default
        }
        return mode
    }

    /// Returns a confirmation request when the query must be approved first, or `nil`
    /// when it may run immediately.
    @MainActor
    static func confirmationRequest(
        for query: String,
        connection: Connection,
        mode: QueryAlertMode = currentMode
    ) -> QueryConfirmationRequest? {
        guard mode != .silent else { return nil }

        let readOnly = isReadOnly(query)
        guard !(mode.allowsReadOnlyQueries && readOnly) else { return nil }

        // Safe mode can only verify when a password is actually stored for the
        // connection; otherwise it degrades to a plain warning.
        let storedPassword = mode.requiresPassword ? connection.password : nil
        let verifyPassword: ((String) -> Bool)?
        if let storedPassword, !storedPassword.isEmpty {
            verifyPassword = { $0 == storedPassword }
        } else {
            verifyPassword = nil
        }

        return QueryConfirmationRequest(
            query: query,
            mode: mode,
            connectionName: connection.name,
            isReadOnly: readOnly,
            verifyPassword: verifyPassword
        )
    }

    // MARK: - Read-only detection

    /// A query counts as read-only when every statement in it starts with a read-only
    /// keyword and contains no write keyword anywhere. Deliberately conservative:
    /// anything ambiguous is treated as a write.
    static func isReadOnly(_ query: String) -> Bool {
        let statements = statements(in: stripLiteralsAndComments(query))
        guard !statements.isEmpty else { return true }
        return statements.allSatisfy(isReadOnlyStatement)
    }

    private static let readOnlyPrefixes = ["SELECT", "WITH", "EXPLAIN", "SHOW", "DESCRIBE", "DESC", "TABLE", "VALUES"]

    private static let writeKeywordRegex = try? NSRegularExpression(
        pattern: #"\b(INSERT|UPDATE|DELETE|MERGE|UPSERT|REPLACE|DROP|CREATE|ALTER|TRUNCATE|RENAME|GRANT|REVOKE|COMMENT|INTO|CALL|EXEC|EXECUTE|SET|COPY|LOAD|IMPORT|VACUUM|REINDEX|CLUSTER|REFRESH|LOCK|ATTACH|DETACH|PRAGMA|BEGIN|START|COMMIT|ROLLBACK|SAVEPOINT|PREPARE|DEALLOCATE|DO|HANDLER|FLUSH|RESET|KILL|SHUTDOWN)\b"#,
        options: [.caseInsensitive]
    )

    private static func isReadOnlyStatement(_ statement: String) -> Bool {
        // Leading parens are legal for `(SELECT ...) UNION (SELECT ...)`.
        let trimmed = statement.drop { $0 == "(" || $0.isWhitespace }
        guard let firstWord = trimmed.split(whereSeparator: { !$0.isLetter }).first else { return false }
        guard readOnlyPrefixes.contains(firstWord.uppercased()) else { return false }

        guard let writeKeywordRegex else { return false }
        let range = NSRange(statement.startIndex..., in: statement)
        return writeKeywordRegex.firstMatch(in: statement, options: [], range: range) == nil
    }

    private static func statements(in query: String) -> [String] {
        query
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Replaces string literals, quoted identifiers and comments with spaces so that
    /// keyword and statement-separator scanning only sees actual SQL.
    private static func stripLiteralsAndComments(_ query: String) -> String {
        var result = ""
        result.reserveCapacity(query.count)

        var index = query.startIndex
        while index < query.endIndex {
            let char = query[index]
            let next = query.index(after: index) < query.endIndex ? query[query.index(after: index)] : nil

            switch char {
            case "'", "\"", "`":
                index = skipQuoted(query, from: index, delimiter: char)
                result.append(" ")
            case "-" where next == "-", "#":
                index = skipToLineEnd(query, from: index)
                result.append(" ")
            case "/" where next == "*":
                index = skipBlockComment(query, from: index)
                result.append(" ")
            default:
                result.append(char)
                index = query.index(after: index)
            }
        }

        return result
    }

    private static func skipQuoted(_ query: String, from start: String.Index, delimiter: Character) -> String.Index {
        var index = query.index(after: start)
        while index < query.endIndex {
            let char = query[index]
            if char == "\\" {
                // Backslash escape (MySQL); skip the escaped character.
                index = query.index(index, offsetBy: 2, limitedBy: query.endIndex) ?? query.endIndex
                continue
            }
            if char == delimiter {
                let next = query.index(after: index)
                // A doubled delimiter is an escaped delimiter, not a terminator.
                if next < query.endIndex, query[next] == delimiter {
                    index = query.index(after: next)
                    continue
                }
                return next
            }
            index = query.index(after: index)
        }
        return query.endIndex
    }

    private static func skipToLineEnd(_ query: String, from start: String.Index) -> String.Index {
        var index = start
        while index < query.endIndex, !query[index].isNewline {
            index = query.index(after: index)
        }
        return index
    }

    private static func skipBlockComment(_ query: String, from start: String.Index) -> String.Index {
        var index = query.index(start, offsetBy: 2, limitedBy: query.endIndex) ?? query.endIndex
        while index < query.endIndex {
            if query[index] == "*", query.index(after: index) < query.endIndex,
               query[query.index(after: index)] == "/" {
                return query.index(index, offsetBy: 2, limitedBy: query.endIndex) ?? query.endIndex
            }
            index = query.index(after: index)
        }
        return query.endIndex
    }
}
