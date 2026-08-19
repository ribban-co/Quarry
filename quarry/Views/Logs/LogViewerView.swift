//
//  LogViewerView.swift
//  Quarry
//

import SwiftUI

struct LogViewerView: View {
    @State private var searchText = ""
    @State private var isPinnedToBottom = true

    private var store: LogStore { LogStore.shared }

    private var filteredEntries: [LogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter { $0.message.localizedCaseInsensitiveContains(query) }
    }

    private static let bottomAnchorID = "logViewerBottomAnchor"

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider()

            logList

            Divider()

            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Filter logs", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - List

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if filteredEntries.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }

                    // Sentinel used to detect whether the user is scrolled to
                    // the bottom; auto-scroll only engages while it's visible.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                        .onAppear { isPinnedToBottom = true }
                        .onDisappear { isPinnedToBottom = false }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
            .onChange(of: store.entries.count) {
                if isPinnedToBottom {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: searchText) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        Text(searchText.isEmpty ? "No log entries yet." : "No entries match \u{201C}\(searchText)\u{201D}")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(filteredEntries.count) of \(store.entries.count) entries")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Copy All") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(store.exportText(filteredEntries), forType: .string)
            }
            .controlSize(.small)
            .disabled(filteredEntries.isEmpty)

            Button("Clear") {
                store.clear()
            }
            .controlSize(.small)
            .disabled(store.entries.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Row

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LogStore.displayTimestampFormatter.string(from: entry.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
