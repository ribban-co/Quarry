//
//  AboutSettingsView.swift
//  Quarry
//

import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    if let appIcon = NSApplication.shared.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 14))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quarry")
                            .font(.title)
                            .fontWeight(.medium)

                        Text("Version \(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Website") {
                    Button("ribban.co") {
                        NSWorkspace.shared.open(URL(string: "https://ribban.co")!)
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.brand)
                }

                LabeledContent("GitHub") {
                    Button("ribban-co/Quarry") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/ribban-co/Quarry")!)
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.brand)
                }

                LabeledContent("Support") {
                    Button("andreas.enemyr@gmail.com") {
                        NSWorkspace.shared.open(URL(string: "mailto:andreas.enemyr@gmail.com")!)
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.brand)
                }
            }

            Section {
                Text("Copyright © 2026 RIBBAN AB. Based on Pluk, © Pluk, Inc.\nLicensed under GNU AGPL v3.0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(.brand)
    }
}

#Preview {
    AboutSettingsView()
        .frame(width: 500, height: 400)
}
