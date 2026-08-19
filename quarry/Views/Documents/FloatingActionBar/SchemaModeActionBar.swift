//
//  SchemaModeActionBar.swift
//  Quarry
//
//  Created by Fauzaan on 10/20/25.
//

import SwiftUI

struct SchemaModeActionBar: View {
    @Binding var tabViewMode: DatabaseTab.ViewMode
    let columnCount: Int
    let isLoading: Bool
    let debouncedIsLoading: Bool
    let onRefresh: (_ currentPage: Int, _ itemsPerPage: Int, _ fetchSchema: Bool) -> Void
    let onDebounceLoadingChange: (Bool) -> Void

    // Schema modification tracking
    let schemaModificationTracker: SchemaModificationTracker?
    let onCommitSchemaModifications: (() -> Void)?
    var onNewField: (() -> Void)?
    var onCancelLoad: (() -> Void)? = nil

    @State private var debounceTask: Task<Void, Never>?
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 5) {
            columnsCountLabel()
            
            Divider()
                .frame(height: 22)
                .padding(.vertical, 6)
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
            
            Button(action: {
                onNewField?()
            }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .contentShape(Rectangle())
            }
            .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8), isActive: false))
            .customHelp("Add Column", position: .top, shortcut: KeyboardShortcut(
                modifiers: [.command, .shift],
                key: "N"
            ), spacing: 10)

            // Schema modification buttons - only show when there are modifications
            if let tracker = schemaModificationTracker, tracker.hasModifications {
                HStack(spacing: 6) {
                    Divider()
                        .frame(height: 22)
                        .padding(.vertical, 6)
                        .padding(.trailing, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    // Show pending deletions with red button
                    let totalDeletionCount = tracker.pendingDeletionCount + tracker.pendingIndexDeletionCount
                    if totalDeletionCount > 0 {
                        Button(action: {
                            onCommitSchemaModifications?()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                Text("\(totalDeletionCount)")
                                    .font(.system(size: 12, weight: .light))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.red)
                        .clipShape(.rect(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .transition(.scale.combined(with: .opacity))
                        .customHelp("Delete Columns/Indexes", position: .top, shortcut: KeyboardShortcut(
                            modifiers: [.command],
                            key: "S"
                        ), spacing: 10)
                    }

                    // Show non-deletion modifications (additions + updates) with the brand button
                    let nonDeletionCount = tracker.columnAdditions.count + tracker.columnUpdates.count + tracker.indexAdditions.count + tracker.indexUpdates.count
                    if nonDeletionCount > 0 {
                        Button(action: {
                            onCommitSchemaModifications?()
                        }) {
                            HStack(spacing: 4) {
                                Text("Save")
                                    .font(.system(size: 12, weight: .light))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(.onBrand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.brand)
                        .clipShape(.rect(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .transition(.scale.combined(with: .opacity))
                        .customHelp("Save Changes", position: .top, shortcut: KeyboardShortcut(
                            modifiers: [.command],
                            key: "S"
                        ), spacing: 10)
                    }

                    Button(action: {
                        tracker.clearAll()
                        // Post notification to reload table view and reset UI
                        NotificationCenter.default.post(
                            name: .tableReloadData,
                            object: nil,
                            userInfo: nil
                        )
                        // Refresh schema to reload original values
                        onRefresh(1, 300, true)
                    }) {
                        Text("Discard")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8)))
                    .customHelp("Discard schema changes", position: .top)
                }
            }

            ViewModeToggle(tabViewMode: $tabViewMode)
                .padding(.leading, 2)
                .padding(.vertical, -2)
        }
        .padding(8)
    }
    
    @ViewBuilder
    private func columnsCountLabel() -> some View {
        HStack(spacing: 0) {
            Button(action: {
                // Open Modal
            }) {
                Text("\(columnCount) Columns")
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8), disableScaleEffect: true))
        }
    }
}
