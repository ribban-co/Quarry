//
//  RecentsSection.swift
//  Quarry
//

import AppKit
import SwiftData
import SwiftUI

struct RecentsSection: View {
    let items: [WorkspaceItem]
    var containerBackedConnectionIds: Set<String> = []
    var stoppedContainerConnectionIds: Set<String> = []
    let onOpen: (WorkspaceItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var notebookToDelete: Notebook?
    @State private var showDeleteNotebook = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recents")
                .font(.system(size: 14, weight: .semibold))

            cardRow
        }
        .confirmationDialog(
            "Delete Notebook",
            isPresented: $showDeleteNotebook,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let notebook = notebookToDelete {
                    modelContext.delete(notebook)
                    notebookToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                notebookToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this notebook? This action cannot be undone.")
        }
        .dialogSeverity(.critical)
    }

    private var cardRow: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    cardForItem(item)
                        .frame(width: 200)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 28, for: .scrollContent)
        .padding(.horizontal, -28)
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 12)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 12)
            }
            .padding(.horizontal, -6)
        )
    }

    @ViewBuilder
    private func cardForItem(_ item: WorkspaceItem) -> some View {
        switch item {
        case .connection(let connection):
            let isContainerStopped = stoppedContainerConnectionIds.contains(connection.keychainId)
            RecentConnectionCard(
                connection: connection,
                isContainerBacked: containerBackedConnectionIds.contains(connection.keychainId),
                isContainerStopped: isContainerStopped
            ) {
                if !isContainerStopped {
                    onOpen(item)
                }
            }
        case .notebook(let notebook):
            RecentNotebookCard(
                notebook: notebook,
                onOpen: { onOpen(item) },
                onDelete: { nb in
                    notebookToDelete = nb
                    showDeleteNotebook = true
                }
            )
        }
    }
}

struct RecentCard<ContextMenu: View>: View {
    let item: WorkspaceItem
    var isContainerBacked: Bool = false
    var isContainerStopped: Bool = false
    let onTap: () -> Void
    @ViewBuilder let contextMenu: ContextMenu

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        cardContent
            .contentShape(.rect)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        onTap()
                    }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .contextMenu { contextMenu }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                itemIcon
                Spacer()
                statusTag
            }
            .padding(.bottom, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(height: 120)
        .background(cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(cardBorder)
        .offset(y: isHovering ? -2 : 0)
    }

    @ViewBuilder
    private var itemIcon: some View {
        switch item {
        case .connection(let connection):
            DatabaseTypeIcon(databaseType: connection.databaseType)
                .grayscale(isContainerStopped ? 1 : 0)
        case .notebook:
            NotebookIcon()
        }
    }

    @ViewBuilder
    private var statusTag: some View {
        switch item {
        case .connection(let connection):
            if isContainerStopped {
                StoppedContainerStatusTag()
            } else if isContainerBacked {
                ContainerStatusTag()
            } else if let env = connection.environment {
                EnvironmentTag(environment: env)
            }
        case .notebook(let notebook):
            NotebookStatusTag(status: notebook.status)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(cardFillColor)
            .shadow(color: .black.opacity(isHovering ? 0.15 : 0.10), radius: isHovering ? 2 : 1, y: isHovering ? 1 : 0.5)
    }

    private var cardFillColor: Color {
        let isDark = colorScheme == .dark
        if isHovering {
            return isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
        }
        return isDark ? Color.white.opacity(0.04) : .white
    }

    private var cardBorder: some View {
        let isDark = colorScheme == .dark
        return RoundedRectangle(cornerRadius: 12)
            .stroke(
                isDark
                    ? Color.white.opacity(isHovering ? 0.12 : 0.06)
                    : Color.black.opacity(isHovering ? 0.12 : 0.08),
                lineWidth: 0.5
            )
    }

    private var relativeTime: String {
        let now = RelativeTimeClock.shared.now
        let interval = now.timeIntervalSince(item.lastAccessedAt)
        if interval < 60 {
            return "Just now"
        }
        return item.lastAccessedAt.formatted(.relative(presentation: .named))
    }
}

struct RecentConnectionCard: View {
    let connection: Connection
    var isContainerBacked: Bool = false
    var isContainerStopped: Bool = false
    let onOpen: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        RecentCard(
            item: .connection(connection),
            isContainerBacked: isContainerBacked,
            isContainerStopped: isContainerStopped,
            onTap: onOpen
        ) {
            Button {
                onOpen()
            } label: {
                Label("Connect", systemImage: "arrow.up.forward.square")
            }
            .disabled(isContainerStopped)

            Divider()

            Button {
                showEditSheet = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(connection.copyableConnectionUri, forType: .string)
            } label: {
                Label("Copy connection string", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            CreateConnectionForm(connection: connection)
                .frame(width: 480)
        }
        .confirmationDialog(
            "Delete \"\(connection.name)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    // Tear down any open window/tab holding this model before
                    // deleting it, otherwise later reads of its attributes fault.
                    if let instance = ConnectionService.shared.getExistingInstance(for: connection) {
                        await ConnectionService.shared.removeConnectionInstance(instance.id)
                    }

                    QueryHistoryService.deleteHistoryForConnection(
                        modelContext: modelContext,
                        connectionKeychainId: connection.keychainId
                    )
                    connection.cleanupKeychain()
                    modelContext.delete(connection)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting this connection removes its saved settings and query history.")
        }
        .dialogSeverity(.standard)
    }
}

struct RecentNotebookCard: View {
    let notebook: Notebook
    let onOpen: () -> Void
    let onDelete: (Notebook) -> Void

    var body: some View {
        RecentCard(item: .notebook(notebook), onTap: onOpen) {
            Button {
                onOpen()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.square")
            }

            Divider()

            Button(role: .destructive) {
                onDelete(notebook)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
