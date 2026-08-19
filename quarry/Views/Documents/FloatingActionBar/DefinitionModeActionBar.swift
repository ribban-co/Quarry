//
//  DefinitionModeActionBar.swift
//  Quarry
//
//  Created by Fauzaan on 10/20/25.
//

import SwiftUI

struct DefinitionModeActionBar: View {
    @Binding var tabViewMode: DatabaseTab.ViewMode
    let isLoading: Bool
    let debouncedIsLoading: Bool
    let onRefresh: (_ currentPage: Int, _ itemsPerPage: Int, _ fetchSchema: Bool) -> Void
    let onDebounceLoadingChange: (Bool) -> Void
    var onCancelLoad: (() -> Void)? = nil

    @State private var debounceTask: Task<Void, Never>?
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 5) {
            Button(action: {
                if isLoading {
                    onCancelLoad?()
                } else {
                    // Cancel any existing loading operations before starting new one
                    loadingTask?.cancel()
                    debounceTask?.cancel()

                    onRefresh(1, 300, true)
                }
            }) {
                // The xmark is a real cancel: clicking while loading aborts the query.
                let iconName = debouncedIsLoading ? "xmark" : "arrow.clockwise"

                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .onChange(of: isLoading) { oldValue, newValue in
                        // Cancel previous debounce task
                        debounceTask?.cancel()

                        if newValue {
                            // Debounce the stopped -> loading transition so
                            // fast loads don't flash the cancel icon
                            debounceTask = Task { @MainActor in
                                do {
                                    try await Task.sleep(for: .milliseconds(400))
                                    // Double-check we haven't been cancelled and loading is still running
                                    if !Task.isCancelled && isLoading {
                                        onDebounceLoadingChange(true)
                                    }
                                } catch {
                                    // Task was cancelled, ignore
                                }
                            }
                        } else {
                            // Restore the refresh icon immediately
                            onDebounceLoadingChange(false)
                        }
                    }
            }
            .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8), isActive: debouncedIsLoading))
            .customHelp(debouncedIsLoading ? "Cancel" : "Refresh", position: .top, shortcut: KeyboardShortcut(
                modifiers: [.command],
                key: "R"
            ), spacing: 10)

            ViewModeToggle(tabViewMode: $tabViewMode)
                .padding(.leading, 2)
                .padding(.vertical, -2)
        }
        .padding(8)
    }
}
