//
//  MySQLFieldsView.swift
//  Quarry
//
//  Created by Fauzaan on 8/18/25.
//

import SwiftUI

struct MySQLFieldsView: View {
    @Binding var hostname: String
    @Binding var port: String
    @Binding var username: String
    @Binding var password: String
    @Binding var defaultDatabase: String
    @Binding var sslMode: String
    let onImportURI: (String) -> Void

    @State private var showURIImportPopover = false

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

                        TextField("", text: $port, prompt: Text("3306"))
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                            .frame(width: 50)
                    }
                }
                TextField("Database", text: $defaultDatabase, prompt: Text("mysql"))
            } header: {
                HStack {
                    Text("Connection")
                    Spacer()
                    Button("Import from URI") {
                        showURIImportPopover.toggle()
                    }
                    .popover(isPresented: $showURIImportPopover, arrowEdge: .top) {
                        URIImportPopover(
                            placeholder: "mysql://username:password@host:port/database"
                        ) { uri in
                            onImportURI(uri)
                            showURIImportPopover = false
                        }
                    }
                }
                .padding(.trailing, -8)
            }

            Section {
                TextField("Username", text: $username, prompt: Text("root"))
                SecureField("Password", text: $password, prompt: Text("password"))
            }

            Section {
                Picker("SSL Mode", selection: $sslMode) {
                    Text("disable").tag("disable")
                    Text("prefer").tag("prefer")
                    Text("require").tag("require")
                }
            }
        }
    }
}
