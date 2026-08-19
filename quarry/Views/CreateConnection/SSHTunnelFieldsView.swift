import AppKit
import SwiftUI

struct SSHTunnelFieldsView: View {
    @Binding var isEnabled: Bool
    @Binding var host: String
    @Binding var port: String
    @Binding var username: String
    @Binding var authMethod: SSHAuthMethod
    @Binding var password: String
    @Binding var privateKeyPath: String
    @Binding var keyPassphrase: String

    var body: some View {
        Section {
            Toggle("Use SSH Tunnel", isOn: $isEnabled)

            if isEnabled {
                LabeledContent("SSH Host") {
                    HStack(spacing: 4) {
                        TextField("", text: $host, prompt: Text("bastion.example.com"))
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                            .frame(width: 180)

                        Text(":")
                            .foregroundStyle(.tertiary)

                        TextField("", text: $port, prompt: Text("22"))
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                            .frame(width: 50)
                    }
                }

                TextField("SSH Username", text: $username, prompt: Text("Username"))

                Picker("Authentication", selection: $authMethod) {
                    ForEach(SSHAuthMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }

                switch authMethod {
                case .sshAgent:
                    EmptyView()
                case .privateKey:
                    LabeledContent("Private Key") {
                        HStack(spacing: 8) {
                            TextField("", text: $privateKeyPath, prompt: Text("~/.ssh/id_ed25519"))
                                .multilineTextAlignment(.trailing)
                                .labelsHidden()

                            Button("Choose...") {
                                choosePrivateKey()
                            }
                        }
                    }

                    SecureField("Key Passphrase", text: $keyPassphrase, prompt: Text("optional"))
                case .password:
                    SecureField("SSH Password", text: $password, prompt: Text("password"))
                }
            }
        } header: {
            Text("SSH")
        }
    }

    private func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose SSH Private Key"

        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = url.path
        }
    }
}
