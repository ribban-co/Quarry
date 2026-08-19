//
//  RowDetailField.swift
//  Quarry
//
//  Created by Claude on 1/21/26.
//

import SwiftUI

struct RowDetailField: View {
    let columnName: String
    let rowInfo: QueryRowInfo
    let isEditing: Bool
    @Binding var editedValue: String

    private var isNull: Bool {
        rowInfo.value == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(columnName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(rowInfo.dataType)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if isEditing {
                TextField("", text: $editedValue, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1...50)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
            } else {
                Text(displayValue)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isNull ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .quaternarySystemFill))
                    .clipShape(.rect(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var displayValue: String {
        guard let value = rowInfo.value else {
            return "NULL"
        }

        switch value {
        case .null:
            return "NULL"
        case .string(let stringValue), .decimalString(let stringValue), .objectID(let stringValue):
            return stringValue.isEmpty ? "(empty)" : stringValue
        case .int(let intValue):
            return String(intValue)
        case .int64(let intValue):
            return String(intValue)
        case .double(let doubleValue):
            return doubleValue.formatted()
        case .bool(let boolValue):
            return boolValue ? "true" : "false"
        case .date(let dateValue):
            return dateValue.formatted(date: .abbreviated, time: .standard)
        case .array(let arrayValue):
            return formatJSON(arrayValue.map(jsonCompatibleValue))
        case .object(let objectValue):
            return formatJSON(objectValue.mapValues(jsonCompatibleValue))
        case .uuid(let uuidValue):
            return uuidValue.uuidString
        case .data(let dataValue):
            return dataValue.base64EncodedString()
        }
    }

    private func formatJSON(_ value: Any) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? String(describing: value)
        } catch {
            return String(describing: value)
        }
    }

    private func jsonCompatibleValue(_ value: DatabaseValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .int64(let value):
            return value
        case .double(let value):
            return value
        case .string(let value), .decimalString(let value), .objectID(let value):
            return value
        case .date(let value):
            return value.ISO8601Format()
        case .data(let value):
            return value.base64EncodedString()
        case .uuid(let value):
            return value.uuidString
        case .array(let values):
            return values.map(jsonCompatibleValue)
        case .object(let values):
            return values.mapValues(jsonCompatibleValue)
        }
    }
}
