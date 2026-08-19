//
//  QueryOperators.swift
//  Quarry
//
//  Created by Fauzaan on 4/15/25.
//
import Foundation
import MongoKitten

struct MongoKittenQueryHandler {
    /// Serializes a MongoDB document, handling special BSON types
    static func serialize(document: Document) -> Primitive {
        var base = Document()
        
        for (key, value) in document {
            if key == "$oid" {
                if let oidString = value as? String,
                   let objectId = ObjectId(oidString) {
                    return objectId
                }
            } else if key == "$date" {
                if let dateValue = parseDate(value) {
                    return dateValue
                }
            } else {
                base[key] = serializeValue(value)
            }
        }
        
        return base
    }
    
    /// Recursively serializes a Primitive value
    static func serializeValue(_ value: Primitive) -> Primitive {
        switch value {
        case let document as Document:
            return serialize(document: document)
        default:
            return value
        }
    }
    
    /// Parses various date formats from MongoDB
    private static func parseDate(_ value: Primitive) -> Date? {
        // Handle string date format
        if let dateString = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateString)
        }
        
        // Handle numeric timestamp (milliseconds since epoch)
        if let timeInterval = value as? Double {
            return Date(timeIntervalSince1970: timeInterval / 1000.0)
        }
        
        return nil
    }
}


