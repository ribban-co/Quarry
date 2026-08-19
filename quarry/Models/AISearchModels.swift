//
//  AISearchModels.swift
//  Collection
//
//  Created on 3/16/25.
//

import SwiftUI

// Filter suggestion for the autocomplete
public struct FilterSuggestion: Identifiable {
    public let id = UUID()
    public let text: String
    public let description: String
    public let icon: String
    public let shortcut: String
    
    public init(text: String, description: String, icon: String, shortcut: String) {
        self.text = text
        self.description = description
        self.icon = icon
        self.shortcut = shortcut
    }
}

// Component of a filter for syntax highlighting
public struct FilterComponent: Identifiable {
    public let id: Int
    public let text: String
    public let color: Color
    
    public init(id: Int, text: String, color: Color) {
        self.id = id
        self.text = text
        self.color = color
    }
}
