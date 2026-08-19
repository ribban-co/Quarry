//
//  FloatingActionBar.swift
//  Collection
//
//  Created by Fauzaan on 2/26/25.
//

import AppKit
import SwiftUI
import MongoKitten

struct FloatingActionBar: View {
    let tabID: UUID
    var viewState: TableListViewState
    let tableName: String
    @Binding var tabViewMode: DatabaseTab.ViewMode
    let modificationTracker: TableModificationTracker
    let isProcessingUpdates: Bool
    let onRefresh: (_ currentPage: Int, _ itemsPerPage: Int, _ fetchSchema: Bool) -> Void
    let onLoadDocuments: (_ filter: String?) -> Void
    let onCommitModifications: () -> Void
    let onNewRecord: () -> Void
    let onDiscardChanges: () -> Void
    let databaseType: DatabaseType?

    // Add current query result as direct parameter to preserve data during loading
    let currentQueryResult: QueryResult?
    let schema: DatabaseSchemaResult?

    // Total rows in the table for the active filter (nil while unknown)
    var totalRowCount: Int? = nil

    // Schema modification tracking
    let schemaModificationTracker: SchemaModificationTracker?
    let onCommitSchemaModifications: (() -> Void)?
    var onNewField: (() -> Void)?
    var onCancelLoad: (() -> Void)? = nil
    
    @Environment(ConnectionInstance.self) private var instance
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    @State private var containerWidth: CGFloat = 416
    @State var showQueryEditor: Bool = false
    @State var showCreateDocumentSheet: Bool = false
    @State var filter: String = ""
    @State var commandFilter: String = ""
    
    @State var action: ActionBar = ActionBar.main
    @State var showFilterEditor: Bool = false
    @State private var searchFocusRequest = 0
    
    @State private var loadingTask: Task<Void, Never>?
    @State private var errorTask: Task<Void, Never>?
    
    // MARK: - Animation States
    @State private var showQueryUpdateAnimation = false
    @State private var previousFilter: String = ""
    @State private var isSubmitAnimating: Bool = false
    @State private var hostingWindow: NSWindow?
    
    // MARK: - Processing State
    @State private var processingStage: ProcessingStage = .idle
    @State private var animationDots: String = ""

    private var actionBarCornerRadius: CGFloat {
        switch action {
        case .search:
            20
        case .commandPalette:
            14
        case .main, .create:
            14
        }
    }

    private var loaderCornerRadius: CGFloat {
        switch action {
        case .main:
            14
        case .commandPalette:
            14
        case .search, .create:
            20
        }
    }
    @State private var animationTask: Task<Void, Never>?
    
    // MARK: - Pagination
    @State var currentPage = 1
    @State var totalPerPage = 300
    private var totalPages: Int {
        guard let totalRowCount, totalPerPage > 0 else { return 1 }
        return max(1, Int((Double(totalRowCount) / Double(totalPerPage)).rounded(.up)))
    }
    private var totalCount: Int {
        // Use the directly passed currentQueryResult to preserve data during loading
        if let queryResult = currentQueryResult {
            return queryResult.totalCount
        }
        return 0
    }
    
    
    private var isLoading: Bool {
        if case .loading = viewState {
            return true
        }
        return false
    }
    
    @State private var debouncedIsLoading: Bool = false
    @State private var debounceTask: Task<Void, Never>?
    private let screenWidth = NSScreen.main?.frame.width ?? 200
    
    var body: some View {
        VStack(spacing: 0) {
            if !showQueryEditor && !showCreateDocumentSheet && action != .commandPalette && tabViewMode == .content {
                topRectangleView
                    .padding(.horizontal, action == .main ? 10 : 16)
                    .frame(width: containerWidth)
                    .animation(.smooth, value: showQueryEditor || showCreateDocumentSheet)
                    .scaleEffect(isSubmitAnimating ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.10), value: isSubmitAnimating)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: containerWidth)
                
            }
            
            if action == .commandPalette {
                CommandPalette.CollectionsList(
                    tabID: tabID,
                    searchText: $commandFilter,
                    onBack: {
                        withAnimation(.spring(response: 0.3)) {
                            action = .main
                        }
                    }
                )
            }
            
            if !showCreateDocumentSheet && showQueryEditor {
                QueryEditor(showQueryEditor: $showQueryEditor, filter: $filter, isLoading: isLoading,totalCount: totalCount, totalRowCount: totalRowCount, onLoadDocuments: onLoadDocuments)
                    .padding(.horizontal, 80)
            }
            
            if showCreateDocumentSheet {
                CreateEditor(showCreateDocumentSheet: $showCreateDocumentSheet)
                    .frame(width: screenWidth * 0.6)
            }
            
            HStack {
                switch action {
                case .main:
                    switch tabViewMode {
                    case .content:
                        ContentModeActionBar(
                            currentPage: $currentPage,
                            tabViewMode: $tabViewMode,
                            totalPages: totalPages,
                            totalCount: totalCount,
                            totalRowCount: totalRowCount,
                            totalPerPage: totalPerPage,
                            modificationTracker: modificationTracker,
                            isProcessingUpdates: isProcessingUpdates,
                            tableName: tableName,
                            isLoading: isLoading,
                            debouncedIsLoading: debouncedIsLoading,
                            onRefresh: onRefresh,
                            onCommitModifications: onCommitModifications,
                            onNewRecord: {
                                if databaseType == .mongodb {
                                    withAnimation(.spring(response: 0.3)) {
                                        showCreateDocumentSheet = true
                                    }
                                } else {
                                    onNewRecord()
                                }
                            },
                            onOpenAISearch: openAISearch,
                            onToggleFilterBuilder: toggleFilterBuilder,
                            onDebounceLoadingChange: { newValue in
                                debouncedIsLoading = newValue
                            },
                            onDiscardChanges: onDiscardChanges,
                            databaseType: databaseType,
                            onCancelLoad: onCancelLoad
                        )
                    case .schema:
                        SchemaModeActionBar(
                            tabViewMode: $tabViewMode,
                            columnCount: schema?.columns.count ?? 0,
                            isLoading: isLoading,
                            debouncedIsLoading: debouncedIsLoading,
                            onRefresh: onRefresh,
                            onDebounceLoadingChange: { newValue in
                                debouncedIsLoading = newValue
                            },
                            schemaModificationTracker: schemaModificationTracker,
                            onCommitSchemaModifications: onCommitSchemaModifications,
                            onNewField: onNewField,
                            onCancelLoad: onCancelLoad
                        )
                    case .definition:
                        DefinitionModeActionBar(
                            tabViewMode: $tabViewMode,
                            isLoading: isLoading,
                            debouncedIsLoading: debouncedIsLoading,
                            onRefresh: onRefresh,
                            onDebounceLoadingChange: { newValue in
                                debouncedIsLoading = newValue
                            },
                            onCancelLoad: onCancelLoad
                        )
                    }
                case .search:
                    AISearchView(
                        filter: $filter,
                        focusRequest: searchFocusRequest,
                        showQueryEditor: showQueryEditor,
                        tableName: tableName,
                        isSubmitAnimating: $isSubmitAnimating,
                        processingStage: $processingStage,
                        onBack: {
                            withAnimation(.spring(response: 0.3)) {
                                action = .main
                            }
                        },
                        onLoadDocuments: onLoadDocuments,
                        onRefresh: {
                            if !isLoading {
                                onRefresh(currentPage, totalPerPage, true)
                            }
                        })
                case .commandPalette:
                    CommandPalette(
                        searchText: $commandFilter,
                        onBack: {
                            withAnimation(.spring(response: 0.3)) {
                                action = .main
                            }
                        },
                        isBackButtonEnabled: true
                    )
                default:
                    switch tabViewMode {
                    case .content:
                        ContentModeActionBar(
                            currentPage: $currentPage,
                            tabViewMode: $tabViewMode,
                            totalPages: totalPages,
                            totalCount: totalCount,
                            totalRowCount: totalRowCount,
                            totalPerPage: totalPerPage,
                            modificationTracker: modificationTracker,
                            isProcessingUpdates: isProcessingUpdates,
                            tableName: tableName,
                            isLoading: isLoading,
                            debouncedIsLoading: debouncedIsLoading,
                            onRefresh: onRefresh,
                            onCommitModifications: onCommitModifications,
                            onNewRecord: {
                                if databaseType == .mongodb {
                                    withAnimation(.spring(response: 0.3)) {
                                        showCreateDocumentSheet = true
                                    }
                                } else {
                                    onNewRecord()
                                }
                            },
                            onOpenAISearch: {
                                withAnimation(.spring(response: 0.3)) {
                                    action = ActionBar.search
                                }
                            },
                            onToggleFilterBuilder: toggleFilterBuilder,
                            onDebounceLoadingChange: { newValue in
                                debouncedIsLoading = newValue
                            },
                            onDiscardChanges: onDiscardChanges,
                            databaseType: databaseType,
                            onCancelLoad: onCancelLoad
                        )
                    case .schema:
                        SchemaModeActionBar(
                            tabViewMode: $tabViewMode,
                            columnCount: schema?.columns.count ?? 0,
                            isLoading: isLoading,
                            debouncedIsLoading: debouncedIsLoading,
                            onRefresh: onRefresh,
                            onDebounceLoadingChange: { newValue in
                                debouncedIsLoading = newValue
                            },
                            schemaModificationTracker: schemaModificationTracker,
                            onCommitSchemaModifications: onCommitSchemaModifications,
                            onNewField: onNewField,
                            onCancelLoad: onCancelLoad
                        )
                    case .definition:
                        DefinitionModeActionBar(
                            tabViewMode: $tabViewMode,
                            isLoading: isLoading,
                            debouncedIsLoading: debouncedIsLoading,
                            onRefresh: onRefresh,
                            onDebounceLoadingChange: { newValue in
                                debouncedIsLoading = newValue
                            },
                            onCancelLoad: onCancelLoad
                        )
                    }
                }
            }
            .background(
                TwoPhaseLoader(
                    containerWidth: containerWidth,
                    isLoading: isLoading,
                    cornerRadius: loaderCornerRadius
                )
            )
            .modifier(GlassBackgroundStyle(cornerRadius: actionBarCornerRadius))
            .background(
                Group {
                    if colorScheme == .dark {
                        RoundedRectangle(cornerRadius: actionBarCornerRadius)
                            .fill(
                                Color(.clear)
                            )
                            .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 4)
                    } else {
                        RoundedRectangle(cornerRadius: actionBarCornerRadius)
                            .fill(
                                Color(.clear)
                            )
                            .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 4)
                    }
                }
            )
            .glassFallbackBorder(
                RoundedRectangle(cornerRadius: actionBarCornerRadius),
                lineWidth: colorScheme == .dark ? 1 : 0.5
            )
//            .background(alignment: .center) {
//                if case .error = viewState {
//                    LoadingErrorIndicator(cornerRadius: action == .main ? 12 : 20)
//                }
//            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: action)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: modificationTracker.hasModifications)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onChange(of: geometry.size.width) { oldWidth, newWidth in
                            containerWidth = newWidth
                        }
                }
            )
            .onAppear() {
                if databaseType == .mongodb && filter.isEmpty {
                    containerWidth = 308
                }
            }
            .task(id: processingStage) {
                await handleProcessingStageChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNewRecord)) { notification in
                // Only process if this notification is for our table
                if let notificationTableName = notification.userInfo?["tableName"] as? String,
                   notificationTableName == tableName {
                    Task {
                        if databaseType == .mongodb {
                            withAnimation(.spring(response: 0.3)) {
                                showCreateDocumentSheet = true
                            }
                        } else {
                            onNewRecord()
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tableRefresh)) { notification in
                // Only process if this notification is for our table
                if let notificationTableName = notification.userInfo?["tableName"] as? String,
                   notificationTableName == tableName {
                    Task {
                        loadingTask?.cancel()
                        debounceTask?.cancel()
                        
                        onRefresh(currentPage, totalPerPage, true)
                    }
                }
            }
            .onDisappear {
                // Cancel all active tasks to prevent crashes
                animationTask?.cancel()
                loadingTask?.cancel()
                errorTask?.cancel()
                debounceTask?.cancel()
            }
        }.onTapOutside {
            guard action != .search else { return }
            withAnimation(.spring(response: 0.3)) {
                action = .main
            }
        }
        .background(WindowReader { window in
            hostingWindow = window
        })
        .contentShape(Rectangle())
        .onTapGesture {
        }
        .onAppear {
            setupEventMonitor()
        }
        .onDisappear {
            removeEventMonitor()
        }
    }
    
    @State private var eventMonitor: Any?
    
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isKeyboardEventForHostingWindow(event) else { return event }

            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

            switch event.keyCode {
            case 15: // 'r' key
                if flags == .command {
                    // Cancel any existing loading operations before starting new one
                    loadingTask?.cancel()
                    debounceTask?.cancel()
                    onRefresh(currentPage, totalPerPage, true)
                    return nil // Consume the event
                }
                return event
                
            case 34: // 'i' key
                if flags == .command {
                    if databaseType == .mongodb {
                        withAnimation(.spring(response: 0.3)) {
                            showCreateDocumentSheet = true
                        }
                    } else {
                        onNewRecord()
                    }
                    return nil // Consume the event
                }
                return event

            case 45: // 'n' key
                if flags == [.command, .shift] {
                    // Add new column in schema mode
                    if tabViewMode == .schema {
                        onNewField?()
                        return nil // Consume the event
                    }
                }
                return event

            case 37: // 'l' key
                if flags == .command {
                    openAISearch()
                    return nil // Consume the event
                }
                return event
                
            case 35: // 'p' key
                if flags == .command {
                    withAnimation(.spring(response: 0.3)) {
                        action = .commandPalette
                    }
                    return nil // Consume the event
                }
                return event
                
            case 1: // 's' key
                if flags == .command {
                    // Commit any in-progress cell edit so the modification is recorded
                    // before we decide whether there's anything to save.
                    (event.window ?? NSApp.keyWindow)?.makeFirstResponder(nil)

                    // Handle save based on current state
                    if tabViewMode == .schema,
                       let tracker = schemaModificationTracker,
                       tracker.hasModifications {
                        onCommitSchemaModifications?()
                    } else if modificationTracker.hasPendingDeletions
                        || modificationTracker.hasModifications {
                        onCommitModifications()
                    }
                    return nil // Consume the event
                }
                return event
                
            case 3: // 'f' key
                if flags == .command {
                    toggleFilterBuilder()
                    return nil // Consume the event
                }
                return event

            case 51: // Delete key with Cmd+Shift
                if flags == [.command, .shift] && !filter.isEmpty {
                    filter = ""
                    onLoadDocuments(filter)
                    return nil // Consume the event
                }
                return event

            case 53: // 'esc' key
                withAnimation(.spring(response: 0.3)) {
                    action = .main
                }
                return event
                
            default:
                return event // Let other keys pass through
            }
        }
    }

    private func isKeyboardEventForHostingWindow(_ event: NSEvent) -> Bool {
        guard let hostingWindow,
              let eventWindow = event.window,
              eventWindow === hostingWindow,
              hostingWindow.isKeyWindow,
              instance.selectedTab?.id == tabID else {
            return false
        }

        return true
    }

    private func toggleFilterBuilder() {
        guard let hostingWindow else { return }
        NotificationCenter.default.post(
            name: .toggleFilterBuilder,
            object: hostingWindow,
            userInfo: ["tabID": tabID]
        )
    }

    private func openAISearch() {
        searchFocusRequest += 1
        withAnimation(.spring(response: 0.3)) {
            action = .search
        }
    }
    
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    @State private var isHoveringTopRectangle: Bool = false
    @State private var animatedFilterText: String = ""
    var statusColor: Color = Color(red: 1.0, green: 0.6, blue: 0.0)
    
    private var topRectangleView: some View {
        VStack {
            HStack {
                // Left side content - processing status or query display
                HStack(spacing: 0) {
                    if !filter.isEmpty || processingStage != .idle {
                        // Display the generated query with truncation
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.brand)
                            
                            if processingStage != .idle {
                                Text(processingStage.description + animationDots)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .transition(.push(from: .bottom))
                                    .id("processing-\(processingStage.description)")
                                    .animation(
                                        .interpolatingSpring(stiffness: 50, damping: 10),
                                        value: processingStage
                                    )
                                
                            } else {
                                Text(filter)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.75))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .animation(.smooth(duration: 0.3), value: filter)
                            }
                        }
                        
                    } else {
                        Text("Query Editor")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                // Right side - Clear button (always positioned at the end)
                if !filter.isEmpty {
                    Button(action: {
                        filter = ""
                        onLoadDocuments(filter)
                    }) {
                        Text("Clear")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)))
                    .customHelp("Clear filter", position: .top, shortcut: KeyboardShortcut(
                        modifiers: [.command, .shift],
                        key: "DELETE"
                    ), spacing: 10)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .animation(.smooth(duration: 0.2), value: filter.isEmpty)
                }
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 5)
        .modifier(GlassBackgroundStyleRoundedTop())
        .background(
            Group {
                if !filter.isEmpty || processingStage != .idle {
                    RoundedCorners(tl: 10, tr: 10, bl: 0, br: 0)
                        .fill(
                            RadialGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .brand, location: 0),
                                    .init(color: .brand.opacity(0.3), location: 0.8),
                                    .init(color: .clear, location: 1)
                                ]),
                                center: .leading,
                                startRadius: 2,
                                endRadius: 50
                            )
                        )
                        .blur(radius: 3)
                        .opacity(0.3)
                }
            }
        )
        .glassFallbackBorder(
            RoundedCornersTop(tl: 10, tr: 10, bl: 0, br: 0),
            lineWidth: colorScheme == .dark ? 1 : 0.5
        )
        .scaleEffect(isHoveringTopRectangle ? 1.02 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringTopRectangle = hovering
        }
        .animation(.smooth(duration: 0.15), value: isHoveringTopRectangle)
        .onTapGesture {
            openQueryEditor()
        }
    }


    private var FilterIcon: some View {
        HStack(spacing: 4) {
            Button(action: {
                toggleFilterBuilder()
            }) {
                BadgedFilterIcon()
            }
            .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8)))
            .customHelp("Ask AI", position: .top, shortcut: KeyboardShortcut(
                modifiers: [.command],
                key: "p"
            ), spacing: 10)
            
            // TODO: More options button
            //            Button(action: {
            //                // TODO:
            //                // Add an action
            //            }) {
            //                Image(systemName: "ellipsis")
            //                    .font(.system(size: 14))
            //                    .contentShape(Rectangle())
            //            }
            //            .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8)))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .modifier(GlassBackgroundStyle(cornerRadius: 8))
        .glassFallbackBorder(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 2)
        .onReceive(NotificationCenter.default.publisher(for: .toggleFilterBuilder)) { notification in
            guard let sourceWindow = notification.object as? NSWindow,
                  let hostingWindow,
                  sourceWindow === hostingWindow,
                  notification.userInfo?["tabID"] as? UUID == tabID else { return }

            showFilterEditor.toggle()
        }
        //        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.actionBarUpdateTrigger)
    }
    
    struct BadgedFilterIcon: View {
        var isFiltered = true
        
        var body: some View {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                if isFiltered {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 8, height: 8)
                        .offset(x: 5, y: -5)
                }
            }
        }
    }
    
    /// Open the full query editor view with animation
    func openQueryEditor() {
        Task { @MainActor in
            if !showQueryEditor {
                withAnimation(.spring(response: 0.15)) {
                    showQueryEditor = true
                }
            }
        }
    }
    
    // MARK: - Processing Animation Methods
    private func handleProcessingStageChange() async {
        if processingStage != .idle {
            await startProcessingAnimation()
        } else {
            stopProcessingAnimation()
        }
    }
    
    private func startProcessingAnimation() async {
        animationTask = Task {
            while !Task.isCancelled && processingStage != .idle {
                animationDots = animationDots.count >= 3 ? "" : animationDots + "."
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    
    private func stopProcessingAnimation() {
        animationTask?.cancel()
        animationTask = nil
        animationDots = ""
    }
}

enum ActionBar: String, CaseIterable, Codable {
    case main = "main"
    case search = "search"
    case create = "create"
    case commandPalette = "commandPalette"
}
