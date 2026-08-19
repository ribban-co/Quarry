//
//  ConnectionDetailsPopover.swift
//  Quarry
//
//  Created by Fauzaan on 8/2/25.
//

import SwiftUI

struct ConnectionDetailsPopover: View {
    let connection: Connection?
    let databaseType: DatabaseType
    let environment: ConnectionEnvironment?
    let version: String?
    let connectedDatabase: String?
    let onDisconnect: () async -> Void
    let onReconnect: () async -> Void
    let onEdit: () -> Void
    @Environment(ConnectionInstance.self) private var instance
    
    private var connectionURL: String {
        connection?.displayUrl ?? ""
    }
    
    private var hostname: String {
        // For Convex, use the deployment URL from the driver if available
        if databaseType == .convex,
           let deploymentUrl = instance.databaseService.getCurrentDeploymentUrl(),
           let url = URL(string: deploymentUrl) {
            return url.host ?? deploymentUrl
        }

        // For other database types, use the stored connection URL
        guard let url = URL(string: connectionURL) else { return connectionURL }
        return url.host ?? connectionURL
    }
    
    private var port: String {
        guard let url = URL(string: connectionURL) else { return "Unknown" }
        if let port = url.port {
            return String(port)
        }
        // Default ports based on database type
        switch databaseType {
        case .postgres, .supabase, .convex, .sqlite:
            return "5432"
        case .mysql:
            return "3306"
        case .mongodb:
            return "27017"
        case .redis:
            return "6379"
        }
    }
    
    private var username: String {
        guard let url = URL(string: connectionURL) else { return "Unknown" }
        return url.user ?? "Unknown"
    }
    
    private var databaseName: String {
        connectedDatabase ?? connection?.defaultDatabase ?? "Default"
    }
    
    private var driverWithVersion: String {
        if let version = version {
            return "\(databaseType.displayName) \(version)"
        } else {
            return databaseType.displayName
        }
    }
    
    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                // Header with database type info
                HStack(spacing: 12) {
                    Image(databaseType.homeIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(databaseType.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection Details")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(connection?.name ?? "Unknown Connection")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Server Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("SERVER")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    VStack(spacing: 8) {
                        CompactDetailRow(label: "Host", value: hostname)
                        
                        // Only show port for network-based databases
                        if databaseType != .sqlite && databaseType != .convex {
                            CompactDetailRow(label: "Port", value: port)
                        }
                    }
                    .padding(16)
                    .background(Color(.controlColor).opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.separator, lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
                
                // Connection Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONNECTION")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    VStack(spacing: 8) {
                        CompactDetailRow(label: "Driver", value: driverWithVersion)
                        
                        CompactDetailRow(label: databaseType == .convex ? "Environment" : "Database", value: databaseName)
                        
                        // Only show username for network-based databases
                        if let username = connection?.username, databaseType != .convex {
                            CompactDetailRow(label: "Username", value: username)
                        }
                        
                        if let connectionEnvironment = environment?.rawValue {
                            CompactDetailRow(label: "Environment", value: connectionEnvironment)
                        }
                    }
                    .padding(16)
                    .background(Color(.controlColor).opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.separator, lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
                
                // Error Section
                if instance.connectionStatus == .error, let lastError = instance.lastError {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("LAST ERROR")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            Spacer()

                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(lastError.localizedDescription, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Copy error to clipboard")
                        }

                        Text(lastError.localizedDescription)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .opacity(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.red.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
                            )
                            .cornerRadius(12)
                    }
                }

                // Actions Section
                HStack(spacing: 8) {
                    Button("Disconnect") {
                        Task {
                            await onDisconnect()
                        }
                    }
                    .compactMenuButtonStyle()
                    
                    Spacer()
                    
                    if databaseType != .convex {
                        Button("Reconnect") {
                            Task {
                                await onReconnect()
                            }
                        }
                        .compactPrimaryStyle()
                    }
                    
                    Button("Edit") {
                        onEdit()
                    }
                    .compactMenuButtonStyle()
                }
            }
            .padding(20)
            .frame(minWidth: 350, maxWidth: 400)
            .textSelection(.enabled)
    }
}

// MARK: - Compact Detail Row
private struct CompactDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
        }
    }
}
