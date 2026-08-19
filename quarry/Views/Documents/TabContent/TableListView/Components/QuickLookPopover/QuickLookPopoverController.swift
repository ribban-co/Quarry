import AppKit

@MainActor
final class QuickLookPopoverController {
    static let shared = QuickLookPopoverController()

    private var popover: NSPopover?

    private init() {}

    func showQuickLook(
        for content: String,
        fieldName: String,
        dataType: String,
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        onSave: @escaping (String) -> Void
    ) {
        closePopover()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let viewController = QuickLookViewController(
            content: content,
            onResizeStart: { [weak popover] in
                popover?.animates = false
            },
            onResize: { [weak popover] newSize in
                popover?.contentSize = newSize
            },
            onResizeEnd: { [weak popover] in
                popover?.animates = true
            },
            onSave: onSave,
            onDismiss: { [weak self] in
                self?.closePopover()
            }
        )

        popover.contentViewController = viewController
        popover.contentSize = viewController.preferredContentSize

        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: .maxY)
        viewController.configureResizeBehavior(relativeTo: positioningRect, of: positioningView)

        self.popover = popover
    }

    func closePopover() {
        popover?.performClose(nil)
        popover = nil
    }
}
