import Foundation

// MARK: - Filter Models
enum FilterConjunction: String, CaseIterable {
    case whereClause = "where"
    case and = "and"
    case or = "or"
}

enum FilterOperator: String, CaseIterable {
    case equals = "equals"
    case notEquals = "not equals"
    case startsWith = "starts with"
    case endsWith = "ends with"
    case greaterThan = "greater than"
    case greaterThanOrEquals = "greater or equals"
    case lessThan = "less than"
    case lessThanOrEquals = "less than or equals"
    case like = "like"
    case ilike = "ilike"
    case notLike = "not like"
    case isIn = "in"
    case isNull = "is null"
    case isNotNull = "is not null"
}

struct FilterCondition: Equatable {
    let id = UUID()
    var conjunction: FilterConjunction
    var field: String
    var filterOperator: FilterOperator
    var value: String
}

// MARK: - PostgreSQL Filter Builder Extension
extension PostgreSQLDriver {
    
    /// Generates a complete PostgreSQL SELECT query from filter conditions
    /// - Parameters:
    ///   - conditions: Array of filter conditions
    ///   - tableName: Name of the table to query
    /// - Returns: Complete SQL query string
    nonisolated func generateFilterQuery(from conditions: [FilterCondition], tableName: String, databaseSchema: String? = "public") -> String {
        let validConditions = conditions.filter { condition in
            !condition.field.isEmpty && !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        
        guard !validConditions.isEmpty else { return "" }
        
        var sql = "SELECT * FROM \(quoteIdentifier(tableName)) "

        if let schema = databaseSchema {
            sql = "SELECT * FROM \(quoteIdentifier(schema)).\(quoteIdentifier(tableName)) "
        }

        for (index, condition) in validConditions.enumerated() {
            if index == 0 {
                sql += "WHERE "
            } else {
                sql += " \(condition.conjunction.rawValue.uppercased()) "
            }

            let escapedField = quoteIdentifier(condition.field)
            let escapedValue = "'\(condition.value.replacingOccurrences(of: "'", with: "''"))'"
            
            switch condition.filterOperator {
            case .equals:
                sql += "\(escapedField) = \(escapedValue)"
            case .notEquals:
                sql += "\(escapedField) != \(escapedValue)"
            case .startsWith:
                sql += "\(escapedField) ILIKE '\(condition.value.replacingOccurrences(of: "'", with: "''"))%'"
            case .endsWith:
                sql += "\(escapedField) ILIKE '%\(condition.value.replacingOccurrences(of: "'", with: "''"))'"
            case .greaterThan:
                sql += "\(escapedField) > \(escapedValue)"
            case .greaterThanOrEquals:
                sql += "\(escapedField) >= \(escapedValue)"
            case .lessThan:
                sql += "\(escapedField) < \(escapedValue)"
            case .lessThanOrEquals:
                sql += "\(escapedField) <= \(escapedValue)"
            case .like:
                sql += "\(escapedField) LIKE \(escapedValue)"
            case .ilike:
                sql += "\(escapedField) ILIKE \(escapedValue)"
            case .notLike:
                sql += "\(escapedField) NOT LIKE \(escapedValue)"
            case .isIn:
                // For IN operator, value should be comma-separated list: "1,2,3"
                let inValues = condition.value.split(separator: ",").map { "'\($0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ", ")
                sql += "\(escapedField) IN (\(inValues))"
            case .isNull:
                sql += "\(escapedField) IS NULL"
            case .isNotNull:
                sql += "\(escapedField) IS NOT NULL"
            }
        }
        
        return sql
    }
}
