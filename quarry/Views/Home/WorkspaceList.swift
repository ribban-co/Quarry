//
//  WorkspaceList.swift
//  Quarry
//

import AppKit
import SwiftData
import SwiftUI

private enum WorkspaceSortField: String, CaseIterable {
    case name
    case lastViewed
    case dateCreated
    case dateUpdated

    static let defaultValue: Self = .dateCreated

    var title: String {
        switch self {
        case .name: "Name"
        case .lastViewed: "Last Viewed"
        case .dateCreated: "Date Created"
        case .dateUpdated: "Date Updated"
        }
    }
}

private enum WorkspaceSortDirection: String {
    case ascending
    case descending

    static let defaultValue: Self = .descending

    var symbol: String {
        switch self {
        case .ascending: "↑"
        case .descending: "↓"
        }
    }

    mutating func toggle() {
        switch self {
        case .ascending:
            self = .descending
        case .descending:
            self = .ascending
        }
    }
}

struct WorkspaceList: View {
    let items: [WorkspaceItem]
    var containerBackedConnectionIds: Set<String> = []
    var stoppedContainerConnectionIds: Set<String> = []
    let onOpenConnection: (Connection) -> Void
    let onOpenNotebook: (Notebook) -> Void
    let onCreateConnection: () -> Void
    let onCreateNotebook: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor(\WorkspaceFolder.sortIndex), SortDescriptor(\WorkspaceFolder.createdAt)])
    private var folders: [WorkspaceFolder]
    @State private var notebookToDelete: Notebook?
    @State private var showDeleteNotebook = false
    @State private var renamingFolderId: UUID?
    @State private var dropTargetFolderId: UUID?
    @State private var isUngroupedDropTargeted = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var isSearchIconHovering = false
    @AppStorage("homeWorkspaceSortField") private var selectedSortFieldRawValue = WorkspaceSortField.defaultValue.rawValue
    @AppStorage("homeWorkspaceSortDirection") private var sortDirectionRawValue = WorkspaceSortDirection.defaultValue.rawValue
    @FocusState private var isSearchFocused: Bool

    private var selectedSortField: WorkspaceSortField {
        get {
            WorkspaceSortField(rawValue: selectedSortFieldRawValue) ?? WorkspaceSortField.defaultValue
        }
        nonmutating set {
            selectedSortFieldRawValue = newValue.rawValue
        }
    }

    private var sortDirection: WorkspaceSortDirection {
        get {
            WorkspaceSortDirection(rawValue: sortDirectionRawValue) ?? WorkspaceSortDirection.defaultValue
        }
        nonmutating set {
            sortDirectionRawValue = newValue.rawValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            listHeader

            if items.isEmpty {
                emptyState
            } else if displayedItems.isEmpty {
                noResultsState
            } else {
                listContent
            }
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

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [WorkspaceItem] {
        guard !normalizedSearchText.isEmpty else { return items }

        return items.filter { item in
            item.searchTokens.localizedStandardContains(normalizedSearchText)
        }
    }

    private var displayedItems: [WorkspaceItem] {
        filteredItems.sorted(by: shouldPlaceBefore(_:_:))
    }

    private var listHeader: some View {
        HStack(alignment: .center, spacing: 6) {
            Spacer()

            createButtons

            if !items.isEmpty {
                HStack(spacing: 0) {
                    sortMenu
                    searchControl
                }
                .fixedSize(horizontal: false, vertical: true)
                .toolbarIsland()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            keyboardSearchShortcut
        }
    }

    private var keyboardSearchShortcut: some View {
        Button(action: showSearch) {
            Color.clear
                .frame(width: 0, height: 0)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: [.command])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var searchToggleAnimation: Animation {
        if accessibilityReduceMotion {
            return .linear(duration: 0.01)
        }

        return .easeOut(duration: 0.16)
    }

    private var searchControl: some View {
        HStack(spacing: isSearchVisible ? 6 : 0) {
            if isSearchVisible {
                toolbarActionIcon("magnifyingglass")
                    .frame(width: 20)
                    .padding(.leading, -4)
                
                TextField("Search workspace", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onExitCommand(perform: handleSearchExitCommand)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        focusSearchField()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            } else {
                searchToggleButton
            }
        }
        .padding(.leading, isSearchVisible ? 8 : 0)
        .padding(.vertical, isSearchVisible ? ToolbarIslandMetrics.controlVerticalPadding : 0)
        .background(isSearchVisible ? searchControlFillColor : .clear)
        .clipShape(.rect(cornerRadius: ToolbarIslandMetrics.innerCornerRadius))
        .frame(width: isSearchVisible ? 220 : 28, alignment: .trailing)
        .animation(searchToggleAnimation, value: isSearchVisible)
        .onChange(of: isSearchVisible) { _, visible in
            if visible {
                focusSearchField()
            } else {
                isSearchFocused = false
            }
        }
    }

    private var searchToggleButton: some View {
        Button(action: showSearch) {
            toolbarActionIcon("magnifyingglass")
        }
        .buttonStyle(homeToolbarActionButtonStyle)
    }

    private var searchControlFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)
    }

    private var createButtons: some View {
        HStack(spacing: 6) {
            Button(action: createFolder) {
                Label("Folder", systemImage: "plus").padding(.trailing, 4)
            }
            .buttonStyle(WorkspaceCreateButtonStyle(cornerRadius: ToolbarIslandMetrics.innerCornerRadius))
            .toolbarIsland()

            Button(action: onCreateNotebook) {
                Label("Notebook", systemImage: "plus").padding(.trailing, 4)
            }
            .buttonStyle(WorkspaceCreateButtonStyle(cornerRadius: ToolbarIslandMetrics.innerCornerRadius))
            .toolbarIsland()

            Button(action: onCreateConnection) {
                Label("Connection", systemImage: "plus").padding(.trailing, 4)
            }
            .buttonStyle(WorkspaceCreateButtonStyle(cornerRadius: ToolbarIslandMetrics.innerCornerRadius))
            .toolbarIsland()
        }
    }

    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(WorkspaceSortField.allCases, id: \.title) { field in
                    Button {
                        handleSortSelection(field)
                    } label: {
                        HStack {
                            if selectedSortField == field {
                                Image(systemName: "checkmark")
                            }

                            Text(field.title)
                        }
                    }
                }
            }
        } label: {
            toolbarActionIcon("arrow.up.arrow.down")
        }
        .buttonStyle(homeToolbarActionButtonStyle)
        .menuIndicator(.hidden)
    }

    private func toolbarActionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 14, height: 14)
    }

    private var homeToolbarActionButtonStyle: ActionButtonStyle {
        ActionButtonStyle(
            padding: EdgeInsets(
                top: ToolbarIslandMetrics.controlVerticalPadding,
                leading: ToolbarIslandMetrics.controlHorizontalPadding,
                bottom: ToolbarIslandMetrics.controlVerticalPadding,
                trailing: ToolbarIslandMetrics.controlHorizontalPadding
            ),
            cornerRadius: ToolbarIslandMetrics.innerCornerRadius
        )
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
                .font(.title2)
        } description: {
            Text("No workspace items match \"\(normalizedSearchText)\".")
        }
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        WorkspaceEmptyState(onCreateConnection: onCreateConnection)
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Name")

                Spacer()

                Text("Kind")
                    .frame(width: 100, alignment: .leading)

                Text("Last Opened")
                    .frame(width: 120, alignment: .leading)

                Text("Created")
                    .frame(width: 120, alignment: .leading)
            }
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
            .padding(.top, 2)
            .padding(.bottom, 10)

            Divider().padding(.bottom, 8)

            LazyVStack(spacing: 6) {
                ForEach(visibleFolders) { folder in
                    folderSection(folder)
                }

                ungroupedSection
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grouping

    private var isSearching: Bool {
        !normalizedSearchText.isEmpty
    }

    private var folderIds: Set<UUID> {
        Set(folders.map(\.id))
    }

    /// Folders stay listed while browsing so empty ones remain drop targets;
    /// a search hides the ones with nothing to show.
    private var visibleFolders: [WorkspaceFolder] {
        guard isSearching else { return folders }
        return folders.filter { !items(in: $0).isEmpty }
    }

    private func items(in folder: WorkspaceFolder) -> [WorkspaceItem] {
        displayedItems.filter { $0.folderId == folder.id }
    }

    /// An item pointing at a folder that no longer exists falls back here
    /// rather than disappearing from the list.
    private var ungroupedItems: [WorkspaceItem] {
        displayedItems.filter { item in
            guard let folderId = item.folderId else { return true }
            return !folderIds.contains(folderId)
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: WorkspaceFolder) -> some View {
        let children = items(in: folder)
        let expanded = isExpanded(folder)

        VStack(alignment: .leading, spacing: 6) {
            WorkspaceFolderRow(
                folder: folder,
                itemCount: children.count,
                isExpanded: expanded,
                isRenaming: renamingFolderId == folder.id,
                isDropTargeted: dropTargetFolderId == folder.id,
                onToggle: { toggleExpansion(folder) },
                onBeginRename: { renamingFolderId = folder.id },
                onCommitRename: { commitRename(folder, to: $0) },
                onCancelRename: { renamingFolderId = nil },
                onPickColor: { folder.color = $0 },
                onDelete: { deleteFolder(folder) }
            )
            .dropDestination(for: WorkspaceItemTransfer.self) { transfers, _ in
                move(transfers, to: folder.id)
                if !folder.isExpanded {
                    withAnimation(moveAnimation) { folder.isExpanded = true }
                }
                return true
            } isTargeted: { isTargeted in
                dropTargetFolderId = isTargeted ? folder.id : nil
            }

            if expanded {
                if children.isEmpty {
                    Text("Drag connections and notebooks here")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 40)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 6) {
                        ForEach(children) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.leading, 24)
                }
            }
        }
    }

    @ViewBuilder
    private var ungroupedSection: some View {
        if visibleFolders.isEmpty {
            ForEach(ungroupedItems) { item in
                itemRow(item)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ungrouped")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 12)

                if ungroupedItems.isEmpty {
                    // Keeps a landing spot for dragging an item back out
                    // once everything is filed away.
                    Text("Drop here to remove from a folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                } else {
                    ForEach(ungroupedItems) { item in
                        itemRow(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUngroupedDropTargeted ? Color(.separatorColor).opacity(0.25) : .clear)
                    .padding(.horizontal, -10)
            )
            .dropDestination(for: WorkspaceItemTransfer.self) { transfers, _ in
                move(transfers, to: nil)
                return true
            } isTargeted: { isUngroupedDropTargeted = $0 }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: WorkspaceItem) -> some View {
        Group {
            switch item {
            case .connection(let connection):
                WorkspaceConnectionRow(
                    connection: connection,
                    isContainerBacked: containerBackedConnectionIds.contains(connection.keychainId),
                    isContainerStopped: stoppedContainerConnectionIds.contains(connection.keychainId),
                    folderMenu: folderMenu(for: item),
                    onOpen: onOpenConnection
                )
            case .notebook(let notebook):
                WorkspaceNotebookRow(
                    notebook: notebook,
                    folderMenu: folderMenu(for: item),
                    onOpen: onOpenNotebook,
                    onDelete: { nb in
                        notebookToDelete = nb
                        showDeleteNotebook = true
                    }
                )
            }
        }
        .draggable(WorkspaceItemTransfer(itemId: item.id)) {
            WorkspaceDragPreview(title: item.name)
        }
    }

    private func folderMenu(for item: WorkspaceItem) -> WorkspaceMoveToFolderMenu {
        WorkspaceMoveToFolderMenu(
            folders: folders,
            currentFolderId: item.folderId,
            onMove: { move(item, to: $0) },
            onMoveToNewFolder: { moveToNewFolder(item) }
        )
    }

    // MARK: - Folder actions

    private var moveAnimation: Animation {
        accessibilityReduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.18)
    }

    private func isExpanded(_ folder: WorkspaceFolder) -> Bool {
        isSearching || folder.isExpanded
    }

    private func toggleExpansion(_ folder: WorkspaceFolder) {
        // Search force-expands every folder; honouring a toggle there would
        // silently flip state the user can't see change.
        guard !isSearching else { return }
        withAnimation(moveAnimation) {
            folder.isExpanded.toggle()
        }
        folder.updatedAt = Date()
    }

    private func createFolder() {
        renamingFolderId = makeFolder().id
    }

    @discardableResult
    private func makeFolder() -> WorkspaceFolder {
        let folder = WorkspaceFolder(
            name: uniqueFolderName(),
            color: nextFolderColor(),
            sortIndex: (folders.map(\.sortIndex).max() ?? -1) + 1
        )
        modelContext.insert(folder)
        return folder
    }

    private func uniqueFolderName() -> String {
        let base = "New Folder"
        let existingNames = Set(folders.map(\.name))
        guard existingNames.contains(base) else { return base }

        var suffix = 2
        while existingNames.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private func nextFolderColor() -> ConnectionColor {
        let palette: [ConnectionColor] = [.blue, .emerald, .orange, .purple, .pink, .turquoise, .yellow, .red]
        return palette[folders.count % palette.count]
    }

    private func commitRename(_ folder: WorkspaceFolder, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            folder.name = trimmedName
            folder.updatedAt = Date()
        }
        renamingFolderId = nil
    }

    /// Deleting a folder never deletes its contents — they fall back to
    /// the ungrouped section.
    private func deleteFolder(_ folder: WorkspaceFolder) {
        if renamingFolderId == folder.id {
            renamingFolderId = nil
        }

        withAnimation(moveAnimation) {
            for item in items where item.folderId == folder.id {
                item.move(toFolder: nil)
            }
            modelContext.delete(folder)
        }
    }

    private func move(_ item: WorkspaceItem, to folderId: UUID?) {
        withAnimation(moveAnimation) {
            item.move(toFolder: folderId)
        }
    }

    private func move(_ transfers: [WorkspaceItemTransfer], to folderId: UUID?) {
        let itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        withAnimation(moveAnimation) {
            for transfer in transfers {
                itemsById[transfer.itemId]?.move(toFolder: folderId)
            }
        }
    }

    private func moveToNewFolder(_ item: WorkspaceItem) {
        let folder = makeFolder()
        move(item, to: folder.id)
        renamingFolderId = folder.id
    }

    private func showSearch() {
        if !isSearchVisible {
            withAnimation(searchToggleAnimation) {
                isSearchVisible = true
            }
        }

        focusSearchField()
    }

    private func handleSearchExitCommand() {
        if searchText.isEmpty {
            collapseSearchField(clearSearchText: false)
            return
        }

        searchText = ""
    }

    private func collapseSearchField(clearSearchText: Bool = true) {
        if clearSearchText {
            searchText = ""
        }

        withAnimation(searchToggleAnimation) {
            isSearchVisible = false
        }
        isSearchFocused = false
    }

    private func focusSearchField() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isSearchFocused = true
        }
    }

    private func handleSortSelection(_ field: WorkspaceSortField) {
        if selectedSortField == field {
            sortDirection.toggle()
            return
        }

        selectedSortField = field
        sortDirection = .descending
    }

    private func shouldPlaceBefore(_ lhs: WorkspaceItem, _ rhs: WorkspaceItem) -> Bool {
        switch selectedSortField {
        case .name:
            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison == .orderedSame {
                return lhs.id < rhs.id
            }
            return sortDirection == .ascending
                ? nameComparison == .orderedAscending
                : nameComparison == .orderedDescending
        case .lastViewed:
            return shouldPlaceDateBefore(
                lhs.lastViewedAt,
                rhs.lastViewedAt,
                lhs: lhs,
                rhs: rhs
            )
        case .dateCreated:
            return shouldPlaceDateBefore(
                lhs.createdAt,
                rhs.createdAt,
                lhs: lhs,
                rhs: rhs
            )
        case .dateUpdated:
            return shouldPlaceDateBefore(
                lhs.updatedAt,
                rhs.updatedAt,
                lhs: lhs,
                rhs: rhs
            )
        }
    }

    private func shouldPlaceDateBefore(
        _ lhsDate: Date,
        _ rhsDate: Date,
        lhs: WorkspaceItem,
        rhs: WorkspaceItem
    ) -> Bool {
        if lhsDate == rhsDate {
            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison == .orderedSame {
                return lhs.id < rhs.id
            }
            return nameComparison == .orderedAscending
        }

        return sortDirection == .ascending
            ? lhsDate < rhsDate
            : lhsDate > rhsDate
    }
}

private func relativeTimeText(for date: Date, now: Date) -> String {
    now.timeIntervalSince(date) < 60
        ? "a moment ago"
        : date.formatted(.relative(presentation: .named))
}

/// Relative timestamp that refreshes itself instead of freezing at whatever the
/// row said when it was last rendered.
private struct RelativeTimeText: View {
    let date: Date?

    var body: some View {
        Text(date.map { relativeTimeText(for: $0, now: RelativeTimeClock.shared.now) } ?? "")
    }
}

private struct WorkspaceRow<Icon: View, ContextMenu: View>: View {
    let icon: Icon
    let title: String
    let subtitle: String?
    let statusTag: AnyView?
    let kind: String
    let lastOpenedAt: Date?
    let createdAt: Date?
    var textOpacity: Double = 1.0
    let onDoubleClick: () -> Void
    @ViewBuilder let contextMenu: ContextMenu

    @State private var isHovering = false

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                icon

                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Text(title)
                            .foregroundStyle(.primary)

                        if let statusTag {
                            statusTag
                        }
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .opacity(textOpacity)
            }

            Spacer()

            Group {
                Text(kind)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)

                RelativeTimeText(date: lastOpenedAt)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Text(createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
            }
            .opacity(textOpacity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(.rect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? Color(.separatorColor).opacity(0.35) : .clear)
        )
        .padding(.horizontal, -10)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { onDoubleClick() }
        )
        .contextMenu { contextMenu }
    }
}

struct WorkspaceNotebookRow: View {
    let notebook: Notebook
    var folderMenu: WorkspaceMoveToFolderMenu?
    let onOpen: (Notebook) -> Void
    let onDelete: (Notebook) -> Void

    var body: some View {
        WorkspaceRow(
            icon: NotebookIcon(),
            title: notebook.title,
            subtitle: notebook.descriptionText.isEmpty ? nil : notebook.descriptionText,
            statusTag: AnyView(NotebookStatusTag(status: notebook.status)),
            kind: "Notebook",
            lastOpenedAt: notebook.updatedAt,
            createdAt: notebook.createdAt,
            onDoubleClick: { onOpen(notebook) }
        ) {
            Button {
                onOpen(notebook)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.square")
            }

            if let folderMenu {
                Divider()

                folderMenu
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

struct ContainerStatusTag: View {
    var body: some View {
        Text("Docker")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.primaryButton)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primaryButton.opacity(0.82), lineWidth: 1)
            )
    }
}

struct StoppedContainerStatusTag: View {
    var body: some View {
        Text("Stopped")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            )
    }
}

struct WorkspaceConnectionRow: View {
    let connection: Connection
    var isContainerBacked: Bool = false
    var isContainerStopped: Bool = false
    var folderMenu: WorkspaceMoveToFolderMenu?
    let onOpen: (Connection) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false

    private var subtitle: String? {
        if connection.databaseType == .convex, let hostname = connection.hostname {
            return "ID: \(hostname)"
        }
        return connection.displayUrl
    }

    var body: some View {
        WorkspaceRow(
            icon: DatabaseTypeIcon(databaseType: connection.databaseType)
                .grayscale(isContainerStopped ? 1 : 0),
            title: connection.name,
            subtitle: subtitle,
            statusTag: isContainerStopped
                ? AnyView(StoppedContainerStatusTag())
                : isContainerBacked
                    ? AnyView(ContainerStatusTag())
                    : connection.environment.map { AnyView(EnvironmentTag(environment: $0)) },
            kind: isContainerStopped ? "Stopped" : (isContainerBacked ? "Container" : "Connection"),
            lastOpenedAt: connection.lastOpenedAt,
            createdAt: connection.createdAt,
            textOpacity: isContainerStopped ? 0.6 : 1.0,
            onDoubleClick: {
                if !isContainerStopped {
                    onOpen(connection)
                }
            }
        ) {
            Button {
                onOpen(connection)
            } label: {
                Label("Connect", systemImage: "arrow.up.forward.square")
            }
            .disabled(isContainerStopped)

            if let folderMenu {
                Divider()

                folderMenu
            }

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
                    // Tear down every open window/tab holding this model before
                    // deleting it, otherwise later reads of its attributes fault.
                    // Multiple instances can exist per connection (multiple tabs,
                    // environment tabs) — removing only the first leaves zombies.
                    while let instance = ConnectionService.shared.getExistingInstance(for: connection) {
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

private struct WorkspaceEmptyState: View {
    let onCreateConnection: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let supportedTypes: [DatabaseType] = [
        .postgres, .mysql, .sqlite, .mongodb, .convex
    ]

    var body: some View {
        VStack(spacing: 28) {
            databaseIconCluster

            VStack(spacing: 8) {
                Text("Connect your first database")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Add a connection to browse tables, run queries, and use AI with your data.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onCreateConnection) {
                Text("New Connection")
            }
            .buttonStyle(PillPrimaryButtonStyle())
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var databaseIconCluster: some View {
        HStack(spacing: -10) {
            ForEach(Array(supportedTypes.enumerated()), id: \.offset) { index, type in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(type.backgroundColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(type.homeIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 26, height: 26)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(iconRingColor, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    .zIndex(Double(supportedTypes.count - index))
            }
        }
    }

    private var iconRingColor: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : .white
    }
}

private struct PillPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color(.textBackgroundColor) : .secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.primaryButton : Color.white.opacity(0.1))
                    .opacity(isHovering ? 0.88 : 1.0)
            )
            .shadow(color: Color.primaryButton.opacity(isEnabled ? 0.25 : 0), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
