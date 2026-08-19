//
//  DocumentFormatter.swift
//  Collection
//
//  Created by Fauzaan on 1/5/25.
//
import MongoKitten
import SwiftUI
import UInt128

struct FormattedPrimitive {
    let value: String
    let color: Color
    let isExpandable: Bool
    let type: String
}

extension MongoFormattedColorToken {
    var color: Color {
        switch self {
        case .primary:
            .primary
        case .secondary:
            .secondary
        case .gray:
            .gray
        case .orange:
            .orange
        case .purple:
            .purple
        case .cyan:
            .cyan
        case .green:
            .green
        case .blue:
            .blue
        case .white:
            .white
        }
    }
}

extension MongoFormattedPrimitivePayload {
    var formattedPrimitive: FormattedPrimitive {
        FormattedPrimitive(
            value: value,
            color: colorToken.color,
            isExpandable: isExpandable,
            type: type
        )
    }
}

extension Document {
    func formatValue(_ value: Primitive?) -> FormattedPrimitive {
        formatValuePayload(value).formattedPrimitive
    }

    func formatValuePayload(_ value: Primitive?) -> MongoFormattedPrimitivePayload {
        guard let value = value else {
            return MongoFormattedPrimitivePayload(
                value: "null",
                colorToken: .gray,
                isExpandable: false,
                type: "Null"
            )
        }

        switch value {
        case let objectId as ObjectId:
            return MongoFormattedPrimitivePayload(
                value: "ObjectId(\"\(objectId.hexString)\")",
                colorToken: .orange,
                isExpandable: false,
                type: "ObjectId"
            )

        case let array as [Primitive]:
            return MongoFormattedPrimitivePayload(
                value: "Array (\(array.count))",
                colorToken: .secondary,
                isExpandable: !array.isEmpty,
                type: "Array"
            )

        case is Null:
            return MongoFormattedPrimitivePayload(
                value: "null",
                colorToken: .gray,
                isExpandable: false,
                type: "Null"
            )

        case let value as Timestamp:
            return MongoFormattedPrimitivePayload(
                value: "\(value)",
                colorToken: .purple,
                isExpandable: false,
                type: "Timestamp"
            )

        case let value as JavaScriptCode:
            return MongoFormattedPrimitivePayload(
                value: "\(value)",
                colorToken: .cyan,
                isExpandable: false,
                type: "JavaScriptCode"
            )

        case let binary as Binary:
            if binary.subType == .uuid {
                return MongoFormattedPrimitivePayload(
                    value: extractUUIDFromBinary(binary)?.uuidString ?? "Invalid UUID",
                    colorToken: .cyan,
                    isExpandable: false,
                    type: "Binary"
                )
            }

            return MongoFormattedPrimitivePayload(
                value: "Binary.createFromBase64(\(binary.data.base64EncodedString()),  \(binary.subType))",
                colorToken: .cyan,
                isExpandable: false,
                type: "Binary"
            )

        case let date as Date:
            return MongoFormattedPrimitivePayload(
                value: date.ISO8601Format(),
                colorToken: .purple,
                isExpandable: false,
                type: "Date"
            )

        case let bool as Bool:
            return MongoFormattedPrimitivePayload(
                value: bool.description,
                colorToken: .green,
                isExpandable: false,
                type: "Boolean"
            )

        case let doc as Document:
            return MongoFormattedPrimitivePayload(
                value: doc.isArray ? "Array (\(doc.count))" : "Object",
                colorToken: .secondary,
                isExpandable: !doc.isEmpty,
                type: doc.isArray ? "Array" : "Object"
            )

        case let string as String:
            return MongoFormattedPrimitivePayload(
                value: "\"\(string)\"",
                colorToken: .green,
                isExpandable: false,
                type: "String"
            )

        case let number as Int:
            return numberPayload(number, type: "Int")
        case let number as Int32:
            return numberPayload(number, type: "Int32")
        case let number as Double:
            return numberPayload(number, type: "Double")
        case let number as BSON.Decimal128:
            return MongoFormattedPrimitivePayload(
                value: String(describing: number.toString),
                colorToken: .blue,
                isExpandable: false,
                type: "Number"
            )
        default:
            return MongoFormattedPrimitivePayload(
                value: String(describing: value),
                colorToken: .white,
                isExpandable: false,
                type: "String"
            )
        }
    }

    func formattedPayload() -> MongoFormattedDocumentPayload {
        let id: String
        if let objectId = self["_id"] as? ObjectId {
            id = objectId.hexString
        } else {
            id = ""
        }

        let fields = keys.map { key in
            formatFieldPayload(key: key, value: self[key])
        }

        return MongoFormattedDocumentPayload(
            id: id,
            jsonString: jsonString,
            fields: fields
        )
    }

    private func formatFieldPayload(key: String, value: Primitive?) -> MongoFormattedFieldPayload {
        let formatted = formatValuePayload(value)

        var nestedFields: [MongoFormattedFieldPayload]?
        if let doc = value as? Document {
            nestedFields = doc.keys.map { nestedKey in
                formatFieldPayload(key: nestedKey, value: doc[nestedKey])
            }
        }

        return MongoFormattedFieldPayload(
            key: key,
            formattedValue: formatted,
            nestedFields: nestedFields
        )
    }

    private func numberPayload(_ number: Any, type: String) -> MongoFormattedPrimitivePayload {
        MongoFormattedPrimitivePayload(
            value: String(describing: number),
            colorToken: .blue,
            isExpandable: false,
            type: type
        )
    }
    
    func extractUUIDFromBinary(_ binary: Binary) -> UUID? {
        guard binary.subType == .uuid, binary.count == 16 else {
            return nil
        }
        
        return binary.storage.withUnsafeReadableBytes { buffer in
            guard buffer.count == 16 else { return nil }
            let bytes = buffer.bindMemory(to: UInt8.self)
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }
    }
}





    extension Binary.SubType {
        public static func == (lhs: Binary.SubType, rhs: Binary.SubType) -> Bool {
            switch (lhs, rhs) {
            case (.generic, .generic), (.function, .function), (.uuid, .uuid), (.md5, .md5):
                return true
            case (.userDefined(let lhsByte), .userDefined(let rhsByte)):
                return lhsByte == rhsByte
            default:
                return false
            }
        }
    }
