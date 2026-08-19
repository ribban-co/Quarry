//
//  KeymapSettingsView.swift
//  Quarry
//

import SwiftUI

struct KeymapSettingsView: View {
    var body: some View {
        Form {
            ForEach(KeymapSettingsContent.sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        KeyboardShortcutRow(action: item.action, shortcut: item.shortcut)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyboardShortcutRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(.rect(cornerRadius: 4))
        }
    }
}

#Preview {
    KeymapSettingsView()
        .frame(width: 500, height: 500)
}
