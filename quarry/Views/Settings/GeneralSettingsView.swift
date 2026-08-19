//
//  GeneralSettingsView.swift
//  Quarry
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("containerSyncEnabled") private var containerSyncEnabled = true
    @AppStorage(QueryAlertMode.storageKey) private var queryAlertMode = QueryAlertMode.default.rawValue

    // MARK: - Future Settings Storage (DO NOT REMOVE - enable when needed)
    // These @AppStorage properties are for future settings sections.
    // Uncomment the corresponding section in body to enable.

    // @AppStorage("receiveBetaUpdates") private var receiveBetaUpdates = false
    // @AppStorage("reopenLastWorkspace") private var reopenLastWorkspace = true

    // @AppStorage("autoHideTableScrollers") private var autoHideTableScrollers = false
    @AppStorage("alternatingRowColors") private var alternatingRowColors = true
    // @AppStorage("estimateCountThreshold") private var estimateCountThreshold = 500000
    // @AppStorage("showOpenInFinderAfterExport") private var showOpenInFinderAfterExport = true

    // @AppStorage("autoSaveQueries") private var autoSaveQueries = true
    // @AppStorage("autoUppercaseKeywords") private var autoUppercaseKeywords = false
    // @AppStorage("autoInsertClosingBraces") private var autoInsertClosingBraces = true
    // @AppStorage("autoCompleteKey") private var autoCompleteKey = AutoCompleteKey.enter.rawValue
    // @AppStorage("indentStyle") private var indentStyle = IndentStyle.spaces.rawValue
    // @AppStorage("indentSize") private var indentSize = 4

    // @AppStorage("queryTimeout") private var queryTimeout = 300
    // @AppStorage("keepConnectionAlive") private var keepConnectionAlive = true

    // @AppStorage("csvDelimiter") private var csvDelimiter = CSVDelimiter.comma.rawValue
    // @AppStorage("csvQuoteStyle") private var csvQuoteStyle = CSVQuoteStyle.quoteIfNeeded.rawValue
    // @AppStorage("csvLineBreak") private var csvLineBreak = CSVLineBreak.lf.rawValue
    // @AppStorage("csvDecimalSeparator") private var csvDecimalSeparator = "."

    // @AppStorage("historyRetention") private var historyRetention = HistoryRetention.days90.rawValue
    // @AppStorage("maxHistoryEntries") private var maxHistoryEntries = 10000

    var body: some View {
        Form {
            appearanceSection
            applicationSection
            containersSection
            queryExecutionSection
            tableSection

            // MARK: - Future Settings Sections (DO NOT REMOVE - uncomment to enable)
            // tableDataSection
            // sqlEditorSection
            // queryExecutionSection
            // exportDefaultsSection
            // queryHistorySection
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, newValue in
            applyAppearance(newValue)
        }
        .onAppear {
            applyAppearance(appearance)
        }
    }

    // MARK: - Active Sections

    private var queryExecutionSection: some View {
        Section("Query Execution") {
            Picker("Before running a query", selection: $queryAlertMode) {
                ForEach(QueryAlertMode.allCases, id: \.rawValue) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode.rawValue)
                }
            }

            Text(QueryAlertMode(rawValue: queryAlertMode)?.summary ?? QueryAlertMode.default.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tableSection: some View {
        Section("Table") {
            Toggle("Alternating row colors", isOn: $alternatingRowColors)
        }
    }

    private var appearanceSection: some View {
        Section {
            HStack(alignment: .top) {
                Text("Appearance")
                    .frame(width: 100, alignment: .leading)

                Spacer()
                    .frame(width: 40)

                HStack(spacing: 16) {
                    AppearanceOptionView(
                        title: "System",
                        mode: .system,
                        isSelected: appearance == 0
                    )
                    .onTapGesture { appearance = 0 }

                    AppearanceOptionView(
                        title: "Light",
                        mode: .light,
                        isSelected: appearance == 1
                    )
                    .onTapGesture { appearance = 1 }

                    AppearanceOptionView(
                        title: "Dark",
                        mode: .dark,
                        isSelected: appearance == 2
                    )
                    .onTapGesture { appearance = 2 }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var applicationSection: some View {
        Section("Application") {
            Toggle("Show in menu bar", isOn: $showInMenuBar)

            // MARK: Future Application toggles (DO NOT REMOVE - uncomment to enable)
            // Toggle("Receive Beta Updates", isOn: $receiveBetaUpdates)
            // Toggle("Reopen last workspace at startup", isOn: $reopenLastWorkspace)
        }
    }

    private var containersSection: some View {
        Section("Containers") {
            Toggle("Sync local containers", isOn: $containerSyncEnabled)
        }
    }

    private func applyAppearance(_ value: Int) {
        NSApp.appearance = AppDelegate.appearance(for: value)
    }

    // MARK: - Future Settings Sections (DO NOT REMOVE - preserved for future use)
    // To enable a section:
    // 1. Uncomment the corresponding @AppStorage properties above
    // 2. Uncomment the section call in body
    // 3. Uncomment the section implementation below

    /*
    private var tableDataSection: some View {
        Section("Table Data") {
            Toggle("Auto hide table scrollers", isOn: $autoHideTableScrollers)
            Toggle("Alternating row background colors", isOn: $alternatingRowColors)

            HStack {
                Text("Estimate count when table has more than")
                TextField("", value: $estimateCountThreshold, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text("rows")
            }

            Toggle("Show \"Open in Finder\" after exporting data", isOn: $showOpenInFinderAfterExport)
        }
    }

    private var sqlEditorSection: some View {
        Section("SQL Editor") {
            Toggle("Automatically save queries while editing", isOn: $autoSaveQueries)
            Toggle("Automatically UPPERCASE keywords", isOn: $autoUppercaseKeywords)
            Toggle("Automatically insert closing braces and quotes", isOn: $autoInsertClosingBraces)

            Picker("Auto-complete key", selection: $autoCompleteKey) {
                ForEach(AutoCompleteKey.allCases, id: \.rawValue) { key in
                    Label(key.rawValue, systemImage: key.icon).tag(key.rawValue)
                }
            }

            HStack {
                Picker("Indent with", selection: $indentStyle) {
                    ForEach(IndentStyle.allCases, id: \.rawValue) { style in
                        Text(style.rawValue).tag(style.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()

                Picker("", selection: $indentSize) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
                .labelsHidden()
                .frame(width: 100)
            }
        }
    }

    private var queryExecutionSection: some View {
        Section("Query Execution") {
            HStack {
                Text("Query timeout")
                TextField("", value: $queryTimeout, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("seconds")
            }

            Toggle("Keep connection alive (ping every 30s)", isOn: $keepConnectionAlive)
        }
    }

    private var exportDefaultsSection: some View {
        Section("Export Defaults (CSV)") {
            Picker("Delimiter", selection: $csvDelimiter) {
                ForEach(CSVDelimiter.allCases, id: \.rawValue) { delimiter in
                    Label(delimiter.rawValue, systemImage: delimiter.icon).tag(delimiter.rawValue)
                }
            }

            Picker("Quote style", selection: $csvQuoteStyle) {
                ForEach(CSVQuoteStyle.allCases, id: \.rawValue) { style in
                    Label(style.rawValue, systemImage: style.icon).tag(style.rawValue)
                }
            }

            Picker("Line break", selection: $csvLineBreak) {
                ForEach(CSVLineBreak.allCases, id: \.rawValue) { lineBreak in
                    Label(lineBreak.rawValue, systemImage: lineBreak.icon).tag(lineBreak.rawValue)
                }
            }

            Picker("Decimal separator", selection: $csvDecimalSeparator) {
                Text(".").tag(".")
                Text(",").tag(",")
            }
        }
    }

    private var queryHistorySection: some View {
        Section("Query History") {
            Picker("Retention period", selection: $historyRetention) {
                ForEach(HistoryRetention.allCases, id: \.rawValue) { period in
                    Label(period.rawValue, systemImage: period.icon).tag(period.rawValue)
                }
            }

            HStack {
                Text("Max entries per connection")
                TextField("", value: $maxHistoryEntries, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            Button("Clear All History") {
                // TODO: Implement clear history logic
            }
            .foregroundStyle(.red)
        }
    }
    */
}

#Preview {
    GeneralSettingsView()
        .frame(width: 500, height: 400)
}
