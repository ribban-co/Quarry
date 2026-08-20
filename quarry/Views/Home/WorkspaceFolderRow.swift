//
//  WorkspaceFolderRow.swift
//  Quarry
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let quarryWorkspaceItem = UTType(exportedAs: "se.ribban.quarry.workspace-item")
}

/// Drag payload for filing workspace items. Carries the `WorkspaceItem.id`
/// rather than the model so it stays Sendable across the drag session.
struct WorkspaceItemTransfer: Codable, Transferable, Sendable {
    let itemId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .quarryWorkspaceItem)
    }
}

/// Collapsible header for one folder. Owns its hover/drop affordances; the
/// list above it owns expansion state and the children it renders.
struct WorkspaceFolderRow: View {
    let folder: WorkspaceFolder
    let itemCount: Int
    let isExpanded: Bool
    let isRenaming: Bool
    let isDropTargeted: Bool
    let onToggle: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void
    let onPickColor: (ConnectionColor) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var tint: Color { folder.color.color }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: isExpanded ? "folder" : "folder.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(tint)
                )

            if isRenaming {
                TextField("Folder name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($isNameFocused)
                    .onSubmit { onCommitRename(draftName) }
                    .onExitCommand(perform: onCancelRename)
                    .frame(maxWidth: 240, alignment: .leading)
            } else {
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Text("\(itemCount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(.separatorColor).opacity(0.35))
                )

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(.rect)
        .background(rowBackground)
        .padding(.horizontal, -10)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .onTapGesture { if !isRenaming { onToggle() } }
        .onChange(of: isRenaming, initial: true) { _, renaming in
            guard renaming else { return }
            draftName = folder.name
            isNameFocused = true
        }
        .onChange(of: isNameFocused) { wasFocused, isFocused in
            // Clicking away is a commit, not a cancel — matches Finder.
            if wasFocused, !isFocused, isRenaming {
                onCommitRename(draftName)
            }
        }
        .contextMenu {
            Button {
                onBeginRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Menu {
                ForEach(ConnectionColor.allCases, id: \.self) { color in
                    Button {
                        onPickColor(color)
                    } label: {
                        HStack {
                            if folder.color == color {
                                Image(systemName: "checkmark")
                            }
                            Text(color.displayName)
                        }
                    }
                }
            } label: {
                Label("Color", systemImage: "paintpalette")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(dropFill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isDropTargeted ? tint.opacity(0.8) : .clear, lineWidth: 1.5)
            )
    }

    private var dropFill: Color {
        if isDropTargeted { return tint.opacity(0.12) }
        return isHovering ? Color(.separatorColor).opacity(0.35) : .clear
    }
}

/// Compact drag proxy — the full-width row makes an unreadable drag image.
struct WorkspaceDragPreview: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        )
    }
}

/// Context-menu submenu for filing a single item, shared by connection and
/// notebook rows.
struct WorkspaceMoveToFolderMenu: View {
    let folders: [WorkspaceFolder]
    let currentFolderId: UUID?
    let onMove: (UUID?) -> Void
    let onMoveToNewFolder: () -> Void

    var body: some View {
        Menu {
            ForEach(folders) { folder in
                Button {
                    onMove(folder.id)
                } label: {
                    HStack {
                        if currentFolderId == folder.id {
                            Image(systemName: "checkmark")
                        }
                        Text(folder.name)
                    }
                }
            }

            if !folders.isEmpty {
                Divider()
            }

            Button {
                onMoveToNewFolder()
            } label: {
                Label("New Folder…", systemImage: "folder.badge.plus")
            }

            if currentFolderId != nil {
                Button {
                    onMove(nil)
                } label: {
                    Label("Remove from Folder", systemImage: "folder.badge.minus")
                }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
    }
}
