//
//  ArrayFloatingDropdown.swift
//  Quarry
//
//  Created by Fauzaan on 7/8/25.
//

import SwiftUI
import AppKit

/// A floating dropdown that works with arrays of any type
struct ArrayFloatingDropdown<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    @State private var isShowingDropdown = false
    @State private var activeIndex: Int = 0
    @State private var hoveredIndex: Int? = nil
    
    let width: CGFloat
    let itemDisplay: (T) -> String
    
    init(items: [T],
         selection: Binding<T>,
         width: CGFloat = 120,
         itemDisplay: @escaping (T) -> String) {
        self.items = items
        self._selection = selection
        self.width = width
        self.itemDisplay = itemDisplay
    }
    
    var body: some View {
        Button(action: {
            isShowingDropdown.toggle()
        }) {
            HStack {
                Text(itemDisplay(selection)).lineLimit(1)
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
            ArrayDropdownListView(
                items: items,
                selection: selection,
                activeIndex: $activeIndex,
                hoveredIndex: $hoveredIndex,
                itemDisplay: itemDisplay,
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

/// The dropdown list content for arrays
private struct ArrayDropdownListView<T: Hashable>: View {
    let items: [T]
    let selection: T
    @Binding var activeIndex: Int
    @Binding var hoveredIndex: Int?
    let itemDisplay: (T) -> String
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
                        Text(itemDisplay(item))
                            .foregroundColor(foregroundColorForItem(at: index))
                        Spacer()
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
            return .brand
        } else if hoveredIndex == index {
            return .brand.opacity(0.12)
        } else {
            return .clear
        }
    }

    private func foregroundColorForItem(at index: Int) -> Color {
        index == activeIndex ? .onBrand : .primary
    }
}
