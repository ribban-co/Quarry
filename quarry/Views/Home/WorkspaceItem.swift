//
//  WorkspaceItem.swift
//  Quarry
//

import SwiftUI

enum WorkspaceItem: Identifiable {
    case connection(Connection)
    case notebook(Notebook)

    var id: String {
        switch self {
        case .connection(let c): "c-\(c.keychainId)"
        case .notebook(let n): "n-\(n.id.uuidString)"
        }
    }

    var name: String {
        switch self {
        case .connection(let c): c.name
        case .notebook(let n): n.title
        }
    }

    var lastAccessedAt: Date {
        switch self {
        case .connection(let c): c.lastOpenedAt
        case .notebook(let n): n.updatedAt
        }
    }

    var createdAt: Date {
        switch self {
        case .connection(let c): c.createdAt
        case .notebook(let n): n.createdAt
        }
    }

    var updatedAt: Date {
        switch self {
        case .connection(let c): c.updatedAt
        case .notebook(let n): n.updatedAt
        }
    }

    var lastViewedAt: Date {
        switch self {
        case .connection(let c): c.lastOpenedAt
        case .notebook(let n): n.updatedAt
        }
    }

    var subtitle: String? {
        switch self {
        case .connection(let c):
            if c.databaseType == .convex, let hostname = c.hostname {
                return "ID: \(hostname)"
            }
            return c.displayUrl
        case .notebook(let n):
            return n.descriptionText.isEmpty ? nil : n.descriptionText
        }
    }

    var kindLabel: String {
        switch self {
        case .connection(let c): c.databaseType.displayName
        case .notebook: "Notebook"
        }
    }

    var searchTokens: String {
        [name, subtitle ?? "", kindLabel, itemTypeKeyword]
            .joined(separator: " ")
    }

    private var itemTypeKeyword: String {
        switch self {
        case .connection: "connection"
        case .notebook: "notebook"
        }
    }
}
