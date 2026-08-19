//
//  QueryConfirmationSheet.swift
//  Quarry
//

import SwiftUI

/// A query waiting for the user's approval before it is sent to the server.
struct QueryConfirmationRequest: Identifiable {
    let id = UUID()
    let query: String
    let mode: QueryAlertMode
    let connectionName: String
    let isReadOnly: Bool
    /// `nil` when no password is stored for the connection, which downgrades
    /// safe mode to a plain warning.
    let verifyPassword: ((String) -> Bool)?

    var needsPassword: Bool {
        mode.requiresPassword && verifyPassword != nil
    }
}

struct QueryConfirmationSheet: View {
    let request: QueryConfirmationRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var passwordError = false
    @FocusState private var passwordFocused: Bool

    private var title: String {
        request.needsPassword ? "Confirm with your password" : "Run this query?"
    }

    private var subtitle: String {
        if request.needsPassword {
            return "Enter the password for “\(request.connectionName)” to send this query to the server."
        }
        if request.isReadOnly {
            return "This query will be sent to “\(request.connectionName)”."
        }
        return "This query modifies data or schema on “\(request.connectionName)”."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            queryPreview

            if request.mode.requiresPassword && request.verifyPassword == nil {
                Label(
                    "No password is stored for this connection, so it can't be verified.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            if request.needsPassword {
                passwordField
            }

            footer
        }
        .padding(20)
        .frame(width: 420)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: request.needsPassword ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(request.isReadOnly ? Color.secondary : Color.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var queryPreview: some View {
        ScrollView {
            Text(request.query)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        )
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField("Password", text: $password)
                .textFieldStyle(CustomTextFieldStyle())
                .focused($passwordFocused)
                .onChange(of: password) { _, _ in passwordError = false }
                .onSubmit(confirm)

            if passwordError {
                Text("Incorrect password")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .onAppear { passwordFocused = true }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel", role: .cancel, action: onCancel)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

            Button(action: confirm) {
                Text("Run Query")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.primaryButton)
            .keyboardShortcut(.defaultAction)
            .disabled(request.needsPassword && password.isEmpty)
        }
    }

    private func confirm() {
        if let verifyPassword = request.verifyPassword, request.mode.requiresPassword {
            guard verifyPassword(password) else {
                passwordError = true
                password = ""
                passwordFocused = true
                return
            }
        }
        onConfirm()
    }
}

extension View {
    /// Presents the query confirmation sheet whenever `request` holds a pending query.
    func queryConfirmation(
        _ request: Binding<QueryConfirmationRequest?>,
        onConfirm: @escaping (QueryConfirmationRequest) -> Void
    ) -> some View {
        sheet(item: request) { pending in
            QueryConfirmationSheet(
                request: pending,
                onConfirm: {
                    request.wrappedValue = nil
                    onConfirm(pending)
                },
                onCancel: {
                    request.wrappedValue = nil
                }
            )
        }
    }
}
