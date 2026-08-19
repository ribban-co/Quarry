import Foundation

// MARK: - Convex Value Types

enum ConvexValue {
    case id(String)
    case null
    case int64(Int64)
    case float64(Double)
    case boolean(Bool)
    case string(String)
    case bytes(Data)
    case array([ConvexValue])
    case object([String: ConvexValue])
    case record([String: ConvexValue])
    
    // MARK: - Type Inference from Swift Values
    
    static func from(_ value: Any?, fieldName: String? = nil) -> ConvexValue {
        // Handle special system fields
        if let fieldName = fieldName {
            if fieldName == "_id" {
                return .id(value as? String ?? "")
            }
            if fieldName == "_creationTime" {
                if let number = value as? NSNumber {
                    return .int64(number.int64Value)
                }
            }
        }

        switch value {
        case nil:
            return .null
        case is NSNull:
            return .null
        case let string as String:
            // Check if it's a Convex ID format
            if string.starts(with: "j") && string.count > 20 {
                return .id(string)
            }
            return .string(string)
        case let number as NSNumber:
            // Check if it's a boolean
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            // Check if it's an integer or float
            if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return .int64(number.int64Value)
            }
            return .float64(number.doubleValue)
        case let bool as Bool:
            return .boolean(bool)
        case let data as Data:
            return .bytes(data)
        case let array as [Any]:
            return .array(array.map { ConvexValue.from($0) })
        case let dict as [String: Any]:
            // Decode Convex wire format type wrappers (single-key objects with $ prefix)
            if dict.count == 1, let (key, inner) = dict.first, key.hasPrefix("$") {
                switch key {
                case "$integer":
                    if let base64 = inner as? String,
                       let data = Data(base64Encoded: base64),
                       data.count == 8 {
                        let decoded = data.withUnsafeBytes { $0.load(as: Int64.self) }
                        return .int64(decoded)
                    }
                case "$float":
                    if let base64 = inner as? String,
                       let data = Data(base64Encoded: base64),
                       data.count == 8 {
                        let decoded = data.withUnsafeBytes { $0.load(as: Double.self) }
                        return .float64(decoded)
                    }
                case "$bytes":
                    if let base64 = inner as? String,
                       let data = Data(base64Encoded: base64) {
                        return .bytes(data)
                    }
                default:
                    break
                }
            }
            let convexDict = dict.mapValues { ConvexValue.from($0) }
            return .object(convexDict)
        default:
            return .string(String(describing: value))
        }
    }
    
    // MARK: - Type Information
    
    var typeName: String {
        switch self {
        case .id: return "id"
        case .null: return "null"
        case .int64: return "int64"
        case .float64: return "float64"
        case .boolean: return "boolean"
        case .string: return "string"
        case .bytes: return "bytes"
        case .array: return "array"
        case .object: return "object"
        case .record: return "record"
        }
    }
    
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
    
    // MARK: - Value Extraction
    
    func asString() -> String? {
        switch self {
        case .string(let value), .id(let value): return value
        default: return nil
        }
    }
    
    func asInt64() -> Int64? {
        if case .int64(let value) = self { return value }
        return nil
    }
    
    func asFloat64() -> Double? {
        if case .float64(let value) = self { return value }
        return nil
    }
    
    func asBool() -> Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }
    
    func asData() -> Data? {
        if case .bytes(let value) = self { return value }
        return nil
    }
    
    func asArray() -> [ConvexValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
    
    func asObject() -> [String: ConvexValue]? {
        switch self {
        case .object(let value), .record(let value): return value
        default: return nil
        }
    }
    
    // MARK: - Swift Value Conversion
    
    func toSwiftValue() -> Any? {
        switch self {
        case .id(let value), .string(let value):
            return value
        case .null:
            return nil
        case .int64(let value):
            return value
        case .float64(let value):
            return value
        case .boolean(let value):
            return value
        case .bytes(let value):
            return value
        case .array(let values):
            return values.map { $0.toSwiftValue() }
        case .object(let dict), .record(let dict):
            return dict.mapValues { $0.toSwiftValue() }
        }
    }
}

// MARK: - Convex Field Type Parsing

struct ConvexFieldType {
    let type: String
    let value: Any?
    let optional: Bool
    let referencedTableName: String?
    let isForeignKey: Bool
    
    init(from fieldInfo: [String: Any]) throws {
        guard let fieldType = fieldInfo["fieldType"] as? [String: Any],
              let type = fieldType["type"] as? String else {
            throw ConvexError.decodingError("Invalid field type structure")
        }
        
        self.type = type
        self.value = fieldType["value"]
        self.optional = fieldInfo["optional"] as? Bool ?? false
        let tableName = (fieldType["tableName"] as? String) ?? (fieldType["table_name"] as? String)
        self.referencedTableName = tableName
        self.isForeignKey = (type == "id" && tableName != nil)
    }
    
    var swiftTypeName: String {
        switch type {
        case "number": return "float64"
        case "union": return parseUnionType()
        default: return type
        }
    }
    
    private func parseUnionType() -> String {
        guard let unionValues = value as? [[String: Any]] else {
            return "union"
        }
        
        // Filter out null types and get the first non-null type
        let nonNullTypes = unionValues.compactMap { unionType -> String? in
            unionType["type"] as? String
        }.filter { $0 != "null" }
        
        return nonNullTypes.first ?? "union"
    }
}

// MARK: - Query Result Helpers

extension ConvexValue {
    
    static func inferDataType(from value: Any?, fieldName: String? = nil) -> String {
        let convexValue = ConvexValue.from(value, fieldName: fieldName)
        return convexValue.typeName
    }
    
    static func createQueryColumnInfo(name: String, value: Any?, index: Int) -> QueryColumnInfo {
        let dataType = inferDataType(from: value, fieldName: name)
        return QueryColumnInfo(
            name: name,
            dataType: dataType,
            format: nil,
            index: index
        )
    }
    
    static func createQueryRowInfo(value: Any?, fieldName: String? = nil) -> QueryRowInfo {
        let dataType = inferDataType(from: value, fieldName: fieldName)
        let formattedValue = formatValueForDisplay(value: value, fieldName: fieldName, dataType: dataType)
        
        return QueryRowInfo(
            value: formattedValue,
            dataType: dataType,
            format: nil
        )
    }
    
    static func formatValueForDisplay(value: Any?, fieldName: String?, dataType: String) -> Any? {
        guard let value = value else { return nil }
        
        if ((value as? NSNull) != nil) {
            return nil
        }
        
        // Primary formatting based on schema data type
        switch dataType {
        case "int64":
            // Handle Int64 values, check if they should be formatted as dates
            let int64Value: Int64
            if let timestamp = value as? Int64 {
                int64Value = timestamp
            } else if let timestampNum = value as? NSNumber {
                int64Value = timestampNum.int64Value
            } else if let dict = value as? [String: Any],
                      let base64 = dict["$integer"] as? String,
                      let data = Data(base64Encoded: base64),
                      data.count == 8 {
                // Decode Convex wire format {"$integer": "base64"}
                int64Value = data.withUnsafeBytes { $0.load(as: Int64.self) }
            } else {
                return value
            }
            
            // Special case for _creationTime field - always format as date
            if let fieldName = fieldName, fieldName == "_creationTime" {
                return formatTimestamp(int64Value)
            }
            
            // For other int64 fields, only format as date if in reasonable timestamp range
            if isReasonableTimestamp(int64Value) {
                return formatTimestamp(int64Value)
            }
            
            return int64Value
            
        case "float64", "number":
            // Decode Convex wire format {"$float": "base64"} for special floats (NaN, Inf, -0)
            if let dict = value as? [String: Any],
               let base64 = dict["$float"] as? String,
               let data = Data(base64Encoded: base64),
               data.count == 8 {
                let decoded = data.withUnsafeBytes { $0.load(as: Double.self) }
                if decoded.isNaN { return "NaN" }
                if decoded.isInfinite { return decoded > 0 ? "Infinity" : "-Infinity" }
                return decoded
            }
            return value
            
        case "boolean":
            if let boolValue = value as? Bool {
                return boolValue ? "true" : "false"
            }
            
            return value
        case "string":
            // Only format date strings for fields that explicitly look like date fields
            if let fieldName = fieldName, isDateFieldName(fieldName), let dateString = value as? String {
                return formatDateString(dateString)
            }
            return value
            
        case "id":
            return value
            
        case "bytes":
            // Decode Convex wire format {"$bytes": "base64"}
            if let dict = value as? [String: Any],
               let base64 = dict["$bytes"] as? String {
                return base64
            }
            if let data = value as? Data {
                return data.base64EncodedString()
            }
            return compactifyJSON(value)
            
        case "array":
            // Handle JSON arrays - compact them for table display
            if let jsonArray = value as? [Any] {
                return compactifyJSON(jsonArray)
            }
            return value
            
        case "object", "record":
            // Handle JSON objects - compact them for table display
            if let jsonDict = value as? [String: Any] {
                return compactifyJSON(jsonDict)
            }
            return value
            
        case "null":
            return nil
            
        default:
            // Fallback for unknown data types
            if let jsonDict = value as? [String: Any] {
                return compactifyJSON(jsonDict)
            } else if let jsonArray = value as? [Any] {
                return compactifyJSON(jsonArray)
            }
            return value
        }
    }
    
    private static func compactifyJSON(_ value: Any) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
            if let compactString = String(data: jsonData, encoding: .utf8) {
                return compactString
            }
        } catch {
            // If JSON serialization fails, fall back to string description
        }
        return String(describing: value)
    }
    
    private static func isDateFieldName(_ fieldName: String) -> Bool {
        let datePatterns = [
            "_time", "time", "date", "created", "updated", "modified",
            "timestamp", "at", "on", "_at", "_on", "_date", "_created",
            "_updated", "_modified", "last_update", "create_date",
            "payment_date", "rental_date", "return_date"
        ]
        
        let lowercased = fieldName.lowercased()
        return datePatterns.contains { pattern in
            lowercased.contains(pattern)
        }
    }
    
    private static func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy, h:mm:ss a"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }
    
    private static func formatDateString(_ dateString: String) -> String {
        // Try to parse common date formats and reformat them
        let formatters = [
            // ISO 8601 formats
            ISO8601DateFormatter(),
            // Custom formatters for common patterns
            createDateFormatter("yyyy-MM-dd HH:mm:ss"),
            createDateFormatter("yyyy-MM-dd'T'HH:mm:ss"),
            createDateFormatter("yyyy-MM-dd"),
            createDateFormatter("MM/dd/yyyy"),
            createDateFormatter("dd/MM/yyyy")
        ]
        
        for formatter in formatters {
            var date: Date?
            
            if let isoFormatter = formatter as? ISO8601DateFormatter {
                date = isoFormatter.date(from: dateString)
            } else if let dateFormatter = formatter as? DateFormatter {
                date = dateFormatter.date(from: dateString)
            }
            
            if let parsedDate = date {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "M/d/yyyy, h:mm:ss a"
                displayFormatter.locale = Locale(identifier: "en_US")
                return displayFormatter.string(from: parsedDate)
            }
        }
        
        // If we can't parse it, return the original string
        return dateString
    }
    
    private static func createDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
    
    private static func isReasonableTimestamp(_ timestamp: Int64) -> Bool {
        // Match Convex's COMMON_UTC_TIMESTAMP_RANGE: [1e12, 4.1e12] (~2001 to ~2100)
        // This is specifically for millisecond timestamps
        let convexTimestampMin: Int64 = 1_000_000_000_000  // 1e12
        let convexTimestampMax: Int64 = 4_100_000_000_000  // 4.1e12
        
        return timestamp > convexTimestampMin && timestamp < convexTimestampMax
    }
}
