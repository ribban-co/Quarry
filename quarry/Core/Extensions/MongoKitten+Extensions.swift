//
//  MongoKitten+Extensions.swift
//  Collection
//
//  Created by Fauzaan on 1/1/25.
//
import Foundation
import MongoKitten

extension Document {
    func documentToJSON(_ document: Document) throws -> Data {
        var jsonDict = [String: Any]()
        
        for (key, value) in document {
            switch value {
            case let objectId as ObjectId:
                jsonDict[key] = ["$oid": objectId.hexString]
                
            case let date as Date:
                jsonDict[key] = ["$date": date.ISO8601Format()]
                
            case let decimal as BSON.Decimal128:
                jsonDict[key] = ["$numberDecimal": decimal.toString]
                
            case let number as Int:
                jsonDict[key] = number
            case let number as Int32:
                jsonDict[key] = number
            case let number as Double:
                jsonDict[key] = number
                
            case let string as String:
                // Check if the string could be an ObjectId (for fields like "category")
                if string.count == 24 && string.range(of: "^[0-9a-f]{24}$", options: .regularExpression) != nil {
                    // Likely an ObjectId stored as string
                    jsonDict[key] = ["$oid": string]
                } else {
                    jsonDict[key] = string
                }
                
            case is Null:
                jsonDict[key] = NSNull()
                
            case let document as Document:
                if document.isArray {
                    var arrayElements = [Any]()
                    for i in 0..<document.count {
                        if let element = document[String(i)] {
                            arrayElements.append(convertPrimitive(element))
                        }
                    }
                    jsonDict[key] = arrayElements
                } else {
                    let nestedDict = try documentToJSON(document)
                    jsonDict[key] = try JSONSerialization.jsonObject(with: nestedDict, options: [])
                }
                
            case let array as [Primitive]:
                jsonDict[key] = array.map { convertPrimitive($0) }
                
            default:
                jsonDict[key] = String(describing: value)
            }
        }
        
        return try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted])
    }

    func convertPrimitive(_ primitive: Primitive) -> Any {
        switch primitive {
        case let objectId as ObjectId:
            return ["$oid": objectId.hexString]
            
        case let date as Date:
            return ["$date": date.ISO8601Format()]
            
        case let decimal as BSON.Decimal128:
            return ["$numberDecimal": decimal.toString]
            
        case let number as Int:
            return number
        case let number as Int32:
            return number
        case let number as Double:
            return number
            
        case let string as String:
            // Check if the string could be an ObjectId
            if string.count == 24 && string.range(of: "^[0-9a-f]{24}$", options: .regularExpression) != nil {
                // Likely an ObjectId stored as string
                return ["$oid": string]
            } else {
                return string
            }
            
        case is Null:
            return NSNull()
            
        case let document as Document:
            if document.isArray {
                var arrayElements = [Any]()
                for i in 0..<document.count {
                    if let element = document[String(i)] {
                        arrayElements.append(convertPrimitive(element))
                    }
                }
                return arrayElements
            } else {
                var dict = [String: Any]()
                for (key, value) in document {
                    dict[key] = convertPrimitive(value)
                }
                return dict
            }
            
        case let array as [Primitive]:
            return array.map { convertPrimitive($0) }
            
        default:
            return String(describing: primitive)
        }
    }
}



// SwiftUI in the macOS 27 SDK declares its own `Document` protocol, which makes the
// unqualified BSON type ambiguous. A module-scope alias wins over both imports.
typealias Document = BSON.Document
