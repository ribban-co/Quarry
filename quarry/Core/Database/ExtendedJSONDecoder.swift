//
//  ExtendedJSONDecoder.swift
//  Quarry
//
//  Created by Fauzaan on 4/5/25.
//

import Foundation
import NIOCore
import BSON
import MongoKitten

/// Facilitates the decoding of ExtendedJSON values into BSON Document objects.
struct ExtendedJSONDecoder {
    nonisolated(unsafe) internal static var extJSONDateFormatterSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    nonisolated(unsafe) internal static var extJSONDateFormatterMilliseconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Decodes a Document directly from Extended JSON data
    /// - Parameter data: The JSON data in Extended JSON format
    /// - Returns: A BSON Document
    /// - Throws: Error if JSON cannot be parsed or is invalid Extended JSON
    public func decodeDocument(from data: Data) throws -> Document {
        let decoder = JSONDecoder(data: data)
        let json = try decoder.jsonKeyValuePairs()
        return try convertJSONToDocument(json, keyPath: [])
    }
    
    private func convertJSONToDocument(_ jsonData: [(key: String, value: Any)], keyPath: [String] = []) throws -> Document {
        // Create a new document
        var document = Document()
        
        // Process each key-value pair in the ordered array
        for (key, value) in jsonData {
            document[key] = try convertToPrimitive(value, keyPath: keyPath + [key])
        }
        
        return document
    }
    
    /// Converts Swift type to BSON Primitive
    /// - Parameters:
    ///   - value: The Swift value to convert
    ///   - keyPath: The current path in the JSON structure (for error reporting)
    /// - Returns: A BSON Primitive
    /// - Throws: DecodingError if conversion fails
    /// Converts Swift type to BSON Primitive
    /// - Parameters:
    ///   - value: The Swift value to convert
    ///   - keyPath: The current path in the JSON structure (for error reporting)
    /// - Returns: A BSON Primitive
    /// - Throws: DecodingError if conversion fails
    private func convertToPrimitive(_ value: Any, keyPath: [String]) throws -> Primitive {
        switch value {
        case is NSNull:
            return Null()
            
        case let stringValue as String:
            return stringValue
            
        case let boolValue as Bool:
            return boolValue
            
        case let intValue as UInt64:
            if intValue <= UInt64(Int32.max) {
                return Int32(intValue)
            } else if intValue <= UInt64(Int64.max) {
                #if (arch(i386) || arch(arm)) && BSONInt64Primitive
                // Int64 conforms to Primitive here
                return Int64(intValue)
                #else
                // Int conforms to Primitive, but Int64 doesn't
                if intValue <= UInt64(Int.max) {
                    return Int(intValue)
                } else {
                    return Int.max // Or handle overflow differently
                }
                #endif
            } else {
                #if (arch(i386) || arch(arm)) && BSONInt64Primitive
                return Int64.max
                #else
                return Int.max
                #endif
            }
            
        case let doubleValue as Double:
            return doubleValue
            
        case let tupleArray as [(key: String, value: Any)]:
            // Check if this is an extended JSON wrapper object with a single key starting with $
            if tupleArray.count == 1, let first = tupleArray.first, first.key.hasPrefix("$") {
                // Check if the value is another tuple array that needs to be converted to a document first
                if let nestedTuples = first.value as? [(key: String, value: Any)] {
                    // Convert the nested tuples to a document before handling the extended JSON
                    let nestedDoc = try convertJSONToDocument(nestedTuples, keyPath: keyPath + [first.key])
                    return handleExtendedJSON(key: first.key, value: nestedDoc, keyPath: keyPath)
                }
                
                // Handle non-nested values directly
                return handleExtendedJSON(key: first.key, value: first.value, keyPath: keyPath)
            }
            
            // Regular document
            return try convertJSONToDocument(tupleArray, keyPath: keyPath)
            
        case let dictionary as [String: Any]:
            // Check if this is an extended JSON wrapper object
            if dictionary.count == 1, let (key, value) = dictionary.first, key.hasPrefix("$") {
                return handleExtendedJSON(key: key, value: value, keyPath: keyPath)
            }
            
            // Regular document - convert to array of tuples to maintain consistency
            let tuples = dictionary.map { (key: $0.key, value: $0.value) }
            return try convertJSONToDocument(tuples, keyPath: keyPath)
            
        case let arrayValue as [Any]:
            // Process array elements into a BSON array
            var bsonArray = [] as Document
            for (index, element) in arrayValue.enumerated() {
                let key = "\(index)" // BSON arrays use string indices as keys
                bsonArray[key] = try convertToPrimitive(element, keyPath: keyPath + [key])
            }
            return bsonArray
            
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: keyPath.map { AnyCodingKey(stringValue: $0)! },
                    debugDescription: "Unsupported type: \(type(of: value))"
                )
            )
        }
    }
    
    private func handleExtendedJSON(key: String, value: Any, keyPath: [String]) -> Primitive {
        switch key {
        case "$numberInt", "$numberLong":
            if let stringValue = value as? String {
                if let intValue = Int32(stringValue) {
                    return intValue
                }
            }
            
        case "$numberDouble":
            if let stringValue = value as? String, let doubleValue = Double(stringValue) {
                return doubleValue
            }
            
        case "$oid":
            if let stringValue = value as? String, let objectId = ObjectId(stringValue) {
                return objectId
            }
            
        case "$numberDecimal":
            if let stringValue = value as? String {
                do {
                    let value = try BSONDecimal128(stringValue)
                    return Decimal128(low: value.rawValue.low.byteSwapped, high: value.rawValue.high.byteSwapped)
                } catch {
                    return "NaN"
                }
            }
            
        case "$date":
            if let dateString = value as? String {
                // First try with milliseconds precision
                if let date = ExtendedJSONDecoder.extJSONDateFormatterMilliseconds.date(from: dateString) {
                    return date
                }
                // Then try with seconds precision
                else if let date = ExtendedJSONDecoder.extJSONDateFormatterSeconds.date(from: dateString) {
                    return date
                }
            }
            // Handle nested $numberLong in $date
            else if let tupleArray = value as? [(key: String, value: Any)],
                    tupleArray.count == 1,
                    let first = tupleArray.first,
                    first.key == "$numberLong",
                    let millisString = first.value as? String,
                    let millis = Int64(millisString) {
                return Date(timeIntervalSince1970: Double(millis) / 1000)
            }
            
        case "$timestamp":
            if let timestampDoc = value as? Document {
                if let t = timestampDoc["t"] as? Int32,
                   let i = timestampDoc["i"] as? Int32 {
                    return Timestamp(increment: i, timestamp: t)
                }
            }
            
        case "$binary":
            if let tupleArray = value as? [(key: String, value: Any)] {
                var base64String: String? = nil
                var subTypeString: String? = nil
                
                for (subKey, subValue) in tupleArray {
                    if subKey == "base64", let str = subValue as? String {
                        base64String = str
                    } else if subKey == "subType", let str = subValue as? String {
                        subTypeString = str
                    }
                }
                
                if let base64 = base64String,
                   let subTypeHex = subTypeString,
                   let subTypeInt = UInt8(subTypeHex, radix: 16),
                   let data = Data(base64Encoded: base64) {
                    
                    // Create a ByteBuffer
                    let allocator = ByteBufferAllocator()
                    var buffer = allocator.buffer(capacity: data.count)
                    buffer.writeBytes(data)
                    
                    // Create SubType enum value
                    let subType: Binary.SubType
                    switch subTypeInt {
                    case 0x00: subType = .generic
                    case 0x01: subType = .function
                    case 0x04: subType = .uuid
                    case 0x05: subType = .md5
                    default: subType = .userDefined(subTypeInt)
                    }
                    
                    return Binary(subType: subType, buffer: buffer)
                }
            }
            
        case "$regex":
            if let tupleArray = value as? [(key: String, value: Any)] {
                var pattern: String? = nil
                var options: String? = nil
                
                for (subKey, subValue) in tupleArray {
                    if subKey == "pattern", let str = subValue as? String {
                        pattern = str
                    } else if subKey == "options", let str = subValue as? String {
                        options = str
                    }
                }
                
                if let pat = pattern, let opt = options {
                    return RegularExpression(pattern: pat, options: opt)
                }
            }
            
        case "$minKey":
            return MinKey()
            
        case "$maxKey":
            return MaxKey()
            
        case "$code":
            if let codeString = value as? String {
                return JavaScriptCode(codeString)
            }
            
        default:
            break
        }
        
        return "Invalid \(key) format with value of type \(type(of: value))"
    }
}


// Extension to Document to add fromJSON initializer
extension Document {
    /// Initialize a Document from Extended JSON
    /// - Parameter json: The JSON data in Extended JSON format
    /// - Throws: Error if JSON cannot be parsed or is invalid Extended JSON
    public init(fromJSON json: Data) throws {
        let decoder = ExtendedJSONDecoder()
        let document = try decoder.decodeDocument(from: json)
        self = document
    }
    
    /// Initialize a Document from Extended JSON string
    /// - Parameter jsonString: The JSON string in Extended JSON format
    /// - Throws: Error if JSON cannot be parsed or is invalid Extended JSON
    public init(fromJSON jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to convert JSON string to data"
                )
            )
        }
        try self.init(fromJSON: data)
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
