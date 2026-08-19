//
//  AISetupPrompt.swift
//  Quarry
//

import SwiftUI

/// Quarry is BYOK, so every AI surface can be reached before a key exists.
/// One place owns the copy and the way out so all of them say the same thing.
enum AISetup {
    static let title = "AI isn't set up yet"
    static let message = "Add your own Anthropic or OpenAI API key to start using AI."
    static let shortMessage = "Add an API key to use AI"
    static let actionTitle = "Open AI Settings"

    @MainActor
    static var isConfigured: Bool { LLM.isConfigured }

    @MainActor
    static func openSettings() {
        SettingsWindowController.shared.show(pane: .ai)
    }

    /// A vendor key can also be present but rejected, so call sites map a
    /// caught error here rather than only checking `isConfigured` up front.
    static func isMissingKey(_ error: Error) -> Bool {
        if case LLMError.missingAPIKey = error { return true }
        return false
    }

    /// User-facing text for any AI failure — the setup prompt when there is no
    /// key, otherwise the underlying description.
    static func description(for error: Error) -> String {
        if isMissingKey(error) { return message }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Inline notice

/// Compact one-line variant for tight surfaces (command prompts, action bars).
/// Renders as a plain error row when `isSetupIssue` is false.
struct AISetupNotice: View {
    let text: String
    var isSetupIssue: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSetupIssue ? "sparkles" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(isSetupIssue ? Color.secondary : Color.red)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if isSetupIssue {
                Button(AISetup.actionTitle) {
                    AISetup.openSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }
}
