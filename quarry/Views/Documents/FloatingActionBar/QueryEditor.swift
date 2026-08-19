//
//  QueryEditor.swift
//  Collection
//
//  Created by Fauzaan on 3/16/25.
//

import SwiftUI
import LanguageSupport

struct QueryEditor: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Environment(ConnectionInstance.self) private var instance
    @Binding var showQueryEditor: Bool
    @Binding var filter: String
    let isLoading: Bool
    let totalCount: Int
    var totalRowCount: Int? = nil
    let onLoadDocuments: (_ filter: String?) -> Void
    
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()
    @State private var isExpanded: Bool = false
    @State private var showEditor: Bool = false

    private var editorLanguage: LanguageConfiguration {
        switch instance.connection.databaseType {
        case .convex:
            return .javascript()
        case .mongodb:
            return .mongodb()
        default:
            return .sqlite()
        }
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            VStack {
                if isExpanded {
                    fullQueryEditorView()
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
            .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator)
            )
            .cornerRadius(10)
        }
        .opacity(opacityValue)
        .onAppear {
            withAnimation(.spring(response: 0.3, blendDuration: 0.1)) {
                isExpanded = true
            }
            
            Task {
                try? await Task.sleep(for: .milliseconds(100))
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
        
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            showEditor = false
            showQueryEditor = false
            opacityValue = 1.0
        }
    }
    
    private func fullQueryEditorView() -> some View {
        VStack(spacing: 0) {
            // Query Editor Header
            HStack {
                Text("Query Editor")
                    .font(.headline)
                    .fontWeight(.regular)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Group {
                    if let totalRowCount, totalRowCount > totalCount {
                        Text("\(totalCount) of \(totalRowCount.formatted()) rows")
                    } else {
                        Text("\(totalCount) rows")
                    }
                }
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                
                Button(action: {}) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    filter = ""
                    onLoadDocuments(filter)
                }) {
                    Text("Clear")
                        .font(.system(size: 12))
                }
                .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)))
                .opacity(filter.isEmpty ? 0.5 : 1)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))
                .animation(.spring(response: 0.3), value: filter.isEmpty)
                
                Button(action: {
                    onLoadDocuments(filter)
                }) {
                    HStack {
                        Text("Run")

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .colorMultiply(.black)
                                .padding(.horizontal, 4.5)
                        } else {
                            Text("⌘⏎")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color(.textBackgroundColor))
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primaryButton)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isLoading)
                .customHelp("Run current query", delay: 1.5, position: .left, shortcut: KeyboardShortcut(
                    modifiers: [.command],
                    key: "Enter"
                ), spacing: 8)
            }
            .padding([.top, .horizontal, .bottom], 8)
            
            CodeEditor(text: $filter, position: $position, messages: $messages, language: editorLanguage, autoFocus: true)
                .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
                .environment(\.codeEditorLayoutConfiguration, .init(wrapText: true))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.separator)
                )
                .padding(.bottom, 2)
                .frame(height: 220)
                .cornerRadius(10)
        }
    }
}
