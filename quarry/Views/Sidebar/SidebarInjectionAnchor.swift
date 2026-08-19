import AppKit
import SwiftUI

/// A zero-impact anchor NSView that can be located by class name from AppKit
/// code and used as an insertion point for sidebar injections.
final class SidebarInjectionAnchorView: NSView {}

struct SidebarInjectionAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarInjectionAnchorView {
        let view = SidebarInjectionAnchorView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = false
        return view
    }

    func updateNSView(_ nsView: SidebarInjectionAnchorView, context: Context) {
        // No-op
    }
}


