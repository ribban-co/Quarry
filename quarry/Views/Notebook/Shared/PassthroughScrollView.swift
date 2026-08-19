import AppKit

final class PassthroughScrollView: NSScrollView {
    var isScrollingEnabled = true

    override func scrollWheel(with event: NSEvent) {
        if !isScrollingEnabled {
            nextResponder?.scrollWheel(with: event)
            return
        }
        guard let documentView else {
            nextResponder?.scrollWheel(with: event)
            return
        }

        let canScrollVertically = documentView.frame.height > contentView.bounds.height + 1
        if canScrollVertically {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}
