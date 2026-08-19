//
//  DefinitionModeView.swift
//  Quarry
//
//  Created by Fauzaan on 10/15/25.
//

import SwiftUI
import LanguageSupport

struct DefinitionModeView: View {
    let schema: DatabaseSchemaResult?
    let tableName: String
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @Environment(\.colorScheme) var colorScheme

    private var schemaDefinition: String {
        guard let schema = schema else {
            return "// No schema information available"
        }

        return generateJSONDefinition(from: schema)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Table Definition")
                    .font(.headline)
                    .padding(.leading, 16)
                Spacer()
                Text("Read-only")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 8)
            .background(
                colorScheme == .dark ? Color(.black).opacity(0.2) : Color(.gray).opacity(0.1)
            )

            Divider()

            // Code editor
//            CodeEditor(
//                text: .constant(schemaDefinition),
//                position: $position,
//                messages: .constant(Set()),
//                language: .json()
//            )
//            .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
//            .disabled(true)
        }
    }

    private func generateJSONDefinition(from schema: DatabaseSchemaResult) -> String {
        let json: [String: Any] = [
            "tableName": tableName,
            "schemaName": schema.schemaName,
            "columnCount": schema.columnCount,
            "columns": schema.columns.map { column in
                var columnDict: [String: Any] = [
                    "name": column.columnName,
                    "type": column.dataType,
                    "nullable": column.isNullable == "YES"
                ]

                if let position = column.ordinalPosition {
                    columnDict["position"] = position
                }

                if let defaultValue = column.columnDefault {
                    columnDict["default"] = defaultValue
                }

                if column.isPrimaryKey {
                    columnDict["primaryKey"] = true
                }

                if !column.constraints.isEmpty {
                    columnDict["constraints"] = column.constraints.map { constraint in
                        var constraintDict: [String: Any] = [
                            "type": constraint.type.rawValue,
                            "name": constraint.name
                        ]

                        if let refTable = constraint.referencedTable {
                            constraintDict["referencedTable"] = refTable
                        }

//                        if let refColumn = constraint.referencedColumn {
//                            constraintDict["referencedColumn"] = refColumn
//                        }

                        if let definition = constraint.definition {
                            constraintDict["definition"] = definition
                        }

                        return constraintDict
                    }
                }

                if let comment = column.comment {
                    columnDict["comment"] = comment
                }

                if let precision = column.numericPrecision {
                    columnDict["numericPrecision"] = precision
                }

                if let scale = column.numericScale {
                    columnDict["numericScale"] = scale
                }

                if let length = column.dataLength {
                    columnDict["dataLength"] = length
                }

                return columnDict
            }
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8) ?? "Error generating JSON"
        } catch {
            return "Error generating JSON: \(error.localizedDescription)"
        }
    }
}
