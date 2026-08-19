//
//  AICommandPrompt.swift
//  Quarry
//
//  Created by Claude on 9/3/25.
//

import SwiftUI

struct AICommandPrompt: View {
    @Environment(ConnectionInstance.self) private var instance
    @Binding var isPresented: Bool
    @Binding var generatedQuery: String
    let cursorLineNumber: Int
    let selectedText: String
    @State private var userPrompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?
    @State private var errorIsSetupIssue: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(selectedText.isEmpty ? "What do you want to generate?" : "What do you want to do with the selected query?", text: $userPrompt)
                .padding(.leading, 4)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onChange(of: userPrompt) { _, _ in
                    errorMessage = nil
                }
            
            HStack {
                // Primary action
                if !isGenerating {
                    Button(action: {
                        Task {
                            await generateCommand()
                        }
                    }) {
                        Text("Generate ⏎")
                    }
                    .buttonStyle(AICommandPromptPrimaryButtonStyle())
                    .disabled(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [])
                }
                
                // Secondary action
                Button(action: {
                    isPresented = false
                }) {
                    HStack(spacing: 4) {
                        Text("Cancel")
                        Text("ESC")
                            .opacity(0.6)
                    }
                }
                .buttonStyle(AICommandPromptSecondaryButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])
                
                if isGenerating {
                    ProgressView()
                        .controlSize(.mini)
                } else if let errorMessage {
                    AISetupNotice(text: errorMessage, isSetupIssue: errorIsSetupIssue)
                }
                
                if !isGenerating {
                    Button("") {
                        Task {
                            await generateCommand()
                        }
                    }
                    .hidden()
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
        .padding(10)
        .foregroundColor(.primary)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 0)
        .frame(width: 450)
        .offset(y: CGFloat(cursorLineNumber * 16)) // Position based on line number
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func generateCommand() async {
        let userMessage = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }

        guard await AISetup.isConfigured else {
            await MainActor.run {
                errorIsSetupIssue = true
                errorMessage = AISetup.shortMessage
            }
            return
        }

        isGenerating = true
        errorMessage = nil

        do {
            var result = ""
            var isFirstToken = true

            for try await chunk in AIService.generateSQL(
                prompt: userMessage,
                selectedText: selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selectedText,
                databaseService: instance.databaseService
            ) {
                result += chunk
                // Hide loading and close prompt on first token
                if isFirstToken {
                    await MainActor.run {
                        isGenerating = false
                        isPresented = false
                    }
                    isFirstToken = false
                }
                // Stream each chunk to the editor
                await MainActor.run {
                    generatedQuery = result
                }
            }

            errorMessage = nil
        } catch {
            await MainActor.run {
                isGenerating = false
                errorIsSetupIssue = AISetup.isMissingKey(error)
                errorMessage = errorIsSetupIssue ? AISetup.shortMessage : "Something went wrong. Please try again."
            }

            debugLog(error)
        }
    }
}
