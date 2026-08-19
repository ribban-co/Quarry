import AppKit

/// Shared timing for notebook mode changes, so the content swap, the toolbar
/// swap, the segment indicator and the agent sidebar all move on one curve
/// instead of each animating — or cutting — on its own.
@MainActor
enum NotebookTransition {

    static let duration: TimeInterval = 0.2

    static var timing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)
    }

    static func run(_ animations: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            context.allowsImplicitAnimation = true
            animations()
        }
    }

    /// Crossfades between two overlapping sibling views.
    static func crossfade(show incoming: NSView, hide outgoing: NSView) {
        guard incoming !== outgoing else { return }

        incoming.alphaValue = outgoing.isHidden ? 1 : 0
        incoming.isHidden = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            context.allowsImplicitAnimation = true
            incoming.animator().alphaValue = 1
            outgoing.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                // A newer crossfade may have re-shown this view mid-flight.
                guard outgoing.alphaValue == 0 else { return }
                outgoing.isHidden = true
                outgoing.alphaValue = 1
            }
        }
    }

    /// Shows the target immediately, for initial state rather than a change.
    static func snap(show incoming: NSView, hide outgoing: [NSView]) {
        incoming.isHidden = false
        incoming.alphaValue = 1
        for view in outgoing where view !== incoming {
            view.isHidden = true
            view.alphaValue = 1
        }
    }
}
