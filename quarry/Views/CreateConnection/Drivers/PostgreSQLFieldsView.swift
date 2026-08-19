//
//  PostgreSQLFieldsView.swift
//  Quarry
//
//  Created by Fauzaan on 8/16/25.
//

import AppKit
import SwiftUI

struct PostgreSQLFieldsView: View {
    @Binding var hostname: String
    @Binding var port: String
    @Binding var username: String
    @Binding var password: String
    @Binding var defaultDatabase: String
    @Binding var sslMode: String
    @Binding var sslKeyPath: String
    @Binding var sslCertPath: String
    @Binding var sslRootCertPath: String
    let onImportURI: (String) -> Void

    @State private var showURIImportPopover = false

    private var hasSSLFiles: Bool {
        !sslKeyPath.isEmpty || !sslCertPath.isEmpty || !sslRootCertPath.isEmpty
    }

    var body: some View {
        Group {
            Section {
                LabeledContent("Host") {
                    HStack(spacing: 4) {
                        TextField("", text: $hostname, prompt: Text("localhost"))
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                            .frame(width: 180)

                        Text(":")
                            .foregroundStyle(.tertiary)

                        TextField("", text: $port, prompt: Text("5432"))
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                            .frame(width: 50)
                    }
                }
                TextField("Database", text: $defaultDatabase, prompt: Text("postgres"))
            } header: {
                HStack {
                    Text("Connection")
                    Spacer()
                    Button("Import from URI") {
                        showURIImportPopover.toggle()
                    }
                    .popover(isPresented: $showURIImportPopover, arrowEdge: .top) {
                        URIImportPopover(
                            placeholder: "postgresql://username:password@host:port/database"
                        ) { uri in
                            onImportURI(uri)
                            showURIImportPopover = false
                        }
                    }
                }
                .padding(.trailing, -8)
            }

            Section {
                TextField("Username", text: $username, prompt: Text("postgres"))
                SecureField("Password", text: $password, prompt: Text("password"))
            }

            Section {
                Picker("SSL Mode", selection: $sslMode) {
                    Text("disable").tag("disable")
                    Text("prefer").tag("prefer")
                    Text("require").tag("require")
                    Text("verify-ca").tag("verify-ca")
                    Text("verify-full").tag("verify-full")
                }

                LabeledContent("SSL Files") {
                    HStack(spacing: 8) {
                        SSLFileButton(
                            title: "Key",
                            path: $sslKeyPath,
                            panelTitle: "Choose SSL Private Key"
                        )

                        SSLFileButton(
                            title: "Cert",
                            path: $sslCertPath,
                            panelTitle: "Choose SSL Certificate"
                        )

                        SSLFileButton(
                            title: "CA Cert",
                            path: $sslRootCertPath,
                            panelTitle: "Choose SSL CA Certificate"
                        )

                        Button {
                            clearSSLFiles()
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 12, height: 12)
                        }
                        .disabled(!hasSSLFiles)
                    }
                }
            }
        }
    }

    private func clearSSLFiles() {
        sslKeyPath = ""
        sslCertPath = ""
        sslRootCertPath = ""
    }
}

private struct SSLFileButton: View {
    let title: String
    @Binding var path: String
    let panelTitle: String

    private var label: String {
        guard !path.isEmpty else {
            return "\(title)..."
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        Button {
            chooseFile()
        } label: {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
        }
        .help(path.isEmpty ? title : path)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = panelTitle

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

struct URIImportPopover: View {
    let placeholder: String
    let onImport: (String) -> Void

    @State private var uriInput: String = ""
    @FocusState private var uriFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var trimmedInput: String {
        uriInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedInput.isEmpty
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField(placeholder, text: $uriInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(uriFieldFocused ? 0.2 : 0.0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.separator, lineWidth: 1)
                )
                .focused($uriFieldFocused)
                .onSubmit(submit)

            HStack {
                Spacer()

                Button(action: submit) {
                    HStack(spacing: 5) {
                        Text("Import")
                            .font(.system(size: 11, weight: .regular))

                        Text("⏎")
                            .font(.system(size: 10, weight: .regular))
                            .opacity(0.7)
                    }
                    .foregroundStyle(canSubmit ? Color(.textBackgroundColor) : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(canSubmit ? Color.primaryButton : Color.gray.opacity(0.25))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(8)
        .frame(width: 360)
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            uriFieldFocused = true
        }
    }

    private func submit() {
        guard canSubmit else { return }
        onImport(trimmedInput)
    }
}
