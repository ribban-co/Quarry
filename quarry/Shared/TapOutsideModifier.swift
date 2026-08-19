import SwiftUI
import AppKit

extension View {
    func onTapOutside(perform action: @escaping () -> Void) -> some View {
        self.background(TapOutsideTracker(action: action))
    }
}

private struct TapOutsideTracker: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> TapOutsideNSView {
        let view = TapOutsideNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: TapOutsideNSView, context: Context) {
        nsView.action = action
    }
}

private final class TapOutsideNSView: NSView {
    var action: (() -> Void)?
    nonisolated(unsafe) private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            addMonitor()
        } else {
            removeMonitor()
        }
    }

    private func addMonitor() {
        removeMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleClick(event)
            return event
        }
    }

    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleClick(_ event: NSEvent) {
        guard let window = self.window, event.window == window else { return }
        let locationInWindow = event.locationInWindow
        let locationInSelf = self.convert(locationInWindow, from: nil)
        if !self.bounds.contains(locationInSelf) {
            action?()
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
