//
//  Pagination.swift
//  Collection
//
//  Created by Fauzaan on 3/6/25.
//

import SwiftUI
import MongoKitten

struct Pagination: View {
    @Binding var currentPage: Int
    var totalPages: Int
    var totalCount: Int
    var totalRowCount: Int?
    var totalPerPage: Int
    let onRefresh: () -> Void
    let modificationTracker: TableModificationTracker
    let onCommitModifications: () -> Void
    
    @Environment(ConnectionInstance.self) private var instance
    @State private var filter: String?
    @State private var isPreviousHovering = false
    @State private var isNextHovering = false
    @State private var previousClickCooldown = false
    @State private var nextClickCooldown = false
    @State private var isShowingPageNumber = false
    @State private var pageIndicatorTask: Task<Void, Never>?
    
    // Unsaved changes confirmation
    @State private var showUnsavedChangesDialog = false
    @State private var pendingPageAction: (() -> Void)?
    
    // Computed property to determine if either button is being hovered
    private var isAnyButtonHovering: Bool {
        isPreviousHovering || isNextHovering
    }
    
    var body: some View {
        let isPreviousDisabled = currentPage <= 1
        // With a known total we can page precisely; otherwise fall back to the
        // "last page is a short page" heuristic.
        let isNextDisabled = totalRowCount != nil
            ? currentPage >= totalPages
            : totalCount != totalPerPage
        
        HStack(spacing: 0) {
            Button(action: {
                checkForUnsavedChanges {
                    withAnimation(.spring(response: 0.3)) {
                        previousPage(filter: filter)
                    }
                }
            }) {
                Image(systemName: "chevron.left")
                    .opacity(isPreviousDisabled ? 0.3 : 1)
                    .font(.system(size: 14))
                    .contentShape(Rectangle())
            }
            .disabled(isPreviousDisabled)
            .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9)))
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .customHelp("Go to previous page", position: .top, shortcut: KeyboardShortcut(
                modifiers: [.command],
                key: "←"
            ), spacing: 10)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPreviousHovering = hovering
                }
            }
            .transition(.scale.combined(with: .opacity))
            
            Button(action: {
                // Open Modal
            }) {
                Group {
                    if isShowingPageNumber || isAnyButtonHovering {
                        if totalRowCount != nil {
                            Text("Page \(currentPage) of \(totalPages)")
                        } else {
                            Text("Page \(currentPage)")
                        }
                    } else if let totalRowCount, totalRowCount > totalCount {
                        Text("\(totalCount) of \(totalRowCount.formatted())")
                    } else {
                        Text("^[\(totalCount) row](inflect: true)")
                    }
                }
                    .foregroundStyle(.gray)
                    .frame(minWidth: 60)
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8), disableScaleEffect: true))
            
            Button(action: {
                checkForUnsavedChanges {
                    withAnimation(.spring(response: 0.3)) {
                        nextPage(filter: filter)
                    }
                }
            }) {
                Image(systemName: "chevron.right")
                    .opacity(isNextDisabled ? 0.3 : 1)
                    .font(.system(size: 14))
                    .contentShape(Rectangle())
            }
            .disabled(isNextDisabled)
            .buttonStyle(ActionButtonStyle(padding: EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9)))
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .customHelp( "Go to next page", position: .top, shortcut: KeyboardShortcut(
                modifiers: [.command],
                key: "→"
            ), spacing: 10)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isNextHovering = hovering
                }
            }
            .transition(.scale.combined(with: .opacity))
        }
        .confirmationDialog(
            "Do you want to save it?",
            isPresented: $showUnsavedChangesDialog,
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task { @MainActor in
                    onCommitModifications()
                    try? await Task.sleep(for: .milliseconds(100))
                    pendingPageAction?()
                    pendingPageAction = nil
                }
            }
            
            Button("Don't Save") {
                // Clear the modifications and proceed with navigation
                modificationTracker.resetAllModifications()
                pendingPageAction?()
                pendingPageAction = nil
            }
            
            Button("Cancel", role: .cancel) {
                pendingPageAction = nil
            }
        } message: {
            Text("This page contains unsaved changes. Your changes will be lost if you don't save them.")
        }
        .onChange(of: currentPage) { oldValue, newValue in
            guard oldValue != newValue else { return }
            showPageNumberBriefly()
        }
        .onDisappear {
            pageIndicatorTask?.cancel()
        }
    }
    
    
    
    // MARK: - Unsaved Changes Check
    private func checkForUnsavedChanges(action: @escaping () -> Void) {
        TextCellView.exitCurrentEditMode()
        
            if modificationTracker.hasModifications {
                // Store the action to execute later
                pendingPageAction = action
                showUnsavedChangesDialog = true
            } else {
                // No unsaved changes, execute action immediately
                action()
            }
    }
    
    // MARK: - Pagination Methods
    @MainActor
    func nextPage(filter: String?) {
        currentPage += 1
        onRefresh()
    }
    
    @MainActor
    func previousPage(filter: String?) {
        guard currentPage > 1 else { return }
        self.currentPage -= 1
        onRefresh()
    }

    @MainActor
    private func showPageNumberBriefly() {
        pageIndicatorTask?.cancel()

        withAnimation(.easeInOut(duration: 0.18)) {
            isShowingPageNumber = true
        }

        pageIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))

            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.18)) {
                isShowingPageNumber = false
            }
        }
    }
}
