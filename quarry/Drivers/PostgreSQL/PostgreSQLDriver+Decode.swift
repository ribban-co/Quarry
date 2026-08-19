//
//  PostgreSQLDriver+Decode.swift
//  Quarry
//
//  Created by Fauzaan on 7/4/25.
//

import Foundation
import PostgresNIO

/// Cached formatters for rendering date cells. DateFormatter is not
/// thread-safe for mutation but is safe for concurrent formatting once
/// configured, so each one is fully configured at init and never mutated.
private enum PostgresCellDateFormatters {
    nonisolated(unsafe) static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    nonisolated(unsafe) static let timestamptz: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssX"
        return formatter
    }()

    nonisolated(unsafe) static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension PostgreSQLDriver {
    func decode(from cell: PostgresCell) throws -> QueryRowInfo {
        // Check if the cell is null
        if cell.bytes == nil {
            return QueryRowInfo(
                value: nil,
                dataType: "nil",
                format: nil
            )
        }
        
        // Extract value based on PostgreSQL data type
        switch cell.dataType {
        case .bool:
            let value = try cell.decode(Bool.self)
            return QueryRowInfo(
                value: value,
                dataType: "bool",
                format: String(describing: cell.format)
            )
            
        case .int2:
            let value = try cell.decode(Int16.self)
            return QueryRowInfo(
                value: value,
                dataType: "int2",
                format: String(describing: cell.format)
            )
            
        case .int4:
            let value = try cell.decode(Int32.self)
            return QueryRowInfo(
                value: value,
                dataType: "int4",
                format: String(describing: cell.format)
            )
            
        case .int8:
            let value = try cell.decode(Int64.self)
            return QueryRowInfo(
                value: value,
                dataType: "int8",
                format: String(describing: cell.format)
            )
            
        case .float4:
            let value = try cell.decode(Float.self)
            return QueryRowInfo(
                value: value,
                dataType: "float4",
                format: String(describing: cell.format)
            )
            
        case .float8:
            let value = try cell.decode(Double.self)
            return QueryRowInfo(
                value: value,
                dataType: "float8",
                format: String(describing: cell.format)
            )
            
        case .text, .varchar, .char:
            let value = try cell.decode(String.self)
            return QueryRowInfo(
                value: value,
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .textArray, .varcharArray, .charArray:
            let stringArray = try cell.decode([String].self)
            return QueryRowInfo(
                value: "{" + stringArray.joined(separator: ",") + "}",
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .int4Array:
            let int4Array = try cell.decode([Int32].self)
            return QueryRowInfo(
                value: "[" + int4Array.map { String($0) }.joined(separator: ", ") + "]",
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .int4Range:
            let range = try cell.decode(Range<Int32>.self)
            return QueryRowInfo(
                value: range.description,
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .int8Range:
            let range = try cell.decode(Range<Int64>.self)
            return QueryRowInfo(
                value: "[\(range.lowerBound),\(range.upperBound))",
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .numrange:
            let stringValue = try cell.decode(String.self)
            return QueryRowInfo(
                value: stringValue,
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .timestamp:
            let value = try cell.decode(Date.self)
            let dateString = PostgresCellDateFormatters.timestamp.string(from: value)
            return QueryRowInfo(
                value: dateString,
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .timestamptz:
            let value = try cell.decode(Date.self)
            let dateString = PostgresCellDateFormatters.timestamptz.string(from: value)
            return QueryRowInfo(
                value: dateString,
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .time:
            let value = try cell.decode(PostgresTimeOfDayValue.self)
            return QueryRowInfo(
                value: value,
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .date:
            let value = try cell.decode(Date.self)
            let dateString = PostgresCellDateFormatters.date.string(from: value)
            return QueryRowInfo(
                value: dateString,
                dataType: "date",
                format: String(describing: cell.format)
            )
            
        case .uuid:
            let value = try cell.decode(UUID.self)
            return QueryRowInfo(
                value: value.description.lowercased(),
                dataType: "uuid",
                format: String(describing: cell.format)
            )
            
        case .json, .jsonb:
            let jsonString = try cell.decode(String.self)
            return QueryRowInfo(
                value: jsonString,
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
            
        case .bytea:
            let value = try cell.decode(Data.self)
            return QueryRowInfo(
                value: value,
                dataType: "bytea",
                format: String(describing: cell.format)
            )
            
        case .numeric:
            let value = try cell.decode(Decimal.self)
            return QueryRowInfo(
                value: value.description,
                dataType: "numeric",
                format: String(describing: cell.format)
            )
            
        case .money:
            guard var bytes = cell.bytes else {
                return QueryRowInfo(
                    value: nil,
                    dataType: "nil",
                    format: nil
                )
            }
            
            guard let rawValue = bytes.readInteger(as: Int64.self) else {
                // Fallback for safety, though binary should contain Int64
                let stringValue = try? cell.decode(String.self)
                return QueryRowInfo(
                    value: stringValue,
                    dataType: "money",
                    format: String(describing: cell.format)
                )
            }
            // PostgreSQL money type is a 64-bit integer of cents.
            let decimalValue = Decimal(rawValue) / 100.0
            return QueryRowInfo(
                value: decimalValue.description,
                dataType: "money",
                format: String(describing: cell.format)
            )
            
        default:
            let value = try cell.decode(String.self)
            return QueryRowInfo(
                value: value,
                dataType: String(describing: cell.dataType),
                format: String(describing: cell.format)
            )
        }
    }
}

