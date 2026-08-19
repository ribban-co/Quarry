//
//  CustomTooltip.swift
//  Collection
//
//  Created by Fauzaan on 3/8/25.
//
import SwiftUI
import AppKit

/// Defines the possible positions for the tooltip
enum TooltipPosition {
    case top
    case bottom
    case left
    case right
}

/// Represents a keyboard modifier
struct KeyboardModifier: Identifiable {
    let id = UUID()
    let symbol: String

    static let command = KeyboardModifier(symbol: "⌘")
    static let shift = KeyboardModifier(symbol: "shift")
    static let option = KeyboardModifier(symbol: "⌥")
    static let control = KeyboardModifier(symbol: "⌃")
}

/// Represents a keyboard shortcut for display
struct KeyboardShortcut {
    let modifiers: [KeyboardModifier]
    let key: String
}

// MARK: - Tooltip Coordinator
@MainActor @Observable
final class TooltipCoordinator {
    static let shared = TooltipCoordinator()

    private var currentTooltip: TooltipWindow?
    private var currentOwner: ObjectIdentifier?
    private var showTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private var lastTooltipDismissTime: Date?
    private let warmupDuration: TimeInterval = 0.5

    private init() {
        setupClickMonitor()
    }

    private func setupClickMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.hideTooltip()
            }
            return event
        }
    }

    func scheduleTooltip(
        text: String,
        relativeTo view: NSView,
        position: TooltipPosition,
        alignment: TooltipPosition?,
        spacing: CGFloat,
        shortcut: KeyboardShortcut?,
        delay: TimeInterval
    ) {
        let owner = ObjectIdentifier(view)

        showTask?.cancel()
        hideTooltip()

        currentOwner = owner

        let isWarm = lastTooltipDismissTime.map { Date().timeIntervalSince($0) < warmupDuration } ?? false

        if isWarm {
            showTooltip(
                text: text,
                relativeTo: view,
                position: position,
                alignment: alignment,
                spacing: spacing,
                shortcut: shortcut,
                animated: false
            )
        } else {
            showTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(delay))

                    guard !Task.isCancelled,
                          self?.currentOwner == owner,
                          view.window != nil else {
                        return
                    }

                    self?.showTooltip(
                        text: text,
                        relativeTo: view,
                        position: position,
                        alignment: alignment,
                        spacing: spacing,
                        shortcut: shortcut,
                        animated: true
                    )
                } catch {
                    // Task cancelled
                }
            }
        }
    }

    private func showTooltip(
        text: String,
        relativeTo view: NSView,
        position: TooltipPosition,
        alignment: TooltipPosition?,
        spacing: CGFloat,
        shortcut: KeyboardShortcut?,
        animated: Bool = true
    ) {
        let tooltip = TooltipWindow(text: text, shortcut: shortcut)
        tooltip.show(relativeTo: view, position: position, alignment: alignment, spacing: spacing, animated: animated)
        currentTooltip = tooltip
    }

    func hideTooltip() {
        showTask?.cancel()
        showTask = nil
        currentOwner = nil
        if currentTooltip != nil {
            lastTooltipDismissTime = Date()
        }
        currentTooltip?.hide()
        currentTooltip = nil
    }

    func hideTooltip(for view: NSView) {
        let owner = ObjectIdentifier(view)
        if currentOwner == owner {
            hideTooltip()
        }
    }

    func showTooltipImmediately(
        text: String,
        at point: NSPoint,
        relativeTo view: NSView
    ) {
        showTask?.cancel()
        hideTooltip()
        currentOwner = ObjectIdentifier(view)

        guard let window = view.window else { return }

        let screenPoint = window.convertPoint(toScreen: view.convert(point, to: nil))

        let tooltip = TooltipWindow(text: text, shortcut: nil)
        var tooltipOrigin = screenPoint
        tooltipOrigin.x -= tooltip.frame.width / 2
        tooltipOrigin.y -= (tooltip.frame.height + 2)
        tooltip.setFrameOrigin(tooltipOrigin)

        tooltip.alphaValue = 0
        window.addChildWindow(tooltip, ordered: .above)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            tooltip.animator().alphaValue = 1.0
        })

        currentTooltip = tooltip
    }
}

// MARK: - Tooltip Window
class TooltipWindow: NSWindow {
    private let tooltipView: NSView

    init(text: String, shortcut: KeyboardShortcut? = nil) {
        tooltipView = NSView()
        tooltipView.wantsLayer = true
        tooltipView.layer?.backgroundColor = NSColor.black.cgColor
        tooltipView.layer?.cornerRadius = 10
        tooltipView.layer?.borderWidth = 0.5
        tooltipView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.1).cgColor

        tooltipView.layer?.shadowColor = NSColor.black.cgColor
        tooltipView.layer?.shadowOpacity = 0.2
        tooltipView.layer?.shadowOffset = CGSize(width: 0, height: 1)
        tooltipView.layer?.shadowRadius = 1

        let padding: CGFloat = 8
        var contentWidth: CGFloat = 0
        var contentHeight: CGFloat = 0

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.sizeToFit()

        if let shortcut = shortcut {
            var currentX: CGFloat = padding + 2
            let keyHeight: CGFloat = 18
            let totalHeight = max(label.frame.height, keyHeight) + padding * 2

            let labelY = (totalHeight - label.frame.height) / 2
            let keyY = (totalHeight - keyHeight) / 2

            label.frame = NSRect(
                x: currentX,
                y: labelY,
                width: label.frame.width,
                height: label.frame.height
            )
            tooltipView.addSubview(label)
            currentX += label.frame.width + 10

            for modifier in shortcut.modifiers {
                let modifierView = Self.createKeyModifierView(symbol: modifier.symbol)
                modifierView.frame.origin = NSPoint(x: currentX, y: keyY)
                tooltipView.addSubview(modifierView)
                currentX += modifierView.frame.width + 6
            }

            let keyView = Self.createKeyView(symbol: shortcut.key)
            keyView.frame.origin = NSPoint(x: currentX, y: keyY)
            tooltipView.addSubview(keyView)
            currentX += keyView.frame.width

            contentWidth = currentX + padding
            contentHeight = totalHeight
        } else {
            label.frame = NSRect(
                x: padding,
                y: padding,
                width: label.frame.width,
                height: label.frame.height
            )
            tooltipView.addSubview(label)

            contentWidth = label.frame.width + padding * 2
            contentHeight = label.frame.height + padding * 2
        }

        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: contentHeight
        )

        super.init(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.backgroundColor = .clear
        self.isOpaque = false
        self.level = .popUpMenu
        self.hasShadow = false
        self.ignoresMouseEvents = true

        tooltipView.frame = contentRect
        self.contentView = tooltipView
    }

    private static func createKeyModifierView(symbol: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.2, alpha: 1.0).cgColor
        container.layer?.cornerRadius = 4

        let label = NSTextField(labelWithString: symbol)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center
        label.sizeToFit()

        let width = max(label.frame.width, 20)
        let height: CGFloat = 18

        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        label.frame = NSRect(
            x: (width - label.frame.width) / 2,
            y: (height - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )

        container.addSubview(label)
        return container
    }

    private static func createKeyView(symbol: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.2, alpha: 1.0).cgColor
        container.layer?.cornerRadius = 4

        let label = NSTextField(labelWithString: symbol)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center
        label.sizeToFit()

        let width = max(label.frame.width, 20)
        let height: CGFloat = 18

        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        label.frame = NSRect(
            x: (width - label.frame.width) / 2,
            y: (height - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )

        container.addSubview(label)
        return container
    }

    func show(relativeTo view: NSView, position: TooltipPosition, alignment: TooltipPosition?, spacing: CGFloat, animated: Bool = true) {
        guard let window = view.window else { return }

        let viewBounds = view.bounds
        let windowPoint = view.convert(viewBounds, to: nil)
        let screenRect = window.convertToScreen(windowPoint)

        var tooltipOrigin = NSPoint.zero

        switch position {
        case .top:
            tooltipOrigin.y = screenRect.maxY + spacing
            if let alignment = alignment {
                switch alignment {
                case .left:
                    tooltipOrigin.x = screenRect.minX
                case .right:
                    tooltipOrigin.x = screenRect.maxX - self.frame.width
                default:
                    tooltipOrigin.x = screenRect.midX - self.frame.width / 2
                }
            } else {
                tooltipOrigin.x = screenRect.midX - self.frame.width / 2
            }

        case .bottom:
            tooltipOrigin.y = screenRect.minY - self.frame.height - spacing
            if let alignment = alignment {
                switch alignment {
                case .left:
                    tooltipOrigin.x = screenRect.minX
                case .right:
                    tooltipOrigin.x = screenRect.maxX - self.frame.width
                default:
                    tooltipOrigin.x = screenRect.midX - self.frame.width / 2
                }
            } else {
                tooltipOrigin.x = screenRect.midX - self.frame.width / 2
            }

        case .left:
            tooltipOrigin.x = screenRect.minX - self.frame.width - spacing
            if let alignment = alignment {
                switch alignment {
                case .top:
                    tooltipOrigin.y = screenRect.maxY - self.frame.height
                case .bottom:
                    tooltipOrigin.y = screenRect.minY
                default:
                    tooltipOrigin.y = screenRect.midY - self.frame.height / 2
                }
            } else {
                tooltipOrigin.y = screenRect.midY - self.frame.height / 2
            }

        case .right:
            tooltipOrigin.x = screenRect.maxX + spacing
            if let alignment = alignment {
                switch alignment {
                case .top:
                    tooltipOrigin.y = screenRect.maxY - self.frame.height
                case .bottom:
                    tooltipOrigin.y = screenRect.minY
                default:
                    tooltipOrigin.y = screenRect.midY - self.frame.height / 2
                }
            } else {
                tooltipOrigin.y = screenRect.midY - self.frame.height / 2
            }
        }

        self.setFrameOrigin(tooltipOrigin)

        if animated {
            self.alphaValue = 0
            window.addChildWindow(self, ordered: .above)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                self.animator().alphaValue = 1.0
            })
        } else {
            self.alphaValue = 1.0
            window.addChildWindow(self, ordered: .above)
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0.0
        }) {
            MainActor.assumeIsolated {
                self.parent?.removeChildWindow(self)
                self.orderOut(nil)
            }
        }
    }
}

// MARK: - NSView Wrapper for Tooltip Tracking
struct TooltipHostView: NSViewRepresentable {
    let text: String
    let delay: Double
    let position: TooltipPosition
    let alignment: TooltipPosition?
    let shortcut: KeyboardShortcut?
    let spacing: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = TooltipTrackingView()
        view.tooltipText = text
        view.tooltipDelay = delay
        view.tooltipPosition = position
        view.tooltipAlignment = alignment
        view.tooltipShortcut = shortcut
        view.tooltipSpacing = spacing
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let trackingView = nsView as? TooltipTrackingView {
            trackingView.tooltipText = text
            trackingView.tooltipDelay = delay
            trackingView.tooltipPosition = position
            trackingView.tooltipAlignment = alignment
            trackingView.tooltipShortcut = shortcut
            trackingView.tooltipSpacing = spacing
        }
    }
}

class TooltipTrackingView: NSView {
    var tooltipText: String = ""
    var tooltipDelay: Double = 1.0
    var tooltipPosition: TooltipPosition = .bottom
    var tooltipAlignment: TooltipPosition?
    var tooltipShortcut: KeyboardShortcut?
    var tooltipSpacing: CGFloat = 8

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)

        Task { @MainActor in
            TooltipCoordinator.shared.scheduleTooltip(
                text: self.tooltipText,
                relativeTo: self,
                position: self.tooltipPosition,
                alignment: self.tooltipAlignment,
                spacing: self.tooltipSpacing,
                shortcut: self.tooltipShortcut,
                delay: self.tooltipDelay
            )
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)

        Task { @MainActor in
            TooltipCoordinator.shared.hideTooltip(for: self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        Task { @MainActor in
            TooltipCoordinator.shared.hideTooltip(for: self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)

        Task { @MainActor in
            TooltipCoordinator.shared.hideTooltip(for: self)
        }
    }
}

// MARK: - SwiftUI ViewModifier
struct CustomTooltip: ViewModifier {
    let text: String
    let delay: Double
    let position: TooltipPosition
    let alignment: TooltipPosition?
    let shortcut: KeyboardShortcut?
    let spacing: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                TooltipHostView(
                    text: text,
                    delay: delay,
                    position: position,
                    alignment: alignment,
                    shortcut: shortcut,
                    spacing: spacing
                )
            )
    }
}

// MARK: - NSView Extension for AppKit Tooltip Support

private class TooltipHoverTracker: NSResponder {
    static var associatedKey: UInt8 = 0

    let text: String
    let shortcut: KeyboardShortcut?
    let position: TooltipPosition
    let delay: TimeInterval
    let spacing: CGFloat
    weak var owner: NSView?

    init(text: String, shortcut: KeyboardShortcut?, position: TooltipPosition, delay: TimeInterval, spacing: CGFloat, owner: NSView) {
        self.text = text
        self.shortcut = shortcut
        self.position = position
        self.delay = delay
        self.spacing = spacing
        self.owner = owner
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseEntered(with event: NSEvent) {
        guard let owner else { return }
        Task { @MainActor in
            TooltipCoordinator.shared.scheduleTooltip(
                text: self.text,
                relativeTo: owner,
                position: self.position,
                alignment: nil,
                spacing: self.spacing,
                shortcut: self.shortcut,
                delay: self.delay
            )
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard let owner else { return }
        Task { @MainActor in
            TooltipCoordinator.shared.hideTooltip(for: owner)
        }
    }
}

extension NSView {
    func installCustomTooltip(
        _ text: String,
        shortcut: KeyboardShortcut? = nil,
        position: TooltipPosition = .bottom,
        delay: TimeInterval = 1.5,
        spacing: CGFloat = 8
    ) {
        toolTip = nil
        // Re-installation (e.g. on view reconfiguration) must not stack
        // tracking areas: drop any area owned by a previous tracker first.
        for trackingArea in trackingAreas where trackingArea.owner is TooltipHoverTracker {
            removeTrackingArea(trackingArea)
        }
        let tracker = TooltipHoverTracker(
            text: text,
            shortcut: shortcut,
            position: position,
            delay: delay,
            spacing: spacing,
            owner: self
        )
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: tracker,
            userInfo: nil
        ))
        objc_setAssociatedObject(self, &TooltipHoverTracker.associatedKey, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// MARK: - SwiftUI Extensions (Backward Compatible)
extension View {
    func customHelp(
        delay: Double = 1,
        position: TooltipPosition = .bottom,
        shortcut: KeyboardShortcut? = nil,
        alignment: TooltipPosition? = nil,
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        self.modifier(CustomTooltip(
            text: extractText(from: content()),
            delay: delay,
            position: position,
            alignment: alignment,
            shortcut: shortcut,
            spacing: spacing
        ))
    }

    func customHelp(
        _ text: String,
        delay: Double = 1.5,
        position: TooltipPosition = .bottom,
        shortcut: KeyboardShortcut? = nil,
        alignment: TooltipPosition? = nil,
        spacing: CGFloat = 8
    ) -> some View {
        self.modifier(CustomTooltip(
            text: text,
            delay: delay,
            position: position,
            alignment: alignment,
            shortcut: shortcut,
            spacing: spacing
        ))
    }

    private func extractText(from view: some View) -> String {
        return "Tooltip"
    }
}
