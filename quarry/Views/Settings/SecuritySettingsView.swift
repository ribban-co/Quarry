//
//  SecuritySettingsView.swift
//  Quarry
//

import SwiftUI

struct SecuritySettingsView: View {
    @AppStorage("savePasswordsInKeychain") private var savePasswordsInKeychain = true
    @AppStorage("askBeforeSavingPasswords") private var askBeforeSavingPasswords = true
    @AppStorage("passwordTimeout") private var passwordTimeout = PasswordTimeout.never.rawValue

    @AppStorage("verifySSLCertificates") private var verifySSLCertificates = true
    @AppStorage("showSSLStatusInIndicator") private var showSSLStatusInIndicator = true

    @AppStorage("maskSensitiveColumns") private var maskSensitiveColumns = false

    @AppStorage("lockOnSleep") private var lockOnSleep = false
    @AppStorage("autoDisconnectTimeout") private var autoDisconnectTimeout = AutoDisconnectTimeout.never.rawValue

    var body: some View {
        Form {
            credentialsSection
            sslSection
            privacySection
            sessionSection
        }
        .formStyle(.grouped)
    }

    private var credentialsSection: some View {
        Section("Credentials") {
            Toggle("Save passwords in Keychain", isOn: $savePasswordsInKeychain)
            Toggle("Ask before saving passwords", isOn: $askBeforeSavingPasswords)

            Picker("Password timeout", selection: $passwordTimeout) {
                ForEach(PasswordTimeout.allCases, id: \.rawValue) { timeout in
                    Label(timeout.rawValue, systemImage: timeout.icon).tag(timeout.rawValue)
                }
            }
        }
    }

    private var sslSection: some View {
        Section("SSL/TLS") {
            Toggle("Verify SSL certificates by default", isOn: $verifySSLCertificates)
            Toggle("Show SSL status in connection indicator", isOn: $showSSLStatusInIndicator)
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Toggle("Mask sensitive columns by default", isOn: $maskSensitiveColumns)
            Text("Columns containing: password, secret, token, key")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            Toggle("Lock Quarry when system sleeps", isOn: $lockOnSleep)

            Picker("Auto-disconnect after", selection: $autoDisconnectTimeout) {
                ForEach(AutoDisconnectTimeout.allCases, id: \.rawValue) { timeout in
                    Label(timeout.rawValue, systemImage: timeout.icon).tag(timeout.rawValue)
                }
            }
        }
    }
}

#Preview {
    SecuritySettingsView()
        .frame(width: 500, height: 450)
}
