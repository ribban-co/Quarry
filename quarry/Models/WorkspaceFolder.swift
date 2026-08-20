//
//  WorkspaceFolder.swift
//  Quarry
//

import SwiftData
import SwiftUI

/// A user-created group in the Home workspace list. Membership lives on the
/// items themselves (`folderId`) so deleting a folder never risks the item.
@Model
final class WorkspaceFolder {
    var id: UUID = UUID()
    var name: String = "New Folder"
    var colorRawValue: String = ConnectionColor.blue.rawValue
    var sortIndex: Int = 0
    var isExpanded: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var color: ConnectionColor {
        get { ConnectionColor(rawValue: colorRawValue) ?? .blue }
        set {
            colorRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    init(name: String = "New Folder", color: ConnectionColor = .blue, sortIndex: Int = 0) {
        self.name = name
        self.colorRawValue = color.rawValue
        self.sortIndex = sortIndex
    }
}
