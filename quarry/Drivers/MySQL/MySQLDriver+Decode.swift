//
//  MySQLDriver+Decode.swift
//  Quarry
//
//  Created by Fauzaan on 21/8/25.
//

import Foundation
import MySQLNIO

extension MySQLDriver {
    // DateFormatter is thread-safe on modern platforms; cached to avoid a per-cell allocation
    nonisolated(unsafe) private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    func decode(from data: MySQLData) throws -> QueryRowInfo {
        // Check if the data is null
        if data.buffer == nil {
            return QueryRowInfo(
                value: nil,
                dataType: "nil",
                format: nil
            )
        }
        
        // Try different data types and return the appropriate QueryRowInfo
        if let stringValue = data.string {
            return QueryRowInfo(
                value: stringValue,
                dataType: "string",
                format: "text"
            )
        }
        
        if let intValue = data.int {
            return QueryRowInfo(
                value: intValue,
                dataType: "int",
                format: "integer"
            )
        }
        
        if let doubleValue = data.double {
            return QueryRowInfo(
                value: doubleValue,
                dataType: "double",
                format: "float"
            )
        }
        
        if let boolValue = data.bool {
            return QueryRowInfo(
                value: boolValue,
                dataType: "bool",
                format: "boolean"
            )
        }
        
        // For date/time types, try to get as string first
        if let dateValue = data.date {
            let dateString = Self.dateTimeFormatter.string(from: dateValue)
            return QueryRowInfo(
                value: dateString,
                dataType: "date",
                format: "datetime"
            )
        }
        
        // If we can't decode, return as raw data
        if let buffer = data.buffer {
            let rawData = buffer.getData(at: 0, length: buffer.readableBytes)
            return QueryRowInfo(
                value: rawData,
                dataType: "binary",
                format: "bytes"
            )
        }
        
        return QueryRowInfo(value: nil, dataType: "unknown", format: nil)
    }
    
    /// Helper method to decode MySQLData and convert to MySQLBindable
    func decodeAndConvertToBindable(_ value: Any) throws -> MySQLData {
        guard let mysqlData = value as? MySQLData else {
            throw DatabaseError.operationFailed("Cannot process non-MySQLData value: \(value)")
        }
        
        let decodedValue = try decode(from: mysqlData)
        return convertToMySQLBindable(decodedValue.value ?? .null)
    }
}
