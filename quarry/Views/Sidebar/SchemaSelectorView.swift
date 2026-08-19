//
//  SchemaSelectorView.swift
//  Quarry
//
//  Created by Claude on 8/23/25.
//

import SwiftUI

struct SchemaSelectorView: View {
    @Environment(ConnectionInstance.self) private var instance
    @State private var availableSchemas: [String] = []
    @State private var selectedSchema: String = ""
    @State private var isLoadingSchemas: Bool = false
    
    var onSchemaSelected: (String) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(availableSchemas, id: \.self) { schema in
                    Button(schema) {
                        selectedSchema = schema
                        onSchemaSelected(schema)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Schema")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(selectedSchema.isEmpty ? "Select Schema" : selectedSchema)
                        .font(.system(size: 12))
                        .foregroundColor(selectedSchema.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                }
            }
            .buttonStyle(SchemaDropdownStyle())
        }
        .padding(.bottom, 8)
        .onChange(of: instance.connectionStatus) { _, _ in
            loadAvailableSchemas()
        }
    }
    
    private func loadAvailableSchemas() {
        Task {
            await MainActor.run {
                isLoadingSchemas = true
            }
            
            do {
                let schemas = try await fetchSchemas()
                await MainActor.run {
                    availableSchemas = schemas
                    // Only update selectedSchema if it's empty or not in the new schema list
                    if selectedSchema.isEmpty || !schemas.contains(selectedSchema) {
                        // Always prefer "public" as default if available, otherwise use first schema
                        selectedSchema = schemas.contains("public") ? "public" : (schemas.first ?? "")
                        if !selectedSchema.isEmpty {
                            onSchemaSelected(selectedSchema)
                        }
                    }
                    isLoadingSchemas = false
                }
            } catch {
                await MainActor.run {
                    // Provide appropriate fallback based on database type
                    let fallbackSchema = getFallbackSchema()
                    availableSchemas = [fallbackSchema]
                    if selectedSchema.isEmpty {
                        selectedSchema = fallbackSchema
                        onSchemaSelected(fallbackSchema)
                    }
                    isLoadingSchemas = false
                }
                debugLog("Failed to load schemas: \(error)")
            }
        }
    }
    
    private func getFallbackSchema() -> String {
        guard let databaseType = instance.databaseType else {
            return "default"
        }
        
        switch databaseType {
        case .postgres, .supabase:
            return "public"
        case .mysql:
            return instance.connectedDatabase?.name ?? "mysql"
        case .sqlite:
            return "main"
        default:
            return "default"
        }
    }
    
    private func fetchSchemas() async throws -> [String] {
        guard let databaseType = instance.databaseType else {
            return ["public"]
        }
        
        switch databaseType {
        case .postgres, .supabase:
            let schemas = try await instance.databaseService.getInformationSchema()
            return schemas.map { $0.name }
        case .mysql:
            return try await fetchMySQLSchemas()
        case .sqlite:
            return ["main"]
        default:
            return ["default"]
        }
    }
    
    
    private func fetchMySQLSchemas() async throws -> [String] {
        do {
            let result = try await instance.databaseService.findDocuments(
                in: "information_schema.schemata",
                databaseSchema: "public",
                filter: "",
                skip: 0,
                limit: 100,
                sortBy: "schema_name",
                ascending: true
            )
            
            var schemas: [String] = []
            for row in result.rawRows {
                if let schemaName = row["schema_name"] as? String {
                    // Filter out system schemas
                    if !["information_schema", "performance_schema", "mysql", "sys"].contains(schemaName) {
                        schemas.append(schemaName)
                    }
                }
            }
            
            return schemas.isEmpty ? [instance.connectedDatabase?.name ?? ""].filter { !$0.isEmpty } : schemas
        } catch {
            debugLog("Error fetching MySQL schemas: \(error)")
            return [instance.connectedDatabase?.name ?? ""].filter { !$0.isEmpty }
        }
    }
}
