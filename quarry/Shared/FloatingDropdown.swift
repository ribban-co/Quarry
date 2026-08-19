//
//  FloatingDropdown.swift
//  Quarry
//
//  Created by Assistant on 7/7/25.
//

import SwiftUI
import AppKit

/// A generic floating dropdown that works with any CaseIterable enum
struct EnumFloatingDropdown<T: CaseIterable & Hashable>: View where T.AllCases: RandomAccessCollection, T: RawRepresentable, T.RawValue == String {
    @Binding var selection: T
    @State private var isShowingDropdown = false
    @State private var activeIndex: Int = 0
    @State private var hoveredIndex: Int? = nil
    
    let width: CGFloat
    let itemDisplay: ((T) -> String)?
    let itemSymbol: ((T) -> String)?
    
    private var items: [T] {
        Array(T.allCases)
    }
    
    init(selection: Binding<T>,
         width: CGFloat = 120,
         itemDisplay: ((T) -> String)? = nil,
         itemSymbol: ((T) -> String)? = nil) {
        self._selection = selection
        self.width = width
        self.itemDisplay = itemDisplay
        self.itemSymbol = itemSymbol
    }
    
    var body: some View {
        Button(action: {
            isShowingDropdown.toggle()
        }) {
            HStack {
                Text(itemDisplay?(selection) ?? selection.rawValue).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.compact.down")
                    .scaleEffect(CGSize(width: 0.7, height: 1.5))
            }
        }
        .buttonStyle(FilterDropdownStyle())
        .frame(width: width)
        .floatingPanel(
            isPresented: $isShowingDropdown,
            width: width + 50,
            height: CGFloat(items.count),
            arrowEdge: .bottom
        ) {
            DropdownListView(
                items: items,
                selection: selection,
                activeIndex: $activeIndex,
                hoveredIndex: $hoveredIndex,
                itemDisplay: itemDisplay,
                itemSymbol: itemSymbol,
                onSelect: { item in
                    selection = item
                    isShowingDropdown = false
                },
                onDismiss: {
                    isShowingDropdown = false
                }
            )
        }
        .onAppear {
            // Set initial active index
            if let currentIndex = items.firstIndex(of: selection) {
                activeIndex = currentIndex
            }
        }
    }
}

/// The dropdown list content
private struct DropdownListView<T: Hashable>: View where T: RawRepresentable, T.RawValue == String {
    let items: [T]
    let selection: T
    @Binding var activeIndex: Int
    @Binding var hoveredIndex: Int?
    let itemDisplay: ((T) -> String)?
    let itemSymbol: ((T) -> String)?
    let onSelect: (T) -> Void
    let onDismiss: () -> Void
    
    @State private var keyboardMonitor: Any?
    @State private var hostingWindow: NSWindow?
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button(action: {
                    onSelect(item)
                }) {
                    HStack {
                        Text(itemDisplay?(item) ?? item.rawValue)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if let symbol = itemSymbol?(item) {
                            Text(symbol)
                                .foregroundColor(.secondary)
                                .font(.system(size: 14, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minWidth: 150)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(backgroundColorForItem(at: index))
                )
                .onHover { isHovered in
                    hoveredIndex = isHovered ? index : nil
                    if isHovered {
                        activeIndex = index
                    }
                }
            }
        }
        .padding(6)
        .background(WindowReader { window in
            hostingWindow = window
        })
        .onAppear {
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }
    
    private func setupKeyboardMonitor() {
        // Remove any existing monitor first
        removeKeyboardMonitor()

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isKeyboardEventForHostingWindow(event) else { return event }

            switch event.keyCode {
            case 125: // Down arrow
                activeIndex = min(activeIndex + 1, items.count - 1)
                return nil
            case 126: // Up arrow
                activeIndex = max(activeIndex - 1, 0)
                return nil
            case 36: // Enter/Return
                if activeIndex < items.count {
                    onSelect(items[activeIndex])
                }
                return nil
            case 53: // Escape
                onDismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func isKeyboardEventForHostingWindow(_ event: NSEvent) -> Bool {
        guard let hostingWindow,
              let eventWindow = event.window,
              eventWindow === hostingWindow,
              hostingWindow.isKeyWindow else {
            return false
        }

        return true
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }
    
    private func backgroundColorForItem(at index: Int) -> Color {
        if index == activeIndex {
            return Color(hex: "#C25B06")
        } else if hoveredIndex == index {
            return Color(hex: "#C25B06")
        } else {
            return .clear
        }
    }
}
