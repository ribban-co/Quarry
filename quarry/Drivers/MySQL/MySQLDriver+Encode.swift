//
//  MySQLDriver+Encode.swift
//  Quarry
//
//  Created by Fauzaan on 21/8/25.
//

import Foundation
import MySQLNIO
import NIOCore

extension MySQLDriver {
    /// Helper method to convert Swift types to MySQL bindable values
    func convertToMySQLBindable(_ value: DatabaseValue) -> MySQLData {
        switch value {
        case .null:
            return MySQLData.null
        case .string(let stringValue), .decimalString(let stringValue), .objectID(let stringValue):
            return MySQLData(string: stringValue)
        case .int(let intValue):
            return MySQLData(int: intValue)
        case .int64(let intValue):
            return MySQLData(int: Int(clamping: intValue))
        case .double(let doubleValue):
            return MySQLData(double: doubleValue)
        case .bool(let boolValue):
            return MySQLData(bool: boolValue)
        case .date(let dateValue):
            return MySQLData(date: dateValue)
        case .data(let dataValue):
            var buffer = ByteBufferAllocator().buffer(capacity: dataValue.count)
            buffer.writeBytes(dataValue)
            return MySQLData(
                type: .blob,
                format: .binary,
                buffer: buffer,
                isUnsigned: false
            )
        case .uuid(let value):
            return MySQLData(string: value.uuidString)
        case .array, .object:
            return MySQLData(string: value.description)
        }
    }
}
