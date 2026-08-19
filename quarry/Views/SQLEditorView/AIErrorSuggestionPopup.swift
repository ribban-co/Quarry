//
//  AIErrorSuggestionPopup.swift
//  Quarry
//
//  Created by Claude on 1/4/25.
//

import SwiftUI

struct AIErrorSuggestionPopup: View {
    private static let actionButtonHeight: CGFloat = 18

    @Binding var isPresented: Bool
    @Binding var suggestion: String?
    let fixLabel: String
    let isLoading: Bool
    let onAcceptAndRun: () -> Void
    let onAcceptOnly: () -> Void
    let onReject: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Content
            if isLoading {
                HStack(spacing: 40) {
                    Text("Generating \(fixLabel) Fix")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 6)
                }
                .padding(.vertical, 8)
            } else if let suggestion = suggestion, !suggestion.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Action buttons
                    HStack(spacing: 8) {
                        Text("Possible fix")
                            .foregroundStyle(.secondary)
                        Spacer()
                        
                        Button(action: {
                            onAcceptAndRun()
                        }) {
                            Text("Accept & Run ⌘⏎")
                                .frame(minHeight: Self.actionButtonHeight)
                        }
                        .buttonStyle(AICommandPromptPrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: [.command])

                        Button(action: {
                            onReject()
                        }) {
                            HStack(spacing: 4) {
                                Text("Reject")
                                Text("ESC")
                                    .opacity(0.6)
                            }
                            .frame(minHeight: Self.actionButtonHeight)
                        }
                        .foregroundStyle(.secondary)
                        .buttonStyle(AICommandPromptSecondaryButtonStyle())
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                }.padding(.vertical, 6)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .frame(width: 400)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .animation(.easeInOut(duration: 0.2), value: suggestion)
    }
}

// MARK: - Button Styles

struct AIErrorSuggestionPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(.textBackgroundColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primaryButton)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct AIErrorSuggestionSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
