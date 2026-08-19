//
//  HoverActionButtons.swift
//  Collection
//
//  Created by Fauzaan on 3/8/25.
//
import SwiftUI

struct HoverActionButtons: View {
    let isVisible: Bool
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onClone: () -> Void
    let onDelete: () -> Void
    let showCopyFeedback: Bool
    let pendingAction: DocumentAction?
    let onSave: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    init(
        isVisible: Bool,
        onEdit: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onClone: @escaping () -> Void,
        showCopyFeedback: Bool = false,
        pendingAction: DocumentAction? = nil,
        onSave: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        self.isVisible = isVisible
        self.onEdit = onEdit
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.onClone = onClone
        self.showCopyFeedback = showCopyFeedback
        self.pendingAction = pendingAction
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        HStack(spacing: .zero) {
            if pendingAction == .delete {
                Button(action: onSave) {
                    Text("Delete")
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .buttonStyle(HoverActionButtonStyleText())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red.opacity(0.8))
                )
                .padding(.trailing, 4)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .tint(.red)
                }
                .buttonStyle(HoverActionButtonStyleText())

                Divider().frame(height: 12).padding(.horizontal, 4)

            } else if pendingAction == .update {
                Button(action: onSave) {
                    Text("Save")
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .buttonStyle(HoverActionButtonStyleText())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            colorScheme == .dark ? Color.black : Color.white)
                                    .opacity(0.3)
                )
                .padding(.trailing, 4)
                .keyboardShortcut("s", modifiers: .command)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .tint(.red)
                }
                .buttonStyle(HoverActionButtonStyleText())

                Divider().frame(height: 12).padding(.horizontal, 4)

            } else {
                ActionButton(
                    systemName: getActionIcon(for: .update),
                    action: onEdit,
                    tooltipText: getActionTooltip(for: .update),
                    tintColor: getActionColor(for: .update)
                )
            }

            ActionButton(
                systemName: showCopyFeedback ? "checkmark" : "clipboard",
                action: onCopy,
                tooltipText: "Copy to clipboard"
            )
            
//            TODO: Implement later
//            ActionButton(
//                systemName: "document.on.document",
//                action: onClone,
//                tooltipText: "Clone Document"
//            )
//            .customHelp("Clone Document", position: .top, spacing: 4)

            ActionButton(
                systemName: getActionIcon(for: .delete),
                action: onDelete,
                tooltipText: getActionTooltip(for: .delete),
                tintColor: getActionColor(for: .delete)
            )
        }
        .padding(3)
        .modifier(GlassBackgroundStyle())
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator)
        )
        .cornerRadius(6)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: pendingAction == .update)
        .padding(.bottom, -6)
        .padding(.trailing, 16)
    }
}

// You'll need to update your DocumentRow to use this:
// Helper extension for action-related UI
extension HoverActionButtons {
    func getActionIcon(for action: DocumentAction) -> String {
        if pendingAction == action {
            switch action {
            case .delete:
                return "trash.slash"
            case .update:
                return "pencil.line"
            }
        } else {
            switch action {
            case .delete:
                return "trash"
            case .update:
                return "pencil.line"
            }
        }
    }
    
    func getActionTooltip(for action: DocumentAction) -> String {
        if pendingAction == action {
            switch action {
            case .delete:
                return "Unmark for Deletion"
            case .update:
                return "Unmark for Update"
            }
        } else {
            switch action {
            case .delete:
                return "Mark for Deletion"
            case .update:
                return "Mark for Update"
            }
        }
    }
    
    func getActionColor(for action: DocumentAction) -> Color {
        if pendingAction == action {
            switch action {
            case .delete:
                return .red
            case .update:
                return .blue
            }
        } else {
            return .gray
        }
    }
}

struct ActionButton: View {
    let systemName: String
    let action: () -> Void
    let tooltipText: String
    let tintColor: Color
    @Environment(\.colorScheme) var colorScheme
    
    init(systemName: String, action: @escaping () -> Void, tooltipText: String, tintColor: Color = .gray) {
        self.systemName = systemName
        self.action = action
        self.tooltipText = tooltipText
        self.tintColor = tintColor
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10))
                .fontWeight(.bold)
                .foregroundColor(tintColor)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
 
        }
        .buttonStyle(HoverActionButtonStyle())
    }
}

