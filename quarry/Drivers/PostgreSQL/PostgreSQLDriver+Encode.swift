//
//  PostgreSQLDriver+Encode.swift
//  Quarry
//
//  Created by Fauzaan on 7/4/25.
//
import PostgresNIO
import Foundation

extension PostgreSQLDriver {
    /// Generates a SET clause with proper type casting for PostgreSQL data types
    func buildSetClause(for columnName: String, parameterIndex: Int, columnType: PostgresDataType, enumTypeName: String? = nil) -> String {
        switch columnType {
        case .jsonb:
            return "\"\(columnName)\" = $\(parameterIndex)::jsonb"
        case .json:
            return "\"\(columnName)\" = $\(parameterIndex)::json"
        case .money:
            return "\"\(columnName)\" = $\(parameterIndex)::money"
        case .numeric:
            return "\"\(columnName)\" = $\(parameterIndex)::numeric"
        case .uuid:
            return "\"\(columnName)\" = $\(parameterIndex)::uuid"
        case .time:
            return "\"\(columnName)\" = $\(parameterIndex)::time"
        case .timestamp:
            return "\"\(columnName)\" = $\(parameterIndex)::timestamp"
        case .timestamptz:
            return "\"\(columnName)\" = $\(parameterIndex)::timestamptz"
        case .date:
            return "\"\(columnName)\" = $\(parameterIndex)::date"
        case .xml:
            return "\"\(columnName)\" = $\(parameterIndex)::xml"
        case .bytea:
            return "\"\(columnName)\" = $\(parameterIndex)::bytea"
        default:
            if columnType.isUserDefined {
                // For enums and other user-defined types, we need to cast to the specific type
                if let enumTypeName = enumTypeName {
                    return "\"\(columnName)\" = $\(parameterIndex)::\"\(enumTypeName)\""
                } else {
                    // Fallback if enum type name is not provided
                    return "\"\(columnName)\" = $\(parameterIndex)"
                }
            } else {
                return "\"\(columnName)\" = $\(parameterIndex)"
            }
        }
    }
    
    func encode(_ value: Any, columnName: String, columnType: PostgresDataType) throws -> PostgresEncodable? {
        guard let stringValue = value as? String else {
            throw DatabaseError.operationFailed("Expected string value for column \(columnName)")
        }
        
        switch columnType {
        case .bool:
            if stringValue.isEmpty {
                return nil
            }
            let lowercased = stringValue.lowercased()
            if ["true", "1", "yes", "on"].contains(lowercased) {
                return true
            } else if ["false", "0", "no", "off"].contains(lowercased) {
                return false
            } else {
                throw DatabaseError.operationFailed("Cannot convert '\(stringValue)' to boolean for column \(columnName)")
            }
            
        case .int2:
            if stringValue.isEmpty {
                return nil
            }
            
            guard let intValue = Int16(stringValue) else {
                throw DatabaseError.operationFailed("Cannot convert '\(stringValue)' to Int16 for column \(columnName)")
            }
            return intValue
            
        case .int4:
            if stringValue.isEmpty {
                return nil
            }
            guard let intValue = Int32(stringValue) else {
                throw DatabaseError.operationFailed("Cannot convert '\(stringValue)' to Int32 for column \(columnName)")
            }
            return intValue
            
        case .int8:
            if stringValue.isEmpty {
                return nil
            }
            guard let intValue = Int64(stringValue) else {
                throw DatabaseError.operationFailed("Cannot convert '\(stringValue)' to Int64 for column \(columnName)")
            }
            return intValue
            
        case .float4:
            if stringValue.isEmpty {
                return nil
            }
            guard let floatValue = Float(stringValue) else {
                throw DatabaseError.operationFailed("Cannot convert '\(stringValue)' to Float for column \(columnName)")
            }
            return floatValue
            
        case .float8, .numeric:
            if stringValue.isEmpty {
                return nil
            }
            guard let doubleValue = Double(stringValue) else {
                throw DatabaseError.operationFailed("Cannot convert '\(stringValue)' to Double for column \(columnName)")
            }
            return doubleValue
            
        case .uuid:
            if stringValue.isEmpty {
                return nil
            }
            guard let uuidValue = UUID(uuidString: stringValue) else {
                throw DatabaseError.operationFailed("Cannot convert '\(stringValue)' to UUID for column \(columnName)")
            }
            return uuidValue
    
        case .date:
            if stringValue.isEmpty {
                return nil
            }
            let date = try stringValue.toDate()
            return date
            
        case .timestamptz:
            if stringValue.isEmpty {
                return nil
            }
            let normalizedDateString = try stringValue.toPostgreSQLTimestampTZ()
            return normalizedDateString.date
        case .jsonb:
            if stringValue.isEmpty {
                return nil
            }
            // Your existing JSONB cleaning logic
            var cleanedString = stringValue
            
            while let firstChar = cleanedString.first, firstChar.asciiValue != nil && firstChar.asciiValue! < 32 {
                cleanedString = String(cleanedString.dropFirst())
            }
            
            while let lastChar = cleanedString.last, lastChar.asciiValue != nil && lastChar.asciiValue! < 32 {
                cleanedString = String(cleanedString.dropLast())
            }
            
            if cleanedString.hasPrefix("\"") && cleanedString.hasSuffix("\"") {
                cleanedString = String(cleanedString.dropFirst().dropLast())
            }
            
            if cleanedString.contains("\\\"") {
                cleanedString = cleanedString.replacingOccurrences(of: "\\\"", with: "\"")
            }
            
            return cleanedString
        
        case .money:
            if stringValue.isEmpty {
                return nil
            }

            var cleanValue = stringValue
            cleanValue = cleanValue.replacingOccurrences(of: "$", with: "")
            cleanValue = cleanValue.replacingOccurrences(of: ",", with: "")
            cleanValue = cleanValue.replacingOccurrences(of: "€", with: "")
            cleanValue = cleanValue.replacingOccurrences(of: "£", with: "")
            
            guard let doubleValue = Double(cleanValue) else {
                throw DatabaseError.operationFailed("Cannot convert '\(stringValue)' to money value for column \(columnName)")
            }
            
            return String(format: "%.2f", doubleValue)
            
        case .text, .varchar, .bpchar:
            if stringValue.isEmpty {
                return ""
            } else {
                return stringValue
            }

        case .int2Array:
            return try parseNumericArray(stringValue, columnName: columnName) { Int16($0) }
        case .int4Array:
            return try parseNumericArray(stringValue, columnName: columnName) { Int32($0) }
        case .int8Array:
            return try parseNumericArray(stringValue, columnName: columnName) { Int64($0) }
        case .float4Array:
            return try parseNumericArray(stringValue, columnName: columnName) { Float($0) }
        case .float8Array:
            return try parseNumericArray(stringValue, columnName: columnName) { Double($0) }
        case .boolArray:
            let elements = parseArrayElements(stringValue)
            return try elements.map { raw -> Bool in
                switch raw.lowercased() {
                case "true", "t", "1", "yes", "on": return true
                case "false", "f", "0", "no", "off": return false
                default:
                    throw DatabaseError.operationFailed("Cannot convert '\(raw)' to Bool in array for column \(columnName)")
                }
            }
        case .uuidArray:
            let elements = parseArrayElements(stringValue)
            return try elements.map { raw -> UUID in
                guard let uuid = UUID(uuidString: raw) else {
                    throw DatabaseError.operationFailed("Cannot convert '\(raw)' to UUID in array for column \(columnName)")
                }
                return uuid
            }
        case .textArray, .varcharArray, .bpcharArray, .charArray:
            return parseArrayElements(stringValue)

        default:
            if stringValue.isEmpty {
                return nil
            }

            return stringValue
        }
    }

    /// Parse a user-facing array string like "[1, 2, 3]" or "{1,2,3}" into element tokens.
    private func parseArrayElements(_ text: String) -> [String] {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("[") && s.hasSuffix("]")) || (s.hasPrefix("{") && s.hasSuffix("}")) {
            s = String(s.dropFirst().dropLast())
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseNumericArray<T>(
        _ text: String,
        columnName: String,
        convert: (String) -> T?
    ) throws -> [T] {
        let elements = parseArrayElements(text)
        return try elements.map { raw -> T in
            guard let value = convert(raw) else {
                throw DatabaseError.operationFailed("Cannot convert '\(raw)' to \(T.self) in array for column \(columnName)")
            }
            return value
        }
    }

    func encode(_ value: DatabaseValue, columnName: String, columnType: PostgresDataType) throws -> PostgresEncodable? {
        switch value {
        case .null:
            return nil
        case .bool(let value):
            if columnType == .bool {
                return value
            }
            return try encode(value.description, columnName: columnName, columnType: columnType)
        case .int(let value):
            switch columnType {
            case .int2:
                return Int16(clamping: value)
            case .int4:
                return Int32(clamping: value)
            case .int8:
                return Int64(value)
            default:
                return try encode(String(value), columnName: columnName, columnType: columnType)
            }
        case .int64(let value):
            switch columnType {
            case .int2:
                return Int16(clamping: Int(value))
            case .int4:
                return Int32(clamping: Int(value))
            case .int8:
                return value
            default:
                return try encode(String(value), columnName: columnName, columnType: columnType)
            }
        case .double(let value):
            switch columnType {
            case .float4:
                return Float(value)
            case .float8, .numeric:
                return value
            default:
                return try encode(String(value), columnName: columnName, columnType: columnType)
            }
        case .string(let value), .decimalString(let value), .objectID(let value):
            return try encode(value, columnName: columnName, columnType: columnType)
        case .date(let value):
            if [.date, .timestamp, .timestamptz].contains(columnType) {
                return value
            }
            return try encode(value.ISO8601Format(), columnName: columnName, columnType: columnType)
        case .data(let value):
            if columnType == .bytea {
                return value
            }
            return try encode(value.base64EncodedString(), columnName: columnName, columnType: columnType)
        case .uuid(let value):
            if columnType == .uuid {
                return value
            }
            return try encode(value.uuidString, columnName: columnName, columnType: columnType)
        case .array, .object:
            return try encode(value.description, columnName: columnName, columnType: columnType)
        }
    }
}


extension String {
    func toDate() throws -> Date? {
        let formats = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "MM-dd-yyyy",
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            "dd.MM.yyyy",
            "MMM dd, yyyy",
            "MMMM dd, yyyy",
            "dd MMM yyyy",
            "dd MMMM yyyy",
            "EEEE, MMM dd, yyyy",
            "yyyy/MM/dd",
            "dd-MMM-yyyy",
            "MM/dd/yyyy HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "HH:mm:ss",
            "h:mm a",
            "MMM yyyy"
        ]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: self) {
                return date
            }
        }
        
        throw DatabaseError.operationFailed("Unable to parse date string \(self)")
    }
}
