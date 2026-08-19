//
//  CommandPalette.swift
//  Quarry
//
//  Created by Fauzaan on 6/27/25.
//

import AppKit
import SwiftUI

struct CommandPalette: View {
    @Environment(ConnectionInstance.self) private var instance
    @Binding var searchText: String
    var onBack: () -> Void
    var isBackButtonEnabled: Bool = true
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        HStack {
            TextField("Open quickly", text: $searchText)
                .focused($isSearchFocused)
                .font(.system(size: 17))
                .task {
                    await focusSearchField()
                }
                .textFieldStyle(PlainTextFieldStyle())
            
            // Clear button
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Button(action: {
                if !searchText.isEmpty {
                    searchText = ""
                } else {
                    if isBackButtonEnabled {
                        onBack()
                    }
                }
            }) {}
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(PlainButtonStyle())
                .opacity(0)
        }
        .padding(.leading, 20)
        .padding(.vertical)
        .padding(.trailing, 12)
        .frame(maxWidth: 500)
    }

    @MainActor
    private func focusSearchField() async {
        await Task.yield()
        isSearchFocused = true
    }
    
    // MARK: - Separate Collection List View
    struct CollectionsList: View {
        @Environment(ConnectionInstance.self) private var instance
        let tabID: UUID
        @Binding var searchText: String
        let onBack: () -> Void
        
        @State private var activeIndex: Int = 0
        @State private var scrollPosition = ScrollPosition(idType: Int.self)
        
        @State private var eventMonitor: Any?
        @State private var hostingWindow: NSWindow?
        @State private var hoveredIndex: Int? = nil
        
        private var filteredCollections: [any CollectionWrapper] {
            guard let collections = instance.collections[instance.connectedDatabase?.name ?? ""] else {
                return []
            }
            
            if searchText.isEmpty {
                return collections
            }
            
            return collections.filter { $0.name.localizedStandardContains(searchText) }
        }
        
        
        var body: some View {
            if !filteredCollections.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Navigation header
                    Text("Top matches")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Collection items
                            ForEach(Array(filteredCollections.enumerated()), id: \.offset) { index, collection in
                                Button(action: {
                                    selectActiveItem()
                                }) {
                                    HStack {
                                        // Collection icon
                                        Image(systemName: collection.type == "view" ? "eye.fill" : "tablecells")
                                            .font(collection.type == "view" ? .footnote : .body)
                                            .foregroundColor(.secondary)
                                            .frame(width: 20)
                                        
                                        // Collection name
                                        Text(collection.name)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        
                                        Spacer()
                                        
                                        HStack {
                                            Text(collection.type.capitalized)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(minWidth: 35)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(.separator, lineWidth: 1)
                                        )
                                    }
                                    .padding(.leading, 10)
                                    .padding(.trailing, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .id(index)
                                .onHover { isHovered in
                                    hoveredIndex = isHovered ? index : nil
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(backgroundColorForItem(at: index))
                                        .contentShape(Rectangle())
                                )
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition($scrollPosition)
                    .frame(maxHeight: min(CGFloat(filteredCollections.count * 37), 320))
                    .padding(.bottom, 4)
                }
                .padding([.horizontal, .top], 8)
                .padding(.bottom, 4)
                .background(WindowReader { window in
                    hostingWindow = window
                })
                .modifier(GlassBackgroundStyle(cornerRadius: 16))
                .glassFallbackBorder(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 500)
                .padding(.bottom, 8)
                .onAppear {
                    withAnimation {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                    setupEventMonitor()
                    resetActiveIndex()
                }
                .onDisappear {
                    removeEventMonitor()
                }
                .onChange(of: searchText) { _, _ in
                    resetActiveIndex()
                }
            }
        }
        
        private func resetActiveIndex() {
            activeIndex = 0
            scrollToActiveIndex()
        }
        
        private func setupEventMonitor() {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                guard isKeyboardEventForHostingWindow(event) else { return event }
                // Only handle navigation keys for the list
                guard !filteredCollections.isEmpty else { return event }
                
                switch event.keyCode {
                case 125: // Down arrow
                    moveDown()
                    return nil // Consume the event
                case 126: // Up arrow
                    moveUp()
                    return nil // Consume the event
                case 36: // Enter/Return
                    selectActiveItem()
                    return nil // Consume the event
                default:
                    return event // Let other keys pass through
                }
            }
        }

        private func isKeyboardEventForHostingWindow(_ event: NSEvent) -> Bool {
            guard let hostingWindow,
                  let eventWindow = event.window,
                  eventWindow === hostingWindow,
                  hostingWindow.isKeyWindow,
                  instance.selectedTab?.id == tabID else {
                return false
            }

            return true
        }
        
        private func removeEventMonitor() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        
        private func moveDown() {
            let newIndex = min(activeIndex + 1, filteredCollections.count - 1)
            if newIndex != activeIndex {
                activeIndex = newIndex
                scrollToActiveIndex()
            }
        }
        
        private func moveUp() {
            let newIndex = max(activeIndex - 1, 0)
            if newIndex != activeIndex {
                activeIndex = newIndex
                scrollToActiveIndex()
            }
        }
        
        private func scrollToActiveIndex() {
            scrollPosition.scrollTo(id: activeIndex, anchor: .center)
        }
        
        private func selectActiveItem() {
            guard activeIndex < filteredCollections.count,
                  let collection = filteredCollections[safe: activeIndex] else { return }

            let isFunction = collection.type == "function" || collection.type == "procedure"
            if isFunction, let pgWrapper = collection as? PostgreSQLCollectionWrapper {
                openFunction(name: pgWrapper.name, oid: pgWrapper.oid, schema: pgWrapper.schema)
            } else {
                instance.createNewTab(name: collection.name, databaseSchema: collection.schema)
            }
            onBack()
            searchText = ""
        }

        private func openFunction(name: String, oid: String, schema: String?) {
            Task {
                do {
                    let definition = try await instance.databaseService.getFunctionDefinition(oid: oid)
                    instance.createFunctionEditorTab(name: name, definition: definition, oid: oid, schema: schema)
                } catch {
                    debugLog("Failed to open function: \(error)")
                }
            }
        }
        
        private func backgroundColorForItem(at index: Int) -> Color {
            if index == activeIndex {
                return .secondary.opacity(0.1)
            } else if hoveredIndex == index {
                return .secondary.opacity(0.1)
            } else {
                return .clear
            }
        }
    }
}
