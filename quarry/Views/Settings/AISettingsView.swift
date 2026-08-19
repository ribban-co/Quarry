//
//  AISettingsView.swift
//  Quarry
//

import SwiftUI

/// BYOK configuration: provider, API key (Keychain-backed via LLMSettings),
/// model selection, and an informational usage counter.
struct AISettingsView: View {
    @Bindable private var settings = LLMSettings.shared
    private let usageService = LLMTokenUsageService.shared

    @State private var apiKeyDraft = ""
    @State private var useCustomModel = false
    @State private var testState: TestState = .idle
    @FocusState private var apiKeyFieldFocused: Bool

    private static let customModelTag = "custom"

    private enum TestState: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            providerSection
            modelSection
            usageSection
        }
        .formStyle(.grouped)
        .onAppear {
            loadStateForSelectedProvider()
        }
        .onChange(of: settings.provider) { _, _ in
            // LLMSettings already reset the model; sync the key draft and picker.
            loadStateForSelectedProvider()
        }
    }

    // MARK: - Provider & API key

    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: $settings.provider) {
                ForEach(LLMProviderKind.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("API Key")
                Spacer()
                SecureField("\(settings.provider.keyPrefix)…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .focused($apiKeyFieldFocused)
                    .onSubmit { saveAPIKey() }
            }

            HStack {
                keyStatusLabel
                Spacer()
                Button("Get an API key") {
                    NSWorkspace.shared.open(settings.provider.consoleURL)
                }
                .buttonStyle(.link)
            }

            HStack {
                testConnectionButton
                Spacer()
                testResultLabel
            }
        }
        .onChange(of: apiKeyFieldFocused) { _, focused in
            if !focused { saveAPIKey() }
        }
    }

    @ViewBuilder
    private var keyStatusLabel: some View {
        if settings.hasAPIKey(for: settings.provider) {
            Label("Key saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Label("No key configured", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.brand)
                .font(.caption)
        }
    }

    private var testConnectionButton: some View {
        Button {
            testConnection()
        } label: {
            if testState == .running {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing…")
                }
            } else {
                Text("Test Connection")
            }
        }
        .disabled(testState == .running || !settings.hasAPIKey(for: settings.provider))
    }

    @ViewBuilder
    private var testResultLabel: some View {
        switch testState {
        case .idle, .running:
            EmptyView()
        case .success:
            Label("Connection works", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(3)
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        Section("Model") {
            Picker("Model", selection: modelPickerSelection) {
                ForEach(settings.provider.suggestedModels, id: \.self) { model in
                    Text(model).tag(model)
                }
                Divider()
                Text("Custom…").tag(Self.customModelTag)
            }

            if useCustomModel {
                HStack {
                    Text("Model ID")
                    Spacer()
                    TextField(settings.provider.defaultModel, text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }
        }
    }

    /// Maps the stored model onto the picker: a known id selects itself, an
    /// unknown one selects "Custom…" and reveals the free-form field.
    private var modelPickerSelection: Binding<String> {
        Binding(
            get: {
                useCustomModel ? Self.customModelTag : settings.model
            },
            set: { newValue in
                if newValue == Self.customModelTag {
                    useCustomModel = true
                } else {
                    useCustomModel = false
                    settings.model = newValue
                }
            }
        )
    }

    // MARK: - Usage

    private var usageSection: some View {
        Section("Usage") {
            let snapshot = usageService.latestSnapshot

            LabeledContent("Tokens this month") {
                Text(snapshot.usedTokens.formatted())
                    .monospacedDigit()
            }
            LabeledContent("Estimated cost") {
                Text(snapshot.usedCreditCents / 100, format: .currency(code: "USD"))
                    .monospacedDigit()
            }
            Text("Rough estimate of spend against your own API key. There is no cap — check your provider's console for exact billing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            // Refresh in case the month rolled over since the last request.
            _ = usageService.currentSnapshot()
        }
    }

    // MARK: - Actions

    private func loadStateForSelectedProvider() {
        apiKeyDraft = settings.apiKey(for: settings.provider) ?? ""
        useCustomModel = !settings.provider.suggestedModels.contains(settings.model)
        testState = .idle
    }

    private func saveAPIKey() {
        settings.setAPIKey(apiKeyDraft, for: settings.provider)
    }

    private func testConnection() {
        saveAPIKey()
        testState = .running
        Task {
            do {
                _ = try await LLM.chatCompletion(
                    messages: [LLMChatMessage(role: .user, content: "Hi")],
                    maxTokens: 8,
                    thinkingMode: .disabled
                )
                testState = .success
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview {
    AISettingsView()
        .frame(width: 500, height: 500)
}
