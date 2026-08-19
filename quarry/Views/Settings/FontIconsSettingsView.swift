//
//  FontIconsSettingsView.swift
//  Quarry
//

import SwiftUI

struct FontIconsSettingsView: View {
    @AppStorage("editorFontFamily") private var editorFontFamily = "SF Mono"
    @AppStorage("editorFontSize") private var editorFontSize = 13
    @AppStorage("editorLineHeight") private var editorLineHeight = 1.4
    @AppStorage("enableLigatures") private var enableLigatures = false

    @AppStorage("resultsFontFamily") private var resultsFontFamily = "System Default"
    @AppStorage("resultsFontSize") private var resultsFontSize = 12

    @AppStorage("sidebarFontSize") private var sidebarFontSize = 13

    @AppStorage("iconStyleFilled") private var iconStyleFilled = false
    @AppStorage("sidebarIconSize") private var sidebarIconSize = SidebarIconSize.small.rawValue

    @AppStorage("syntaxTheme") private var syntaxTheme = SyntaxTheme.default.rawValue

    private let fontFamilies = [
        "SF Mono",
        "Menlo",
        "Monaco",
        "Courier New",
        "JetBrains Mono",
        "Fira Code",
        "Source Code Pro"
    ]

    private let lineHeights = [1.2, 1.4, 1.6, 1.8, 2.0]

    var body: some View {
        Form {
            editorFontSection
            resultsFontSection
            sidebarFontSection
            iconsSection
            syntaxThemeSection
        }
        .formStyle(.grouped)
    }

    private var editorFontSection: some View {
        Section("Editor Font") {
            Picker("Font family", selection: $editorFontFamily) {
                ForEach(fontFamilies, id: \.self) { font in
                    Text(font).tag(font)
                }
            }

            HStack {
                Text("Font size")
                TextField("", value: $editorFontSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("px")
            }

            Picker("Line height", selection: $editorLineHeight) {
                ForEach(lineHeights, id: \.self) { height in
                    Text(height.formatted(.number.precision(.fractionLength(1)))).tag(height)
                }
            }

            Toggle("Enable ligatures", isOn: $enableLigatures)
        }
    }

    private var resultsFontSection: some View {
        Section("Results Table Font") {
            Picker("Font family", selection: $resultsFontFamily) {
                Text("System Default").tag("System Default")
                ForEach(fontFamilies, id: \.self) { font in
                    Text(font).tag(font)
                }
            }

            HStack {
                Text("Font size")
                TextField("", value: $resultsFontSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("px")
            }
        }
    }

    private var sidebarFontSection: some View {
        Section("Sidebar Font") {
            HStack {
                Text("Font size")
                TextField("", value: $sidebarFontSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("px")
            }
        }
    }

    private var iconsSection: some View {
        Section("Icons") {
            Picker("Icon style", selection: $iconStyleFilled) {
                Text("Outlined").tag(false)
                Text("Filled").tag(true)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()

            Picker("Sidebar icon size", selection: $sidebarIconSize) {
                ForEach(SidebarIconSize.allCases, id: \.rawValue) { size in
                    Label(size.rawValue, systemImage: size.icon).tag(size.rawValue)
                }
            }
        }
    }

    private var syntaxThemeSection: some View {
        Section("Syntax Highlighting Theme") {
            Picker("Theme", selection: $syntaxTheme) {
                ForEach(SyntaxTheme.allCases, id: \.rawValue) { theme in
                    Label(theme.rawValue, systemImage: theme.icon).tag(theme.rawValue)
                }
            }
        }
    }
}

#Preview {
    FontIconsSettingsView()
        .frame(width: 500, height: 500)
}
