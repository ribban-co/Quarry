import SwiftUI
import CodeEditorView
import LanguageSupport

struct FunctionEditorView: View {
    @Environment(ConnectionInstance.self) private var instance
    @Environment(\.colorScheme) private var colorScheme

    @State private var functionBody = ""
    @State private var position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = []
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var showSaveError = false
    @State private var showSaveConfirmation = false
    @State private var pendingConfirmation: QueryConfirmationRequest?
    @State private var hasLoaded = false
    @State private var tab: DatabaseTab?

    private var originalDefinition: String {
        tab?.originalFunctionDefinition ?? ""
    }

    private var isModified: Bool {
        hasLoaded && functionBody != originalDefinition
    }

    private var functionName: String {
        tab?.name ?? "Function"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
        }
        .background(
            Group {
                if colorScheme == .dark {
                    Rectangle().fill(Color.black.opacity(0.30))
                } else {
                    Color.white
                }
            }
        )
        .background(
            Button(action: { requestSave() }) { EmptyView() }
                .keyboardShortcut("s", modifiers: [.command])
                .hidden()
                .disabled(!isModified || isSaving)
        )
        .onAppear {
            loadDefinitionFromTab()
        }
        .confirmationDialog(
            "Save Function",
            isPresented: $showSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task { await saveFunction() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will execute the function definition to update it in the database.")
        }
        .queryConfirmation($pendingConfirmation) { _ in
            Task { await saveFunction() }
        }
        .alert("Save Error", isPresented: $showSaveError, presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "f.cursive")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(functionName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer()

            Button(action: { requestSave() }) {
                HStack(spacing: 6) {
                    Text("Save")
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .colorMultiply(.black)
                    } else {
                        Text("\u{2318}S")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(Color(.textBackgroundColor))
                .background(Color.primaryButton)
                .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!isModified || isSaving)
            .opacity(isModified ? 1 : 0)
            .padding(.trailing, -8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            CodeEditor(text: $functionBody, position: $position, messages: $messages, language: .sqlite())
                .environment(\.codeEditorTheme, transparentTheme)
                .environment(\.codeEditorLayoutConfiguration, .init(wrapText: true))

            if functionBody.isEmpty {
                Text("Function definition")
                    .foregroundStyle(.secondary.opacity(0.6))
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 38)
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, 10)
    }

    private var transparentTheme: Theme {
        var theme = colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
        theme.backgroundColour = NSColor.clear
        return theme
    }

    private func loadDefinitionFromTab() {
        guard let currentTab = instance.selectedTab,
              currentTab.type == .functionEditor,
              let query = currentTab.initialQuery else { return }
        tab = currentTab
        functionBody = query
        currentTab.initialQuery = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            hasLoaded = true
        }
    }

    /// Routes the save through the query alert mode: warn/prompt for a password when
    /// the setting asks for it, otherwise fall back to the plain save confirmation.
    private func requestSave() {
        let trimmed = functionBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let request = QueryAlertPolicy.confirmationRequest(
            for: trimmed,
            connection: instance.connection
        ) {
            pendingConfirmation = request
        } else {
            showSaveConfirmation = true
        }
    }

    @MainActor
    private func saveFunction() async {
        let trimmed = functionBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await instance.databaseService.executeRawQuery(trimmed, databaseSchema: tab?.functionSchema)

            tab?.originalFunctionDefinition = functionBody

            try? await instance.loadCollectionsForCurrentDatabase(schema: tab?.functionSchema)
        } catch {
            saveError = error
            showSaveError = true
        }
    }
}
