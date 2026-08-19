//
//  QueryEditor.swift
//  Collection
//
//  Created by Fauzaan on 3/16/25.
//

import SwiftUI
import LanguageSupport
import MongoKitten

struct CreateEditor: View {
    // MARK: - Dependencies
    @Binding var showCreateDocumentSheet: Bool
    @Environment(ConnectionInstance.self) private var instance

    // MARK: - View State
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()
    @State private var isExpanded: Bool = false
    @State private var showEditor: Bool = false
    @State private var saveSuccess: Bool = false
    @State private var jsonDocument: String = "{\n  \n}"
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false
    
    // MARK: - Initialization
    init(showCreateDocumentSheet: Binding<Bool>) {
//        self._viewModel = State(initialValue: CreateEditorViewModel(documentListModel: documentListModel))
        self._showCreateDocumentSheet = showCreateDocumentSheet
    }
    
    // MARK: - Body
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            VStack {
                if isExpanded {
                    fullQueryEditorView()
                        .opacity(showEditor ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: showEditor)
                        .onTapOutside {
                            closeWithAnimation()
                        }
                        .onKeyPress(.escape) {
                            closeWithAnimation()
                            return .handled
                        }
                }
            }
            .fixedSize(horizontal: !isExpanded, vertical: !isExpanded)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .modifier(GlassBackgroundStyle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator, lineWidth: 1)
            )
        }
        .opacity(opacityValue)
        .onAppear {
            withAnimation(.spring(response: 0.3, blendDuration: 0.1)) {
                isExpanded = true
            }
            
            // This will run approximately when the animation finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                showEditor = true
            }
        }
    }
    
    @State private var opacityValue: Double = 1.0
    
    // MARK: - Private Methods
    private func closeWithAnimation() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            isExpanded = false
            opacityValue = 0.0
        }
        
        // Dismiss after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            showEditor = false
            showCreateDocumentSheet = false
            opacityValue = 1.0
        }
    }
    
    private func handleSave() {
        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }

            do {
                // Parse JSON
                guard let document = try? MongoKitten.Document(fromJSON: jsonDocument) else {
                    throw MongoError.invalidData
                }

                // Convert to dictionary
                var documentData: [String: Any] = [:]
                for (key, value) in document {
                    documentData[key] = value
                }

                // Get collection name from selectedTab
                guard let collectionName = instance.selectedTab?.name else {
                    throw DatabaseError.operationFailed("No collection selected")
                }

                // Create document
                try await instance.databaseService.createDocument(
                    in: collectionName,
                    databaseSchema: nil,
                    document: documentData
                )

                // Show success
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.2)) {
                        saveSuccess = true
                    }
                }

                // Wait for success animation
                try? await Task.sleep(for: .milliseconds(800))

                // Close editor
                await MainActor.run {
                    closeWithAnimation()
                }

                // Refresh document list
                NotificationCenter.default.post(
                    name: .tableRefresh,
                    object: nil,
                    userInfo: ["tableName": collectionName]
                )

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    
    private func fullQueryEditorView() -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Insert Document")
                    .font(.headline)
                    .fontWeight(.regular)
                    .foregroundColor(.secondary)

                Spacer()

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Button(action: handleSave) {
                    ZStack {
                        ProgressView()
                            .controlSize(.mini)
                            .opacity(isLoading ? 1 : 0)
                            .animation(.easeIn, value: isLoading)

                        Text("Save")
                    }
                    .frame(minWidth: 80)
                }
                .if(saveSuccess) { view in
                    view.buttonStyle(SuccessButtonStyle())
                } else: { view in
                    view.buttonStyle(OutlineButtonStyle())
                }
                .disabled(isLoading || saveSuccess)
            }
            .padding([.top, .horizontal, .bottom], 8)

            CodeEditor(text: $jsonDocument, position: $position, messages: $messages, language: .mongodb())
                .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
                .environment(\.codeEditorLayoutConfiguration, .init(wrapText: true))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.separator, lineWidth: colorScheme == .dark ? 1 : 0.5)
                        .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 2)
                )
                .padding(.bottom, 2)
                .cornerRadius(10)
                .frame(height: isExpanded ? 320 : 0)
                .disabled(isLoading || saveSuccess)
        }
    }
}

// MARK: - Button Styles
struct SuccessButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    Color.green
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
