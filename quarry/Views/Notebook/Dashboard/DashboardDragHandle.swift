import AppKit

final class DashboardDragHandle: NSView {

    var onDragBegan: ((NSEvent) -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: ((NSEvent) -> Void)?
    var onDragCancelled: (() -> Void)?

    private let imageView: NSImageView
    private var isDragging = false
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag to reorder")
        imageView = NSImageView(image: image ?? NSImage())
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: frameRect)

        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    isolated deinit {
        removeEventMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, isDragging {
            cancelDrag()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isDragging else { return }
        isDragging = true
        installEventMonitor()
        NSCursor.closedHand.push()
        onDragBegan?(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        finishDrag(with: event)
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel, .gesture, .swipe, .magnify, .rotate]
        ) { [weak self] event in
            guard let self, self.isDragging else { return event }

            switch event.type {
            case .leftMouseDragged:
                self.onDragMoved?(event)
            case .leftMouseUp:
                self.finishDrag(with: event)
            case .scrollWheel, .gesture, .swipe, .magnify, .rotate, .rightMouseDown, .otherMouseDown:
                self.cancelDrag()
            default:
                break
            }

            return event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func finishDrag(with event: NSEvent) {
        isDragging = false
        removeEventMonitor()
        NSCursor.pop()
        onDragEnded?(event)
    }

    private func cancelDrag() {
        isDragging = false
        removeEventMonitor()
        NSCursor.pop()
        onDragCancelled?()
    }

}

enum NotebookDragVisuals {

    static func dragIconName(for blockType: NotebookBlockType, filled: Bool) -> String {
        switch blockType {
        case .chart:
            filled ? "chart.bar.fill" : "chart.bar"
        case .text:
            filled ? "doc.text.fill" : "doc.text"
        case .singleValue:
            "numbers.rectangle"
        case .query:
            "terminal"
        }
    }

    @MainActor
    static func dragCard(title: String, iconName: String, size: NSSize? = nil, zPosition: CGFloat = 1000) -> CALayer {
        let card = CALayer()
        let cardWidth = size?.width ?? 180
        let cardHeight = size?.height ?? 36
        card.frame = NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
        card.cornerRadius = 8
        card.masksToBounds = false
        card.zPosition = zPosition

        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            card.backgroundColor = isDark
                ? NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
                : NSColor.white.withAlphaComponent(0.95).cgColor
        }

        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.2
        card.shadowOffset = CGSize(width: 0, height: -1)
        card.shadowRadius = 6

        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            let iconLayer = CALayer()
            iconLayer.frame = NSRect(x: 10, y: (cardHeight - 16) / 2, width: 16, height: 16)
            iconLayer.contents = configured.cgImage(forProposedRect: nil, context: nil, hints: nil)
            iconLayer.contentsGravity = .resizeAspect
            card.addSublayer(iconLayer)
        }

        let textLayer = CATextLayer()
        textLayer.string = title
        textLayer.fontSize = 12
        textLayer.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.truncationMode = .end
        textLayer.frame = NSRect(x: 32, y: (cardHeight - 16) / 2, width: cardWidth - 44, height: 16)

        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            textLayer.foregroundColor = NSColor.labelColor.cgColor
        }

        card.addSublayer(textLayer)
        return card
    }

    static func autoScrollDelta(
        for locationInScroll: NSPoint,
        visibleHeight: CGFloat,
        edgeZone: CGFloat = 90,
        speed: CGFloat = 36
    ) -> CGFloat {
        if locationInScroll.y < edgeZone {
            return -((edgeZone - locationInScroll.y) / edgeZone) * speed
        }
        if locationInScroll.y > visibleHeight - edgeZone {
            return ((locationInScroll.y - (visibleHeight - edgeZone)) / edgeZone) * speed
        }
        return 0
    }
}
