//
//  FloatingPanel.swift
//  Quarry
//
//  Created by Assistant on 7/7/25.
//

import SwiftUI
import AppKit

/// An NSPanel subclass that implements floating panel traits
class FloatingPanel<Content: View>: NSPanel {
    @Binding var isPresented: Bool
    
    init(view: () -> Content,
         contentRect: NSRect,
         backing: NSWindow.BackingStoreType = .buffered,
         defer flag: Bool = false,
         isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        
        super.init(contentRect: contentRect,
                   styleMask: [ .nonactivatingPanel, .titled, .hudWindow, .fullSizeContentView],
                   backing: backing,
                   defer: flag)
        
        // Allow the panel to be on top of other windows
        isFloatingPanel = true
        level = .floating
        
        // Allow the panel to be overlaid in a fullscreen space
        collectionBehavior.insert(.fullScreenAuxiliary)
        
        // Don't show a window title
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        
        /// Sets animations accordingly
        animationBehavior = .none
        
        // Hide when unfocused
        hidesOnDeactivate = false
        
        // Set the content view
        contentView = NSHostingView(rootView: view()
            .ignoresSafeArea()
            .padding(.bottom, -18) /// Dirty hack to remove bottom padding
        )
    }
    
    override func resignMain() {
        super.resignMain()
        close()
    }
    
    override func close() {
        super.close()
        isPresented = false
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Add a FloatingPanel to a view hierarchy
fileprivate struct FloatingPanelModifier<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var contentRect: CGRect
    @ViewBuilder let view: () -> PanelContent
    @State var panel: FloatingPanel<PanelContent>?
    @State private var anchorFrame: CGRect = .zero
    @State private var eventMonitor: Any?
    let arrowEdge: Edge
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: AnchorFrameKey.self, value: geometry.frame(in: .global))
                }
            )
            .onPreferenceChange(AnchorFrameKey.self) { frame in
                anchorFrame = frame
            }
            .onAppear {
                panel = FloatingPanel(view: view, contentRect: contentRect, isPresented: $isPresented)
                if isPresented {
                    present()
                }
            }
            .onDisappear {
                panel?.close()
                panel = nil
                removeEventMonitor()
            }
            .onChange(of: isPresented) { _, value in
                if value {
                    present()
                } else {
                    panel?.close()
                    removeEventMonitor()
                }
            }
    }
    
    private func present() {
        guard let panel = panel, let window = NSApp.mainWindow else { return }
        
        // Convert anchor frame to screen coordinates
        let windowFrame = window.frame
        let screenX = windowFrame.origin.x + anchorFrame.origin.x
        let screenY = windowFrame.origin.y + windowFrame.height - anchorFrame.maxY
        
        // Position panel based on arrow edge
        let panelX: CGFloat
        let panelY: CGFloat
        
        switch arrowEdge {
        case .top:
            panelX = screenX + (anchorFrame.width - panel.frame.width) / 2
            panelY = screenY + anchorFrame.height + 4
        case .bottom:
            panelX = screenX + (anchorFrame.width - panel.frame.width) / 2
            panelY = screenY - panel.frame.height - 4
        case .leading:
            panelX = screenX - panel.frame.width - 4
            panelY = screenY + (anchorFrame.height - panel.frame.height) / 2
        case .trailing:
            panelX = screenX + anchorFrame.width + 4
            panelY = screenY + (anchorFrame.height - panel.frame.height) / 2
        }
        
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        panel.orderFront(nil)
        panel.makeKey()
        
        setupEventMonitor()
    }
    
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            guard let panel = self.panel, let window = event.window else {
                self.isPresented = false
                return event
            }
            
            // If click is not in our panel, close it
            if window != panel {
                self.isPresented = false
            }
            
            return event
        }
    }
    
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// Preference key to track anchor frame
struct AnchorFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// View extension for easy usage
extension View {
    func floatingPanel<Content: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = 200,
        height: CGFloat? = nil,
        arrowEdge: Edge = .bottom,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(FloatingPanelModifier(
            isPresented: isPresented,
            contentRect: CGRect(x: 0, y: 0, width: width, height: height ?? 300),
            view: content,
            arrowEdge: arrowEdge
        ))
    }
}
