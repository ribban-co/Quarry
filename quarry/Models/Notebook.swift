//
//  Notebook.swift
//  Quarry
//

import SwiftData
import SwiftUI

enum NotebookStatus: String, Codable, CaseIterable {
    case exploratory = "Exploratory"
    case inProgress = "In Progress"
    case approved = "Approved"
    case endorsed = "Endorsed"

    var nsColor: NSColor {
        switch self {
        case .exploratory: NSColor(red: 0.58, green: 0.44, blue: 0.72, alpha: 1)
        case .inProgress: NSColor(red: 0.4, green: 0.56, blue: 0.75, alpha: 1)
        case .approved: NSColor(red: 0.42, green: 0.65, blue: 0.52, alpha: 1)
        case .endorsed: NSColor(red: 0.82, green: 0.6, blue: 0.4, alpha: 1)
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}

@Model
final class Notebook {
    var id: UUID = UUID()
    var title: String = "Untitled Notebook"
    var descriptionText: String = ""
    var status: NotebookStatus = NotebookStatus.exploratory
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPublished: Bool = false
    var lastRefreshedAt: Date?

    init(title: String = "Untitled Notebook", description: String = "", status: NotebookStatus = .exploratory) {
        self.title = title
        self.descriptionText = description
        self.status = status
    }
}
