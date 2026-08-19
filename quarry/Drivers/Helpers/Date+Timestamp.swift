//
//  Date+Timestamp.swift
//  Quarry
//
//  Created by Fauzaan on 7/5/25.
//

import Foundation

extension String {
    // MARK: - Database Timestamp Parsing
    /// Parse string as database timestamp without timezone conversion
    func toDateFromDatabaseTimestamp() throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // Always UTC
        formatter.isLenient = false
        
        // Try common database timestamp formats
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        ]
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: self) {
                // Verify round-trip conversion
                let reconstructed = formatter.string(from: date)
                if reconstructed == self {
                    return date
                }
            }
        }
        
        throw TimestampError.invalidFormat("Unable to parse timestamp: \(self)")
    }
    
    /// Parse with specific database type
    func toDateForDatabase(_ type: DatabaseType) throws -> Date {
        switch type {
        case .mysql:
            return try toMySQLDate()
        case .postgres:
            return try toPostgreSQLDate()
        default :
            fatalError("Unsupported database type \(type)")
        }
    }
    
    /// Validate if string is a valid database timestamp
    var isValidDatabaseTimestamp: Bool {
        return (try? toDateFromDatabaseTimestamp()) != nil
    }
    
    /// Validate for specific database
    func isValidTimestampFor(_ database: DatabaseType) -> Bool {
        return (try? toDateForDatabase(database)) != nil
    }
    
    // MARK: - Database Specific Methods
    
    private func toMySQLDate() throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        
        guard let date = formatter.date(from: self) else {
            throw TimestampError.invalidMySQLFormat
        }
        
        return date
    }
    
    func toPostgreSQLDate() throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        
        // PostgreSQL supports microseconds
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss.SSSSSS"
        ]
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: self) {
                return date
            }
        }
        
        throw TimestampError.invalidPostgreSQLFormat
    }
    
    private func toSQLiteDate() throws -> Date {
        // SQLite can store in multiple formats
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS"
        ]
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: self) {
                return date
            }
        }
        
        throw TimestampError.invalidSQLiteFormat
    }
    
    // MARK: - Format Detection
    
    /// Detect timestamp format
    var detectedTimestampFormat: TimestampFormat? {
        let patterns: [(TimestampFormat, String)] = [
            (.standard, "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$"),
            (.withMilliseconds, "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}$"),
            (.withMicroseconds, "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{6}$"),
            (.iso8601, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$"),
            (.iso8601WithZ, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
        ]
        
        for (format, pattern) in patterns {
            if self.matches(pattern) {
                return format
            }
        }
        
        return nil
    }
    
    private func matches(_ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}

enum TimestampFormat: String {
    case standard = "yyyy-MM-dd HH:mm:ss"
    case withMilliseconds = "yyyy-MM-dd HH:mm:ss.SSS"
    case withMicroseconds = "yyyy-MM-dd HH:mm:ss.SSSSSS"
    case iso8601 = "yyyy-MM-dd'T'HH:mm:ss"
    case iso8601WithZ = "yyyy-MM-dd'T'HH:mm:ss'Z'"
}

enum TimestampError: LocalizedError {
    case invalidFormat(String)
    case invalidMySQLFormat
    case invalidPostgreSQLFormat
    case invalidSQLiteFormat
    case roundTripValidationFailed(original: String, converted: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return message
        case .invalidMySQLFormat:
            return "Invalid MySQL timestamp format. Expected: YYYY-MM-DD HH:MM:SS"
        case .invalidPostgreSQLFormat:
            return "Invalid PostgreSQL timestamp format"
        case .invalidSQLiteFormat:
            return "Invalid SQLite timestamp format"
        case .roundTripValidationFailed(let original, let converted):
            return "Round-trip validation failed: '\(original)' != '\(converted)'"
        }
    }
}
