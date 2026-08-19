//
//  Date+Timestampz.swift
//  Quarry
//
//  Created by Fauzaan on 7/5/25.
//

import Foundation

// MARK: - Cached Formatters

/// Cache of fully configured DateFormatters keyed by format + timezone.
/// DateFormatter is not thread-safe for mutation but is safe for concurrent
/// parsing/formatting once configured, so formatters are configured here at
/// creation and never mutated afterwards.
private enum TimestampTZFormatters {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    /// Returns a cached formatter for the given format. Passing no timezone
    /// preserves DateFormatter's default timezone behavior.
    static func formatter(format: String, timeZone: TimeZone? = nil) -> DateFormatter {
        let key = "\(format)|\(timeZone?.identifier ?? "default")"

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key] {
            return cached
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let timeZone {
            formatter.timeZone = timeZone
        }
        formatter.dateFormat = format
        cache[key] = formatter
        return formatter
    }
}

extension String {
    
    // MARK: - Timestamp with Timezone Parsing
    
    /// Parse string as timestamp with timezone
    func toDateFromTimestampTZ() throws -> (date: Date, timezone: TimeZone, offset: String) {
        // Try different formats and extract timezone info
        let formats: [(format: String, hasOffset: Bool)] = [
            ("yyyy-MM-dd HH:mm:ssZZZZZ", true),              // 2023-12-13 10:30:00+08:00
            ("yyyy-MM-dd HH:mm:ssZZZ", true),                // 2023-12-13 10:30:00+0800
            ("yyyy-MM-dd HH:mm:ssZ", true),                  // 2023-12-13 10:30:00+08
            ("yyyy-MM-dd'T'HH:mm:ssZZZZZ", true),           // 2023-12-13T10:30:00+08:00
            ("yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", true),       // 2023-12-13T10:30:00.123+08:00
            ("yyyy-MM-dd HH:mm:ss zzz", false),             // 2023-12-13 10:30:00 PST
            ("yyyy-MM-dd'T'HH:mm:ss'Z'", true)              // 2023-12-13T10:30:00Z (UTC)
        ]
        
        for (format, hasOffset) in formats {
            let formatter = TimestampTZFormatters.formatter(format: format)

            if let date = formatter.date(from: self) {
                let offset = extractTimezoneOffset() ?? "+00:00"
                let timezone = extractTimezone(formatter: formatter, hasOffset: hasOffset)
                return (date, timezone, offset)
            }
        }
        
        throw TimestampTZError.invalidFormat("Unable to parse timestamptz: \(self)")
    }
    
    /// Parse and preserve exact format for database
    func toTimestampTZData() throws -> TimestampTZData {
        let parsed = try toDateFromTimestampTZ()
        
        return TimestampTZData(
            originalString: self,
            date: parsed.date,
            timezone: parsed.timezone,
            offset: parsed.offset,
            format: detectedTimestampTZFormat()
        )
    }
    
    /// Validate timestamptz format
    var isValidTimestampTZ: Bool {
        return (try? toDateFromTimestampTZ()) != nil
    }
    
    // MARK: - Database Specific Methods
    
    /// Convert to PostgreSQL timestamptz
    func toPostgreSQLTimestampTZ() throws -> (date: Date, offset: String) {
        // PostgreSQL accepts various formats
        let formats = [
            "yyyy-MM-dd HH:mm:ssZZZ",      // 2023-12-13 10:30:00+08
            "yyyy-MM-dd HH:mm:ssZZZZZ",    // 2023-12-13 10:30:00+08:00
            "yyyy-MM-dd HH:mm:ss.SSSZZZ",  // 2023-12-13 10:30:00.123+08
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ"   // ISO 8601
        ]
        
        for format in formats {
            let formatter = TimestampTZFormatters.formatter(format: format)
            if let date = formatter.date(from: self) {
                let offset = extractTimezoneOffset() ?? "+00:00"

                // PostgreSQL is flexible with format, so just verify date is correct
                return (date, offset)
            }
        }
        
        throw TimestampTZError.invalidPostgreSQLFormat
    }
    
    /// Convert to SQL Server datetimeoffset
    func toSQLServerDateTimeOffset() throws -> (date: Date, offset: String) {
        // SQL Server uses specific format: YYYY-MM-DD hh:mm:ss[.nnnnnnn] [+|-]hh:mm
        let pattern = "^(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,7})?)\\s*([+-]\\d{2}:\\d{2})$"
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: self.utf16.count)),
              match.numberOfRanges == 3 else {
            throw TimestampTZError.invalidSQLServerFormat
        }
        
        let datePartRange = Range(match.range(at: 1), in: self)!
        let offsetRange = Range(match.range(at: 2), in: self)!
        
        let datePart = String(self[datePartRange])
        let offset = String(self[offsetRange])
        
        let formatter = TimestampTZFormatters.formatter(
            format: datePart.contains(".") ? "yyyy-MM-dd HH:mm:ss.SSSSSSS" : "yyyy-MM-dd HH:mm:ss",
            timeZone: TimeZone(secondsFromGMT: 0)
        )

        guard let date = formatter.date(from: datePart) else {
            throw TimestampTZError.invalidSQLServerFormat
        }
        
        return (date, offset)
    }
    
    // MARK: - Private Helper Methods
    
    private func extractTimezoneOffset() -> String? {
        // Extract timezone offset patterns
        let patterns = [
            "[+-]\\d{2}:\\d{2}",     // +08:00
            "[+-]\\d{4}",            // +0800
            "[+-]\\d{2}",            // +08
            "Z$"                     // Z (UTC)
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: self.utf16.count)),
               let range = Range(match.range, in: self) {
                let offset = String(self[range])
                return offset == "Z" ? "+00:00" : normalizeOffset(offset)
            }
        }
        
        return nil
    }
    
    private func normalizeOffset(_ offset: String) -> String {
        // Normalize to +HH:MM format
        if offset.count == 3 {  // +08
            return "\(offset):00"
        } else if offset.count == 5 && !offset.contains(":") {  // +0800
            let hours = offset.prefix(3)
            let minutes = offset.suffix(2)
            return "\(hours):\(minutes)"
        }
        return offset
    }
    
    private func extractTimezone(formatter: DateFormatter, hasOffset: Bool) -> TimeZone {
        if hasOffset, let offset = extractTimezoneOffset() {
            let seconds = offsetToSeconds(offset)
            return TimeZone(secondsFromGMT: seconds) ?? TimeZone.current
        }
        
        // Try to extract named timezone (PST, EST, etc.)
        if let abbr = extractTimezoneAbbreviation() {
            return TimeZone(abbreviation: abbr) ?? TimeZone.current
        }
        
        return formatter.timeZone ?? TimeZone.current
    }
    
    private func extractTimezoneAbbreviation() -> String? {
        let pattern = "\\s([A-Z]{3,4})$"  // PST, EST, GMT, etc.
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: self.utf16.count)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[range])
    }
    
    private func offsetToSeconds(_ offset: String) -> Int {
        // Convert +HH:MM to seconds
        let normalized = normalizeOffset(offset)
        let components = normalized.replacingOccurrences(of: "+", with: "").split(separator: ":")
        
        guard components.count == 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]) else {
            return 0
        }
        
        let sign = normalized.hasPrefix("-") ? -1 : 1
        return sign * (hours * 3600 + minutes * 60)
    }
    
    private func detectedTimestampTZFormat() -> TimestampTZFormat {
        if self.contains("T") && self.hasSuffix("Z") {
            return .iso8601UTC
        } else if self.contains("T") {
            return .iso8601
        } else if self.contains(".") {
            return .standardWithMillis
        } else {
            return .standard
        }
    }
}

// MARK: - Supporting Types

struct TimestampTZData {
    let originalString: String
    let date: Date
    let timezone: TimeZone
    let offset: String
    let format: TimestampTZFormat
    
    /// Reconstruct the original string
    func toString() -> String {
        let formatter = TimestampTZFormatters.formatter(format: format.dateFormat, timeZone: timezone)
        return formatter.string(from: date)
    }
    
    /// Convert to specific database format
    func toDatabaseString(for database: DatabaseType) -> String {
        switch database {
        case .postgres:
            return toPostgreSQLString()
        case .mysql:
            // MySQL doesn't have true timestamptz, converts to UTC
            return toMySQLString()
        default:
            fatalError("Unsupported database type: \(database)")
        }
    }
    
    private func toPostgreSQLString() -> String {
        let formatter = TimestampTZFormatters.formatter(format: "yyyy-MM-dd HH:mm:ssZZZ", timeZone: timezone)
        return formatter.string(from: date)
    }

    private func toMySQLString() -> String {
        // MySQL converts to UTC
        let formatter = TimestampTZFormatters.formatter(format: "yyyy-MM-dd HH:mm:ss", timeZone: TimeZone(secondsFromGMT: 0))
        return formatter.string(from: date)
    }
}

enum TimestampTZFormat {
    case standard              // 2023-12-13 10:30:00+08:00
    case standardWithMillis    // 2023-12-13 10:30:00.123+08:00
    case iso8601              // 2023-12-13T10:30:00+08:00
    case iso8601UTC           // 2023-12-13T10:30:00Z
    case sqlServer            // 2023-12-13 10:30:00 +08:00
    
    var dateFormat: String {
        switch self {
        case .standard:
            return "yyyy-MM-dd HH:mm:ssZZZZZ"
        case .standardWithMillis:
            return "yyyy-MM-dd HH:mm:ss.SSSZZZZZ"
        case .iso8601:
            return "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        case .iso8601UTC:
            return "yyyy-MM-dd'T'HH:mm:ss'Z'"
        case .sqlServer:
            return "yyyy-MM-dd HH:mm:ss ZZZZZ"
        }
    }
}

enum TimestampTZError: LocalizedError {
    case invalidFormat(String)
    case invalidPostgreSQLFormat
    case invalidSQLServerFormat
    case timezoneConversionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return message
        case .invalidPostgreSQLFormat:
            return "Invalid PostgreSQL timestamptz format"
        case .invalidSQLServerFormat:
            return "Invalid SQL Server datetimeoffset format"
        case .timezoneConversionFailed:
            return "Failed to convert timezone"
        }
    }
}

// MARK: - Date Extension for TimestampTZ

extension Date {
    /// Convert to timestamptz string with specific timezone
    func toTimestampTZ(timezone: TimeZone = .current, format: TimestampTZFormat = .standard) -> String {
        let formatter = TimestampTZFormatters.formatter(format: format.dateFormat, timeZone: timezone)
        return formatter.string(from: self)
    }
    
    /// Convert to timestamptz for specific database
    func toTimestampTZFor(_ database: DatabaseType, timezone: TimeZone = .current) -> String {
        switch database {
        case .postgres:
            return toTimestampTZ(timezone: timezone, format: .standard)
        case .mysql:
            // MySQL doesn't support timestamptz, convert to UTC
            return toTimestampTZ(timezone: TimeZone(secondsFromGMT: 0)!, format: .standard)
                .replacingOccurrences(of: "+00:00", with: "")
        default:
            fatalError("Unsupported database type: \(database)")
        }
    }
}
