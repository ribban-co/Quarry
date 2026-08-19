import Foundation
import ConvexMobile

// MARK: - Convex Filter Builder (Scaffold)
// Produces a FilterExpression JSON for `_system/frontend/paginatedTableDocuments`.

extension ConvexDriver {
    nonisolated private func mapToConvexOperator(_ op: FilterOperator) -> String {
        switch op {
        case .equals: return "eq"          // built-in
        case .notEquals: return "neq"      // built-in
        case .greaterThan: return "gt"     // built-in
        case .greaterThanOrEquals: return "gte" // built-in
        case .lessThan: return "lt"        // built-in
        case .lessThanOrEquals: return "lte" // built-in
        case .isIn: return "anyOf"         // array filter
        case .isNull: return "type"        // type filter (value: "null")
        case .isNotNull: return "notype"    // type filter (value: "null")
        // The following are not specified in provided schema; we will fallback to eq for now.
        case .like: return "eq"
        case .ilike: return "eq"
        case .notLike: return "neq"
        case .startsWith: return "eq"
        case .endsWith: return "eq"
        }
    }

    /// Convert a user-entered string into a JSON-compatible primitive if possible (number/bool), else string.
    nonisolated private func toJSONPrimitive(from string: String) -> Any {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "true" { return true }
        if trimmed.lowercased() == "false" { return false }
        if let int64Value = Int64(trimmed) { return int64Value }
        if let doubleValue = Double(trimmed) { return doubleValue }
        return trimmed
    }

    /// Builds a FilterExpression dictionary:
    /// { clauses: Filter[], order?: "asc" | "desc", index?: ... }
    nonisolated func generateFilterPayload(from conditions: [FilterCondition]) -> [String: Any]? {
        let validConditions: [FilterCondition] = conditions.filter { condition in
            guard !condition.field.isEmpty else { return false }
            switch condition.filterOperator {
            case .isNull, .isNotNull:
                return true
            default:
                return !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        guard !validConditions.isEmpty else { return nil }

        // Convert each condition to a Filter (FilterByBuiltin | FilterByOr | FilterByType)
        let clauses: [[String: Any]] = validConditions.enumerated().map { index, condition in
            let opString = mapToConvexOperator(condition.filterOperator)
            var clause: [String: Any] = [
                "enabled": true,
                "op": opString,
                // Give each filter a stable id for easier client-side tracking
                "id": "filter_\(index)"
            ]
            // Most filters operate on a field; some index filters do not, but we don't emit index filters here
            clause["field"] = condition.field

            switch condition.filterOperator {
            case .isNull:
                clause["value"] = "null"
            case .isNotNull:
                clause["value"] = "null"
            case .isIn:
                let items: [Any] = condition.value
                    .split(separator: ",")
                    .map { toJSONPrimitive(from: String($0)) }
                clause["value"] = items
            default:
                clause["value"] = toJSONPrimitive(from: condition.value)
            }

            return clause
        }

        // Assemble FilterExpression. We omit order to let server default to "desc".
        let payload: [String: Any] = [
            "clauses": clauses
        ]

        return payload
    }

    /// Builds a JSON string representing the FilterExpression payload.
    nonisolated func generateFilterQuery(from conditions: [FilterCondition], tableName: String) -> String {
        guard let payload = generateFilterPayload(from: conditions) else { return "" }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes, .sortedKeys])
            if let jsonString = String(data: data, encoding: .utf8) {
                return jsonString
            }
        } catch {
            // Fall through and return empty string
        }
        return ""
    }

    /// Human-readable preview (not the real schema), for quick UI/debug.
    nonisolated func generateFilterPreviewString(from conditions: [FilterCondition], tableName: String) -> String {
        let validConditions: [FilterCondition] = conditions.filter { condition in
            guard !condition.field.isEmpty else { return false }
            switch condition.filterOperator {
            case .isNull, .isNotNull:
                return true
            default:
                return !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        guard !validConditions.isEmpty else { return "" }

        var parts: [String] = []
        for (index, c) in validConditions.enumerated() {
            let conj: String = index == 0 ? "where" : "and"
            let op = mapToConvexOperator(c.filterOperator)
            switch c.filterOperator {
            case .isNull:
                parts.append("\(conj) \(c.field) \(op)null")
            case .isNotNull:
                parts.append("\(conj) \(c.field) \(op) not null")
            case .isIn:
                let values = c.value
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .joined(separator: ", ")
                parts.append("\(conj) \(c.field) \(op) [\(values)]")
            default:
                parts.append("\(conj) \(c.field) \(op) '" + c.value.replacingOccurrences(of: "'", with: "\\'") + "'")
            }
        }

        return "convex \(tableName) " + parts.joined(separator: " ")
    }
}
