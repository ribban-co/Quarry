//
//  AISearchView.swift
//  Collection
//
//  Created by Fauzaan on 3/14/25.
//

import SwiftUI
import Combine

struct AISearchView: View {
    @Binding var filter: String
    let focusRequest: Int
    let showQueryEditor: Bool
    let tableName: String
    @Binding var isSubmitAnimating: Bool
    @Binding var processingStage: ProcessingStage
    let onBack: () -> Void
    let onLoadDocuments: (_ filter: String) -> Void
    let onRefresh: () -> Void
    
    @Environment(ConnectionInstance.self) private var instance
    @FocusState private var isSearchFocused: Bool
    @State private var search: String = ""
    
    var body: some View {
        VStack(spacing: 6) {
            // First row: Full width input field
            mainInputSection
                .padding(.leading, 8)
            
            // Second row: Action buttons
            actionButtonsSection
        }
        .padding(.top, 10)
        .padding(10)
        // Add refresh keyboard shortcut
        .overlay(
            Button("") {
                onRefresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        )
        .frame(maxWidth: 500)
        .task(id: focusRequest) {
            await focusSearchField()
        }
        .task(id: showQueryEditor) {
            await focusSearchField()
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var mainInputSection: some View {
        HStack {
            searchTextField
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Left side tools
            leftToolsSection
                .padding(.bottom, 4)
                .padding(.leading, 6)
            
            Spacer()
            
            // Right side controls
            rightControlsSection
        }
    }
    
    @ViewBuilder
    private var leftToolsSection: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "table")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(tableName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator)
            )
            .customHelp("This table schema is shared with LLM provider", delay: 0.2, position: .top, shortcut: nil, spacing: 4)
        }
    }
    
    @State var showErrorAlert = false

    @ViewBuilder
    private var rightControlsSection: some View {
        HStack(alignment: .bottom) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Text("Close")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("ESC")
                        .font(.caption2)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.controlColor).opacity(0.3))
                        )
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(AIBackButtonStyle())
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The current driver doesn’t support AI search queries")
            }
            
            if processingStage != .idle {
                Button(action: {
                    cancelProcessing()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(ChatSendButtonStyle())
            } else {
                Button(action: {
                    Task {
                        guard instance.databaseType != nil else {
                            showErrorAlert = true
                            return
                        }

                        await processNaturalLanguageQuery(search: search)
                    }
                }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(ChatSendButtonStyle())
                .disabled(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    

    
    @ViewBuilder
    private var searchTextField: some View {
        TextField("Ask what to find (e.g. id: 2)...", text: $search)
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .onSubmit {
                Task {
                    await processNaturalLanguageQuery(search: search)
                }
            }
            .disabled(processingStage != .idle)
            .padding(.bottom, processingStage != .idle ? 2 : 0)
    }

    @MainActor
    private func focusSearchField() async {
        isSearchFocused = false
        await Task.yield()

        for _ in 0..<8 {
            guard !Task.isCancelled, processingStage == .idle else { return }
            isSearchFocused = true
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
    
    // MARK: - Processing Logic
    
    private func cancelProcessing() {
        processingStage = .idle
        // Cancel any ongoing AI request if possible
    }
    
    // MARK: - AI Request Methods
    
    /// Submits a natural language query to AI service and processes the result
    private func processNaturalLanguageQuery(search: String) async {
        guard !search.isEmpty else { return }

        await MainActor.run {
            processingStage = .writingQuery
        }

        do {
            filter = try await performAIQuery(databaseService: instance.databaseService, search: search)

            await processQueryResult(filter)
        } catch {
            await handleQueryError(error)
        }
    }
    
    private func performAIQuery(databaseService: DatabaseService, search: String) async throws -> String {
        guard let selectedTab = instance.selectedTab?.name else {
            throw LLMError.invalidResponse
        }

        let prompt = try await instance.databaseService.buildSystemPrompt(for: selectedTab, databaseSchema: instance.selectedTab?.databaseSchema)

        let response = try await LLM.chatCompletion(
            messages: [LLMChatMessage(role: .user, content: search)],
            systemPrompt: prompt,
            tools: [],
            maxTokens: 4096,
            thinkingMode: .disabled
        )

        return response.assistantMessage.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    @MainActor
    private func processQueryResult(_ result: String) async {
        search = ""

        onLoadDocuments(result)
        
        // Trigger scale animation on submit
        withAnimation(.easeInOut(duration: 0.15)) {
            isSubmitAnimating = true
        }
        
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.15)) {
                isSubmitAnimating = false
                processingStage = .idle
                isSearchFocused = true
            }
        }
        
    }
    
    @MainActor
    private func handleQueryError(_ error: Error) async {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            debugLog("Error: \(description)")
        } else {
            debugLog("Error: Could not create Message: \(error.localizedDescription)")
        }
        processingStage = .idle
    }
}


// MARK: - Processing Stage Enum
/// Represents the different stages of query processing
public enum ProcessingStage: Int {
    case idle = 0
    case writingQuery = 1
    case fetchingData = 2
    
    var description: String {
        switch self {
        case .idle:
            return ""
        case .writingQuery:
            return "Writing query"
        case .fetchingData:
            return "Fetching data"
        }
    }
}
