//
//  MySQLFilterBuilder.swift
//  Quarry
//
//  Created by Fauzaan on 21/8/25.
//

import Foundation


// MARK: - MySQL Filter Builder Extension
extension MySQLDriver {
    /// Generates a complete MySQL SELECT query from filter conditions
    /// - Parameters:
    ///   - conditions: Array of filter conditions
    ///   - tableName: Name of the table to query
    /// - Returns: Complete SQL query string
    nonisolated func generateFilterQuery(from conditions: [FilterCondition], tableName: String) -> String {
        let validConditions = conditions.filter { condition in
            !condition.field.isEmpty && 
            (condition.filterOperator == .isNull || condition.filterOperator == .isNotNull || 
             !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        
        guard !validConditions.isEmpty else { return "" }
        
        var sql = "SELECT * FROM \(quoteIdentifier(tableName)) "
        
        for (index, condition) in validConditions.enumerated() {
            if index == 0 {
                sql += "WHERE "
            } else {
                sql += " \(condition.conjunction.rawValue.uppercased()) "
            }
            
            let escapedField = quoteIdentifier(condition.field)
            let escapedValue = "'\(condition.value.replacingOccurrences(of: "'", with: "\\'"))'"

            switch condition.filterOperator {
            case .equals:
                sql += "\(escapedField) = \(escapedValue)"
            case .notEquals:
                sql += "\(escapedField) != \(escapedValue)"
            case .startsWith:
                sql += "\(escapedField) LIKE '\(condition.value.replacingOccurrences(of: "'", with: "\\'"))%'"
            case .endsWith:
                sql += "\(escapedField) LIKE '%\(condition.value.replacingOccurrences(of: "'", with: "\\'"))'"
//            case .contains:
//                sql += "\(escapedField) LIKE '%\(condition.value.replacingOccurrences(of: "'", with: "\\'"))%'"
//            case .notContains:
//                sql += "\(escapedField) NOT LIKE '%\(condition.value.replacingOccurrences(of: "'", with: "\\'"))%'"
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
            case .notLike:
                sql += "\(escapedField) NOT LIKE \(escapedValue)"
            case .isIn:
                // For IN operator, value should be comma-separated list: "1,2,3"
                let inValues = condition.value.split(separator: ",").map { 
                    "'\($0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "'", with: "\\'"))'" 
                }.joined(separator: ", ")
                sql += "\(escapedField) IN (\(inValues))"
            case .isNull:
                sql += "\(escapedField) IS NULL"
            case .isNotNull:
                sql += "\(escapedField) IS NOT NULL"
            case .ilike:
                break
            }
        }
        
        return sql
    }
    
    /// Builds WHERE clause from filter conditions for use in existing queries
    /// - Parameter conditions: Array of filter conditions
    /// - Returns: WHERE clause string (without SELECT/FROM)
    func buildWhereClause(from conditions: [FilterCondition]) -> String {
        let validConditions = conditions.filter { condition in
            !condition.field.isEmpty && 
            (condition.filterOperator == .isNull || condition.filterOperator == .isNotNull || 
             !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        
        guard !validConditions.isEmpty else { return "" }
        
        var whereClause = " WHERE "
        
        for (index, condition) in validConditions.enumerated() {
            if index > 0 {
                whereClause += " \(condition.conjunction.rawValue.uppercased()) "
            }
            
            let escapedField = quoteIdentifier(condition.field)
            let escapedValue = "'\(condition.value.replacingOccurrences(of: "'", with: "\\'"))'"

            switch condition.filterOperator {
            case .equals:
                whereClause += "\(escapedField) = \(escapedValue)"
            case .notEquals:
                whereClause += "\(escapedField) != \(escapedValue)"
            case .startsWith:
                whereClause += "\(escapedField) LIKE '\(condition.value.replacingOccurrences(of: "'", with: "\\'"))%'"
            case .endsWith:
                whereClause += "\(escapedField) LIKE '%\(condition.value.replacingOccurrences(of: "'", with: "\\'"))'"
            case .greaterThan:
                whereClause += "\(escapedField) > \(escapedValue)"
            case .greaterThanOrEquals:
                whereClause += "\(escapedField) >= \(escapedValue)"
            case .lessThan:
                whereClause += "\(escapedField) < \(escapedValue)"
            case .lessThanOrEquals:
                whereClause += "\(escapedField) <= \(escapedValue)"
            case .like:
                whereClause += "\(escapedField) LIKE \(escapedValue)"
            case .notLike:
                whereClause += "\(escapedField) NOT LIKE \(escapedValue)"
            case .isIn:
                // For IN operator, value should be comma-separated list: "1,2,3"
                let inValues = condition.value.split(separator: ",").map {
                    "'\($0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "'", with: "\\'"))'"
                }.joined(separator: ", ")
                whereClause += "\(escapedField) IN (\(inValues))"
            case .isNull:
                whereClause += "\(escapedField) IS NULL"
            case .isNotNull:
                whereClause += "\(escapedField) IS NOT NULL"
            case .ilike:
                break
            }
        }
        
        return whereClause
    }
}
