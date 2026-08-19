//
//  SQLEditorView.swift
//  Quarry
//
//  Created by Claude on 8/31/25.
//

import AppKit
import SwiftUI
import CodeEditorView
import LanguageSupport

private enum ResultsPillTabBarMetrics {
    static let outerCornerRadius = ToolbarIslandMetrics.cornerRadius
    static let innerCornerRadius = ToolbarIslandMetrics.innerCornerRadius
    static let legacyOuterHeight: CGFloat = 32
    static let legacyButtonHeight: CGFloat = 28
    static let containerPadding: CGFloat = 2
    static let horizontalPadding: CGFloat = 14
    static let labelSpacing: CGFloat = 4
    static let selectionAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.3)
    static let hoverAnimation = Animation.easeOut(duration: 0.15)
}

struct SQLEditorView: View {
    @Environment(ConnectionInstance.self) private var instance
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("enableAIFeatures") private var enableAIFeatures = true
    @AppStorage("showAIErrorSuggestions") private var showAIErrorSuggestions = true
    
    @State private var sqlQuery: String = ""
    @State private var viewState: SQLEditorViewState = .idle
    @State private var selectedResultIndex: Int = 0
    @State private var isExecuting: Bool = false
    @State private var lastExecutionTime: TimeInterval = 0
    @State private var lastRowCount: Int = 0
    @State private var lastError: Error?
    @State private var showAICommandPrompt: Bool = false
    @State private var initialCursorLineNumber: Int = 0
    @State private var aiErrorSuggestion: String? = nil
    @State private var isLoadingAISuggestion: Bool = false
    @State private var showAIErrorSuggestion: Bool = false
    @State private var originalQueryBeforeSuggestion: String = ""
    @State private var originalFullEditorContent: String = ""
    @State private var executedQueryPosition: CodeEditor.Position = CodeEditor.Position()
    @State private var showingInlineDiff: Bool = false
    @State private var sqlLanguageService: SQLAutocompleteLanguageService?
    @State private var editorWindow: NSWindow?
    @State private var pendingConfirmation: QueryConfirmationRequest?
    
    @State private var splitRatio: CGFloat = 0.4
    private var isLoading : Bool { viewState == .loading }
    
    var body: some View {
        SplitView(.vertical, $splitRatio, dividerColor: lastError != nil ? Color(.red).opacity(0.5) : isExecuting ? Color(red: 1.0, green: 0.5, blue: 0.0) : Color(.separatorColor), minSize: 40) {
            VStack(spacing: 0) {
                sqlEditor
                editorToolbar
            }
            .overlay(alignment: .top) {
                if showAIErrorSuggestion {
                    VStack {
                        Spacer()
                        
                        AIErrorSuggestionPopup(
                            isPresented: $showAIErrorSuggestion,
                            suggestion: $aiErrorSuggestion,
                            fixLabel: aiFixLabel,
                            isLoading: isLoadingAISuggestion,
                            onAcceptAndRun: acceptAISuggestion,
                            onAcceptOnly: acceptAISuggestionOnly,
                            onReject: rejectAISuggestion
                        )
                        .padding(.bottom, 10) // offset to place below the toolbar
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: showAIErrorSuggestion)
                }
            }
        } right: {
            resultsContent
        }
        .background(
            Group {
                if colorScheme == .dark {
                    Rectangle()
                        .fill(
                            Color(.black).opacity(0.30)
                        )
                        .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 4)
                } else {
                    Color(colorScheme == .dark ? .clear : Color(.white))
                        .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 4)
                }
            }
        )
        .background(WindowReader { window in
            editorWindow = window
        })
        .background(
            Group {
                Button(action: postSwitchDatabaseShortcut) {
                    EmptyView()
                }
                .keyboardShortcut("k", modifiers: [.command])
                .hidden()

                Button(action: {
                    openAICommandPrompt()
                }) {
                    EmptyView()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .hidden()

            }
        )
        .onAppear {
            configureSQLLanguageServiceIfNeeded()
            loadAvailableDatabases()
            loadInitialQueryFromTab()
        }
        .queryConfirmation($pendingConfirmation) { request in
            runQuery(request.query)
        }
    }
    
    @State private var selectedDatabase: String = ""
    @State private var availableDatabases: [any DatabaseWrapper] = []
    @State private var selectedSchema: String = ""
    @State private var availableSchemas: [InformationSchema] = []

    private var usesSchemaPicker: Bool {
        instance.connection.databaseType == .postgres || instance.connection.databaseType == .supabase
    }

    private var selectedExecutionSchema: String? {
        usesSchemaPicker && !selectedSchema.isEmpty ? selectedSchema : nil
    }

    private enum ToolbarMetrics {
        static let controlHeight: CGFloat = 30
        static let horizontalPadding: CGFloat = 12
        static let cornerRadius: CGFloat = 8
    }
    
    private var executionSummaryText: String {
        guard lastExecutionTime > 0 else { return "" }

        let timeInMs = lastExecutionTime * 1000
        let formattedTime = timeInMs.formatted(.number.precision(.fractionLength(0)))

        if lastRowCount > 0 {
            let formattedCount = lastRowCount.formatted(.number)
            return "\(formattedCount) rows returned in \(formattedTime)ms"
        } else {
            return "Executed in \(formattedTime)ms"
        }
    }
    
    private var editorToolbar: some View {
        HStack {
            Text(executionSummaryText)
                .font(.callout)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            HStack(spacing: 0) {
                ToolbarIconButton(
                    systemName: "wand.and.stars",
                    action: prettifyCode,
                    disabled: sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || showingInlineDiff,
                )
                .keyboardShortcut("i", modifiers: [.command])
                .customHelp(
                    formatActionLabel,
                    shortcut: KeyboardShortcut(
                        modifiers: [.command],
                        key: "i"
                    )
                )
                
                // Add to Favorites button
                //                ToolbarIconButton(
                //                    systemName: "heart",
                //                    action: addToFavorites,
                //                    disabled: sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                //                    tooltip: "Add to Favorites"
                //                )
            }

            aiErrorSuggestionToggle
            
            
            // Database/schema selection button (secondary style)
            Menu {
                if usesSchemaPicker {
                    if !availableSchemas.isEmpty {
                        ForEach(availableSchemas, id: \.name) { schema in
                            Button(schema.name) {
                                selectedSchema = schema.name
                            }
                        }
                    } else {
                        Text("No schemas available")
                            .foregroundColor(.secondary)
                    }
                } else {
                    if !availableDatabases.isEmpty {
                        ForEach(availableDatabases, id: \.name) { database in
                            Button(database.name) {
                                selectedDatabase = database.name
                            }
                        }
                    } else {
                        Text("No databases available")
                            .foregroundColor(.secondary)
                    }
                }
            } label: {
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(usesSchemaPicker ? "Schema: " : "Database: ")
                        Text(usesSchemaPicker ? selectedSchema : selectedDatabase)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
                .font(.system(size: 12))
                .frame(minHeight: ToolbarMetrics.controlHeight)
                .padding(.horizontal, ToolbarMetrics.horizontalPadding)
                .foregroundStyle(.secondary)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(.rect(cornerRadius: ToolbarMetrics.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                        .stroke(.separator, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .fixedSize()

            Button(action: {
                executeQuery()
            }) {
                HStack(spacing: 8) {
                    Text(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Run" : "Run Selection")
                        .lineLimit(1)
                    
                    if isExecuting {
                        ProgressView()
                            .controlSize(.small)
                            .colorMultiply(.white)
                            .scaleEffect(0.7)
                            .padding(.horizontal, 4)
                    } else {
                        Text("⌘⏎")
                            .fontWeight(.medium)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(minHeight: ToolbarMetrics.controlHeight)
                .padding(.horizontal, ToolbarMetrics.horizontalPadding)
                .foregroundStyle(Color(.textBackgroundColor))
                .background(Color.primaryButton)
                .clipShape(.rect(cornerRadius: ToolbarMetrics.cornerRadius))
                .fixedSize()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(PlainButtonStyle())
            .disabled((sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isExecuting || showingInlineDiff)
        }
        .padding(.leading)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }

    private var aiErrorSuggestionToggle: some View {
        Button {
            showAIErrorSuggestions.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                    .fill(showAIErrorSuggestions ? Color(NSColor.controlBackgroundColor) : Color.clear)

                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(showAIErrorSuggestions ? .primary : .secondary)
            }
            .frame(width: ToolbarMetrics.controlHeight, height: ToolbarMetrics.controlHeight)
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                    .stroke(.separator, lineWidth: showAIErrorSuggestions ? 0.5 : 0)
            )
            .contentShape(.rect(cornerRadius: ToolbarMetrics.cornerRadius))
        }
        .buttonStyle(.plain)
        .customHelp(showAIErrorSuggestions ? "Turn off AI error suggestions" : "Turn on AI error suggestions")
    }
    
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()

    private func openAICommandPrompt() {
        initialCursorLineNumber = cursorLineNumber + 1
        showAICommandPrompt = true
    }

    private func postSwitchDatabaseShortcut() {
        guard let window = editorWindow ?? NSApp.keyWindow else { return }
        NotificationCenter.default.post(name: .switchDatabaseShortcut, object: window)
    }
    
    private var cursorLineNumber: Int {
        guard !position.selections.isEmpty else { return 0 }
        let cursorPosition = position.selections[0].location
        let textUpToCursor = String(sqlQuery.prefix(cursorPosition))
        return textUpToCursor.components(separatedBy: .newlines).count - 1
    }
    
    private var selectedText: String {
        guard !position.selections.isEmpty else { return "" }
        let selection = position.selections[0]
        guard selection.length > 0, selection.location + selection.length <= sqlQuery.count else { return "" }
        
        let startIndex = sqlQuery.index(sqlQuery.startIndex, offsetBy: selection.location)
        let endIndex = sqlQuery.index(startIndex, offsetBy: selection.length)
        return String(sqlQuery[startIndex..<endIndex])
    }
    
    private var usesJavaScriptFormatter: Bool {
        switch instance.connection.databaseType {
        case .convex, .mongodb:
            return true
        default:
            return false
        }
    }

    private var aiFixLabel: String {
        switch instance.connection.databaseType {
        case .convex:
            return "Convex"
        case .mongodb:
            return "MongoDB"
        case .redis:
            return "Redis"
        default:
            return "SQL"
        }
    }

    private var formatActionLabel: String {
        usesJavaScriptFormatter ? "Format Query" : "Format SQL"
    }

    private var placeholderIntroText: String {
        switch instance.connection.databaseType {
        case .convex:
            return "Start writing a Convex query or type"
        case .mongodb:
            return "Start writing a MongoDB query or type"
        case .redis:
            return "Start writing Redis commands or type"
        default:
            return "Start writing SQL or type"
        }
    }

    private var emptyStateIntroText: String {
        switch instance.connection.databaseType {
        case .convex, .mongodb, .redis:
            return "Write a query and press"
        default:
            return "Write a SQL query and press"
        }
    }

    private var editorLanguage: LanguageConfiguration {
        switch instance.connection.databaseType {
        case .convex:
            return .javascript()
        case .mongodb:
            return .mongodb()
        default:
            return .sqlite(sqlLanguageService)
        }
    }

    private var sqlEditor: some View {
        ZStack(alignment: .topLeading) {
            CodeEditor(text: $sqlQuery, position: $position, messages: $messages, language: editorLanguage, autoFocus: true)
                .environment(\.codeEditorTheme, transparentTheme)
                .environment(\.codeEditorLayoutConfiguration, .init(wrapText: true))

            // Placeholder text
            if sqlQuery.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text(placeholderIntroText)
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.system(.body, design: .monospaced))

                    Text("⌘L")
                        .font(.callout)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                        .cornerRadius(4)

                    Text("to generate a query")
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.leading, 38)
                .allowsHitTesting(false)
            }

            // AI Command Prompt
            if showAICommandPrompt {
                AICommandPrompt(
                    isPresented: $showAICommandPrompt,
                    generatedQuery: $sqlQuery,
                    cursorLineNumber: initialCursorLineNumber,
                    selectedText: selectedText
                )
                .padding(.top, 8)
                .padding(.leading, 38)
                .transition(.move(edge: .bottom))
                .animation(.easeInOut(duration: 0.3), value: showAICommandPrompt)
            }
        }
        .padding(.top, 10)
    }
    
    private var transparentTheme: Theme {
        var theme = colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
        theme.backgroundColour = NSColor.clear
        return theme
    }
    
    private var resultsToolbar: some View {
        HStack {
            Text("Results")
                .font(.headline)

            Spacer()

            switch viewState {
            case .idle:
                Text("Ready")
                    .foregroundColor(.secondary)
            case .loading:
                Text("Executing...")
                    .foregroundColor(.secondary)
            case .loaded(let results):
                if results.count == 1 {
                    Text("\(results[0].totalCount) rows")
                        .foregroundColor(.secondary)
                } else {
                    Text("\(results.count) result sets")
                        .foregroundColor(.secondary)
                }
            case .error:
                Text("Error")
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var resultsContent: some View {
        Group {
            switch viewState {
            case .idle:
                emptyState
            case .loaded(let results):
                VStack(spacing: 0) {
                    if results.count > 1 {
                        resultsTabBar(results: results)
                        Divider()
                    }
                    if selectedResultIndex < results.count {
                        resultTable(result: results[selectedResultIndex])
                    } else if let firstResult = results.first {
                        resultTable(result: firstResult)
                    }
                }
            case .loading:
                EmptyView()
            case .error(let message):
                errorState(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultsTabBar(results: [QueryResult]) -> some View {
        ResultsPillTabBar(
            results: results,
            selectedIndex: $selectedResultIndex
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

struct ResultsPillTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let results: [QueryResult]
    @Binding var selectedIndex: Int
    @Namespace private var animation

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                glassTabContainer
                    .glassEffect(.regular.tint(Color(.controlColor).opacity(0.15)), in: .capsule)
            } else {
                legacyTabContainer
                    .background(legacyContainerFill)
                    .clipShape(.rect(cornerRadius: ResultsPillTabBarMetrics.outerCornerRadius))
            }
        }
    }

    @available(macOS 26, *)
    private var glassTabContainer: some View {
        HStack(spacing: 3) {
            ForEach(results.indices, id: \.self) { index in
                ResultPillTab(
                    index: index,
                    rowCount: results[index].totalCount,
                    isSelected: selectedIndex == index,
                    animation: animation,
                    useCapsuleStyle: true,
                    onSelect: {
                        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                            selectedIndex = index
                        }
                    }
                )
            }
        }
        .padding(4)
    }

    private var legacyTabContainer: some View {
        HStack(spacing: 0) {
            ForEach(results.indices, id: \.self) { index in
                ResultPillTab(
                    index: index,
                    rowCount: results[index].totalCount,
                    isSelected: selectedIndex == index,
                    animation: animation,
                    useCapsuleStyle: false,
                    onSelect: {
                        withAnimation(ResultsPillTabBarMetrics.selectionAnimation) {
                            selectedIndex = index
                        }
                    }
                )
            }
        }
        .padding(ResultsPillTabBarMetrics.containerPadding)
        .frame(minHeight: ResultsPillTabBarMetrics.legacyOuterHeight)
    }

    private var legacyContainerFill: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.2)
            : Color.black.opacity(0.04)
    }
}

struct ResultPillTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    let index: Int
    let rowCount: Int
    let isSelected: Bool
    let animation: Namespace.ID
    var useCapsuleStyle = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ResultsPillTabBarMetrics.labelSpacing) {
                Text("Result \(index + 1)")
                    .font(.system(size: useCapsuleStyle ? 13 : 11, weight: useCapsuleStyle ? .regular : .medium))
                    .lineLimit(1)

                Text("(\(rowCount.formatted()))")
                    .font(.system(size: useCapsuleStyle ? 12 : 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, useCapsuleStyle ? 12 : ResultsPillTabBarMetrics.horizontalPadding)
            .padding(.vertical, useCapsuleStyle ? 6 : 0)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(minHeight: useCapsuleStyle ? nil : ResultsPillTabBarMetrics.legacyButtonHeight)
            .background(selectionBackground)
            .contentShape(useCapsuleStyle ? AnyShape(.capsule) : AnyShape(.rect(cornerRadius: ResultsPillTabBarMetrics.innerCornerRadius)))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ResultsPillTabBarMetrics.hoverAnimation) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if useCapsuleStyle {
            if isSelected {
                Capsule()
                    .fill(capsuleSelectedFill)
                    .matchedGeometryEffect(id: "pill", in: animation)
            } else if isHovering {
                Capsule()
                    .fill(capsuleHoverFill)
            }
        } else {
            if isSelected {
                RoundedRectangle(cornerRadius: ResultsPillTabBarMetrics.innerCornerRadius, style: .continuous)
                    .fill(legacySelectedFill)
                    .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 0)
                    .matchedGeometryEffect(id: "pill", in: animation)
            }
        }
    }

    private var capsuleSelectedFill: Color {
        colorScheme == .dark
            ? Color(white: 0.22)
            : Color(white: 0.898)
    }

    private var capsuleHoverFill: Color {
        colorScheme == .dark
            ? Color(white: 0.17)
            : Color(white: 0.949)
    }

    private var legacySelectedFill: Color {
        colorScheme == .dark
            ? Color(.controlColor).opacity(0.3)
            : .white
    }
}

extension SQLEditorView {
    private var emptyState: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(emptyStateIntroText)
                    .font(.body)
                    .foregroundColor(.secondary.opacity(0.7))
                
                Text("⌘⏎")
                    .font(.callout)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                    .cornerRadius(4)
                
                Text("to execute")
                    .font(.body)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateText: AttributedString {
        var text = AttributedString()
        
        if let range = text.range(of: "⌘⏎") {
            text[range].foregroundColor = .primary
            text[range].font = .system(size: 56, weight: .bold)
        }
        
        return text
    }
    
    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.top, 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Check if this is a DatabaseError with rich information
                    if let error = lastError as? DatabaseError {
                        // Main error message
                        HStack {
                            Text("Error:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                            
                            Text(message.sentenceCase)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        
                        // Show position indicator if available
                        if let position = error.position, let query = error.query {
                            VStack(alignment: .leading, spacing: 2) {
                                let (contextLines, caretLine) = buildPositionIndicatorParts(position: position, query: query)
                                
                                // Show context lines in secondary color
                                if !contextLines.isEmpty {
                                    Text(contextLines)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                // Show caret line in red
                                Text(caretLine)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        // Show hint if available
                        if let hint = error.hint, !hint.isEmpty {
                            Text("Hint: \(hint)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                    } else {
                        // Fallback for non-DatabaseError errors
                        HStack {
                            Text("Error:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                            
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        
                    }
                }
                
                Spacer()
            }
            .padding(12)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    
    private func resultTable(result: QueryResult) -> some View {
        Group {
            if result.columns.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.top, 1)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Query executed successfully")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Text("No results returned")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                TableListViewController(
                    queryResult: result,
                    tableName: "SQL Query Result",
                    cacheNamespace: UUID().uuidString,
                    showPaddingRows: false
                )
            }
        }
    }
    
    private func executeQuery() {
        guard !showingInlineDiff else { return }

        let queryToExecute: String
        let trimmedSelectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedSelectedText.isEmpty {
            queryToExecute = trimmedSelectedText
        } else {
            queryToExecute = sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !queryToExecute.isEmpty else { return }

        if let request = QueryAlertPolicy.confirmationRequest(
            for: queryToExecute,
            connection: instance.connection
        ) {
            pendingConfirmation = request
            return
        }

        runQuery(queryToExecute)
    }

    private func runQuery(_ queryToExecute: String) {
        isExecuting = true
        viewState = .loading
        lastError = nil
        selectedResultIndex = 0

        Task {
            let startTime = Date()

            do {
                let results = try await instance.databaseService.executeRawQuery(queryToExecute, databaseSchema: selectedExecutionSchema)

                let executionTime = Date().timeIntervalSince(startTime)

                await MainActor.run {
                    viewState = .loaded(results)
                    lastExecutionTime = executionTime
                    lastRowCount = results.reduce(0) { $0 + $1.totalCount }
                }

                try? await Task.sleep(for: .milliseconds(250))

                await MainActor.run {
                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    viewState = .error(error.localizedDescription)
                    isExecuting = false
                    lastError = error
                    aiErrorSuggestion = nil
                }

                await getAIErrorSuggestion(for: queryToExecute, error: error)
            }
        }
    }
    
    private func getAIErrorSuggestion(for query: String, error: Error) async {
        // Suggestions are automatic, not user-initiated — without a key there is
        // nothing to nag about, so skip instead of flashing an empty popup.
        let shouldShowSuggestion = await MainActor.run {
            enableAIFeatures && showAIErrorSuggestions && AISetup.isConfigured
        }
        guard shouldShowSuggestion else { return }

        await MainActor.run {
            isLoadingAISuggestion = true
            showAIErrorSuggestion = true
            originalQueryBeforeSuggestion = query
            originalFullEditorContent = sqlQuery
            executedQueryPosition = position

            // Show loading state in editor - keep original query visible
            sqlQuery = query
            showingInlineDiff = true

            // Clear any existing messages
            messages = Set()
        }

        do {
            let suggestion = try await performAIErrorAnalysis(query: query, error: error)
            await MainActor.run {
                aiErrorSuggestion = suggestion
                isLoadingAISuggestion = false
                sqlQuery = formatDiffText(original: originalQueryBeforeSuggestion, suggested: suggestion)
            }

            try? await Task.sleep(for: .milliseconds(100))

            await MainActor.run {
                applyDiffHighlighting(original: originalQueryBeforeSuggestion, suggested: suggestion)
            }
        } catch {
            await MainActor.run {
                isLoadingAISuggestion = false
                showAIErrorSuggestion = false
                showingInlineDiff = false
                // Revert to original query on error
                sqlQuery = originalQueryBeforeSuggestion
                messages = Set()
            }
        }
    }
    
    private func performAIErrorAnalysis(query: String, error: Error) async throws -> String {
        let databaseType = instance.connection.databaseType.rawValue
        return try await AIService.analyzeError(
            query: query,
            error: error,
            databaseType: databaseType,
            databaseService: instance.databaseService,
            schemaName: selectedExecutionSchema
        )
    }
    
    private func formatDiffText(original: String, suggested: String?) -> String {
        guard let suggested = suggested else {
            return original
        }
        
        // Format both queries using the editor's language-aware formatter for accurate comparison
        let formattedOriginal = formatQuery(original)
        let formattedSuggested = formatQuery(suggested)
        
        // Create git-like diff showing only changed lines
        let originalLines = formattedOriginal.components(separatedBy: .newlines)
        let suggestedLines = formattedSuggested.components(separatedBy: .newlines)
        
        var diffLines: [String] = []
        let maxLines = max(originalLines.count, suggestedLines.count)
        
        for i in 0..<maxLines {
            let originalLine = i < originalLines.count ? originalLines[i] : ""
            let suggestedLine = i < suggestedLines.count ? suggestedLines[i] : ""
            
            // Only show lines that are different
            if originalLine != suggestedLine {
                // Add original line (will be marked red)
                if !originalLine.isEmpty {
                    diffLines.append(originalLine)
                }
                // Add suggested line (will be marked green)
                if !suggestedLine.isEmpty {
                    diffLines.append(suggestedLine)
                }
            } else if !originalLine.isEmpty {
                // Keep unchanged lines as context
                diffLines.append(originalLine)
            }
        }
        
        return diffLines.joined(separator: "\n")
    }
    
    private func formatQuery(_ query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return query }

        if usesJavaScriptFormatter { return JSFormatter.format(trimmedQuery) }
        
        // Determine the SQL dialect based on the database type
        let dialect: SQLDialect
        switch instance.connection.databaseType {
        case .postgres:
            dialect = .postgresql
        case .mongodb:
            dialect = .sqlite // MongoDB uses SQL-like queries, use SQLite as fallback
        case .mysql:
            dialect = .mysql
        case .sqlite:
            dialect = .sqlite
        default:
            dialect = .sqlite // Default fallback
        }
        
        // Configure formatting options for consistent diff comparison
        let options = SQLFormatOptions(
            tabWidth: 2,
            useTabs: false,
            keywordCase: .upper,
            dataTypeCase: .upper,
            functionCase: .upper,
            linesBetweenQueries: 1
        )
        
        // Format using the SQLFormatter
        return SQLFormatter.format(trimmedQuery, dialect: dialect, options: options)
    }
    
    private func applyDiffHighlighting(original: String, suggested: String?) {
        guard let suggested = suggested else { return }
        
        // Format both queries for accurate comparison (same as in formatDiffText)
        let formattedOriginal = formatQuery(original)
        let formattedSuggested = formatQuery(suggested)
        
        // Parse the formatted queries to track line types
        let originalLines = formattedOriginal.components(separatedBy: .newlines)
        let suggestedLines = formattedSuggested.components(separatedBy: .newlines)
        let displayedLines = sqlQuery.components(separatedBy: .newlines)
        
        // Clear any existing messages first
        messages = Set()
        var newMessages = Set<TextLocated<Message>>()
        
        // Track which lines in the display are original vs suggested
        var displayLineIndex = 0
        let maxLines = max(originalLines.count, suggestedLines.count)
        
        for i in 0..<maxLines {
            let originalLine = i < originalLines.count ? originalLines[i] : ""
            let suggestedLine = i < suggestedLines.count ? suggestedLines[i] : ""
            
            if originalLine != suggestedLine {
                // Lines are different - show both with colors
                
                // Add original line (red)
                if !originalLine.isEmpty && displayLineIndex < displayedLines.count {
                    let location = TextLocation(zeroBasedLine: displayLineIndex, column: 0)
                    let message = Message(
                        category: .error, // Red for original
                        length: displayedLines[displayLineIndex].count,
                        summary: "",
                        description: nil
                    )
                    newMessages.insert(TextLocated(location: location, entity: message))
                    displayLineIndex += 1
                }
                
                // Add suggested line (green)
                if !suggestedLine.isEmpty && displayLineIndex < displayedLines.count {
                    let location = TextLocation(zeroBasedLine: displayLineIndex, column: 0)
                    let message = Message(
                        category: .live, // Green for suggestion
                        length: displayedLines[displayLineIndex].count,
                        summary: "",
                        description: nil
                    )
                    newMessages.insert(TextLocated(location: location, entity: message))
                    displayLineIndex += 1
                }
            } else if !originalLine.isEmpty {
                displayLineIndex += 1
            }
        }
        
        messages = newMessages
    }
    
    private func acceptAISuggestion() {
        guard let suggestion = aiErrorSuggestion else { return }
        applyAISuggestionToEditor(suggestion: suggestion)
        cleanupSuggestionState()
        // Execute the corrected query immediately
        executeQuery()
    }
    
    private func acceptAISuggestionOnly() {
        guard let suggestion = aiErrorSuggestion else { return }
        applyAISuggestionToEditor(suggestion: suggestion)
        cleanupSuggestionState()
    }
    
    private func applyAISuggestionToEditor(suggestion: String) {
        // If we have a specific selection that was executed, replace only that part
        if !executedQueryPosition.selections.isEmpty && executedQueryPosition.selections[0].length > 0 {
            let selection = executedQueryPosition.selections[0]
            
            // Ensure the selection is still valid for the original content
            guard selection.location + selection.length <= originalFullEditorContent.count else {
                // Fallback: replace entire content if selection is invalid
                sqlQuery = suggestion
                return
            }
            
            // Replace only the selected part with the suggestion
            let startIndex = originalFullEditorContent.index(originalFullEditorContent.startIndex, offsetBy: selection.location)
            let endIndex = originalFullEditorContent.index(startIndex, offsetBy: selection.length)
            
            var newContent = originalFullEditorContent
            newContent.replaceSubrange(startIndex..<endIndex, with: suggestion)
            sqlQuery = newContent
            
            // Update the position to select the new suggestion
            let newSelectionRange = NSRange(location: selection.location, length: suggestion.count)
            position = CodeEditor.Position(selections: [newSelectionRange], verticalScrollPosition: position.verticalScrollPosition)
            
        } else {
            // No specific selection was made, replace entire content
            sqlQuery = suggestion
        }
    }
    
    private func rejectAISuggestion() {
        // Restore the original full editor content, not just the executed query
        sqlQuery = originalFullEditorContent
        position = executedQueryPosition
        cleanupSuggestionState()
    }
    
    private func cleanupSuggestionState() {
        aiErrorSuggestion = nil
        showAIErrorSuggestion = false
        showingInlineDiff = false
        originalQueryBeforeSuggestion = ""
        originalFullEditorContent = ""
        executedQueryPosition = CodeEditor.Position()
        messages = Set()
    }
    
    private func prettifyCode() {
        guard !showingInlineDiff else { return }

        let trimmedQuery = sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        if usesJavaScriptFormatter {
            sqlQuery = JSFormatter.format(trimmedQuery)
        } else {
            sqlQuery = formatQuery(trimmedQuery)
        }
    }
    
    private func addToFavorites() {
        // TODO: Implement add to favorites functionality
        // For now, just show that it was triggered
        let trimmedQuery = sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            // This would typically save to UserDefaults or Core Data
        }
    }
    
    private func getCurrentQuery() -> String? {
        let trimmed = sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func buildPositionIndicatorParts(position: Int, query: String) -> (contextLines: String, caretLine: String) {
        // Handle multiline queries by finding the correct line and column
        let lines = query.components(separatedBy: .newlines)
        var currentPosition = 0
        
        for (lineIndex, line) in lines.enumerated() {
            let lineLength = line.count + 1 // +1 for newline character
            
            if currentPosition + lineLength > position {
                // The error is on this line
                let columnPosition = position - currentPosition
                let spaces = String(repeating: " ", count: max(0, columnPosition))
                
                // Build context lines (everything except the caret)
                var contextLines = ""
                
                // Add previous lines for context (max 2 lines before)
                let startLine = max(0, lineIndex - 2)
                for i in startLine..<lineIndex {
                    if !contextLines.isEmpty { contextLines += "\n" }
                    contextLines += lines[i]
                }
                
                // Add the error line
                if !contextLines.isEmpty { contextLines += "\n" }
                contextLines += line
                
                // Add next lines for context (max 2 lines after)
                let endLine = min(lines.count, lineIndex + 3)
                for i in (lineIndex + 1)..<endLine {
                    contextLines += "\n" + lines[i]
                }
                
                // Build the red caret line
                let caretLine = "\(spaces)^"
                
                return (contextLines, caretLine)
            }
            
            currentPosition += lineLength
        }
        
        // Fallback to original behavior if position not found
        let spaces = String(repeating: " ", count: max(0, position - 1))
        return (query, "\(spaces)^")
    }
    
    private func buildPositionIndicator(position: Int, query: String) -> String {
        let (contextLines, caretLine) = buildPositionIndicatorParts(position: position, query: query)
        return "\(contextLines)\n\(caretLine)"
    }
    
    private func loadAvailableDatabases() {
        Task {
            if usesSchemaPicker {
                do {
                    let schemas = try await instance.databaseService.getInformationSchema()
                    await MainActor.run {
                        self.availableSchemas = schemas
                        let preferredSchema = instance.selectedTab?.databaseSchema
                            ?? instance.databaseService.currentSchema
                            ?? "public"
                        self.selectedSchema = schemas.first(where: { $0.name == preferredSchema })?.name
                            ?? schemas.first(where: { $0.name == "public" })?.name
                            ?? schemas.first?.name
                            ?? ""
                    }
                } catch {
                    await MainActor.run {
                        self.availableSchemas = []
                        self.selectedSchema = instance.selectedTab?.databaseSchema
                            ?? instance.databaseService.currentSchema
                            ?? "public"
                    }
                }
                return
            }

            await MainActor.run {
                // Show only the current connected database
                if let currentDatabase = instance.databaseService.currentDatabase {
                    self.availableDatabases = [currentDatabase]
                    self.selectedDatabase = currentDatabase.name
                } else {
                    self.availableDatabases = []
                    self.selectedDatabase = ""
                }
            }
        }
    }

    @MainActor
    private func configureSQLLanguageServiceIfNeeded() {
        guard instance.connection.databaseType != .convex, instance.connection.databaseType != .mongodb else {
            sqlLanguageService = nil
            return
        }

        if sqlLanguageService == nil {
            sqlLanguageService = SQLAutocompleteLanguageService(connection: instance)
        }
    }

    private func loadInitialQueryFromTab() {
        if let tab = instance.selectedTab,
           tab.type == .sqlEditor,
           let query = tab.initialQuery {
            sqlQuery = query
            tab.initialQuery = nil
            if tab.autoRunInitialQuery {
                tab.autoRunInitialQuery = false
                // loadAvailableDatabases() resolves selectedSchema
                // asynchronously, so seed it from the tab first — otherwise
                // this auto-run would execute with no schema.
                if usesSchemaPicker, let schema = tab.databaseSchema, !schema.isEmpty {
                    selectedSchema = schema
                }
                executeQuery()
            }
        }

        if sqlQuery.isEmpty && instance.connection.databaseType == .convex {
            sqlQuery = """
            export default query({
              handler: async (ctx) => {
                console.log("Write and test your query function here!");
                return await ctx.db.query("table_name").take(10);
              },
            })
            """
        }
    }
}

enum SQLEditorViewState: Equatable {
    case idle
    case loading
    case loaded([QueryResult])
    case error(String)

    static func == (lhs: SQLEditorViewState, rhs: SQLEditorViewState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.loaded(let lhsResults), .loaded(let rhsResults)):
            guard lhsResults.count == rhsResults.count else { return false }
            for (lhs, rhs) in zip(lhsResults, rhsResults) {
                if lhs.totalCount != rhs.totalCount { return false }
            }
            return true
        default:
            return false
        }
    }
}
