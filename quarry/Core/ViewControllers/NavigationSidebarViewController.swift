import AppKit
import SwiftUI

final class NavigationSidebarViewController: NSViewController {

    private static let tooltipDelay: TimeInterval = 0.4

    private let stackView = NSStackView()
    private var itemButtonsContainer = NSStackView()
    nonisolated(unsafe) private var notificationObservers: [Any] = []

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        self.view = container

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)

        let homeButton = makeHomeButton()
        stackView.addArrangedSubview(homeButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: 26).isActive = true
        stackView.setCustomSpacing(4, after: homeButton)
        stackView.setCustomSpacing(4, after: separator)

        itemButtonsContainer.orientation = .vertical
        itemButtonsContainer.alignment = .centerX
        itemButtonsContainer.spacing = 0
        stackView.addArrangedSubview(itemButtonsContainer)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 50),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .sidebarItemsDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildItems()
                }
            }
        )
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .tabDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateSelection()
                }
            }
        )

        rebuildItems()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Home Button

    private func makeHomeButton() -> SidebarIconButton {
        let button = makeSidebarIconButton(systemName: "house.fill")
        button.target = self
        button.action = #selector(homeButtonTapped)
        button.tag = -1
        button.isSelected = true
        button.installCustomTooltip("Home", position: .right, delay: Self.tooltipDelay)
        return button
    }

    @objc private func homeButtonTapped() {
        WindowController.switchToTab(.home)
    }

    private func makeSidebarIconButton(systemName: String, style: SidebarIconButton.Style = .bordered) -> SidebarIconButton {
        let button = SidebarIconButton(frame: NSRect(x: 0, y: 0, width: 50, height: 40), style: style)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 50),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
        button.setIcon(systemName: systemName)
        return button
    }

    // MARK: - Item Buttons

    private func rebuildItems() {
        for subview in itemButtonsContainer.arrangedSubviews {
            itemButtonsContainer.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let items = SidebarItemRegistry.shared.items

        if let separator = stackView.arrangedSubviews.first(where: { $0 is NSBox }) {
            separator.isHidden = items.isEmpty
        }

        for item in items {
            let button = makeItemButton(for: item)
            itemButtonsContainer.addArrangedSubview(button)
        }

        updateSelection()
    }

    private func makeItemButton(for item: SidebarItem) -> SidebarItemButton {
        let button: SidebarItemButton
        var menu: NSMenu?

        switch item {
        case .connection(let id):
            guard let instance = ConnectionService.shared.getInstance(id),
                  instance.connection.modelContext != nil else {
                let placeholder = SidebarItemButton(
                    frame: NSRect(x: 0, y: 0, width: 50, height: 40),
                    fillColor: .gray,
                    label: "?",
                    icon: nil
                )
                placeholder.installCustomTooltip("Unavailable Connection", position: .right, delay: Self.tooltipDelay)
                // Early return skips the shared sizing below; without these the
                // stack view collapses the row and neighbors overlap.
                placeholder.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    placeholder.widthAnchor.constraint(equalToConstant: 50),
                    placeholder.heightAnchor.constraint(equalToConstant: 40),
                ])
                return placeholder
            }
            let color = NSColor(instance.connection.color.color)
            let letter = String(instance.connection.name.prefix(1)).uppercased()
            button = SidebarItemButton(
                frame: NSRect(x: 0, y: 0, width: 50, height: 40),
                fillColor: color,
                label: letter,
                icon: nil
            )
            button.installCustomTooltip(instance.connection.name, position: .right, delay: Self.tooltipDelay)
            menu = makeConnectionContextMenu(instanceId: id, instance: instance)

        case .notebook(let id, let title):
            button = SidebarItemButton(
                frame: NSRect(x: 0, y: 0, width: 50, height: 40),
                fillColor: NSColor(red: 0.6, green: 0.4, blue: 0.1, alpha: 1.0),
                label: nil,
                icon: "doc.text"
            )
            button.installCustomTooltip(title, position: .right, delay: Self.tooltipDelay)
            menu = makeNotebookContextMenu(notebookId: id)
        }

        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 50),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
        button.sidebarItem = item
        button.target = self
        button.action = #selector(itemButtonTapped(_:))
        button.menu = menu
        return button
    }

    @objc private func itemButtonTapped(_ sender: SidebarItemButton) {
        guard let item = sender.sidebarItem else { return }
        switch item {
        case .connection(let uuid):
            WindowController.switchToTab(.connection(uuid))
        case .notebook(let uuid, _):
            WindowController.switchToTab(.notebook(uuid))
        }
    }

    // MARK: - Selection

    private var activeTabType: TabType? {
        guard let window = view.window else { return nil }
        return WindowController.getController(for: window)?.tabType
    }

    private func updateSelection() {
        let tabType = activeTabType

        if let homeButton = stackView.arrangedSubviews.first as? SidebarIconButton {
            homeButton.isSelected = tabType == .home || tabType == nil
        }

        for case let button as SidebarItemButton in itemButtonsContainer.arrangedSubviews {
            guard let item = button.sidebarItem else { continue }

            switch (item, tabType) {
            case (.connection(let itemId), .connection(let activeId)):
                button.isSelected = itemId == activeId
            case (.notebook(let itemId, _), .notebook(let activeId)):
                button.isSelected = itemId == activeId
            default:
                button.isSelected = false
            }
        }
    }

    // MARK: - Context Menus

    private func makeConnectionContextMenu(instanceId: UUID, instance: ConnectionInstance) -> NSMenu {
        let menu = NSMenu()

        let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(disconnectConnection(_:)), keyEquivalent: "")
        disconnectItem.target = self
        disconnectItem.representedObject = instanceId
        menu.addItem(disconnectItem)

        menu.addItem(.separator())

        let copyItem = NSMenuItem(title: "Copy Connection String", action: #selector(copyConnectionString(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = instance.connection.copyableConnectionUri
        menu.addItem(copyItem)

        return menu
    }

    private func makeNotebookContextMenu(notebookId: UUID) -> NSMenu {
        let menu = NSMenu()

        let closeItem = NSMenuItem(title: "Close Notebook", action: #selector(closeNotebook(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.representedObject = notebookId
        menu.addItem(closeItem)

        return menu
    }

    @objc private func disconnectConnection(_ sender: NSMenuItem) {
        guard let instanceId = sender.representedObject as? UUID else { return }
        Task {
            await ConnectionService.shared.removeConnectionInstance(instanceId)
        }
    }

    @objc private func copyConnectionString(_ sender: NSMenuItem) {
        guard let connectionString = sender.representedObject as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(connectionString, forType: .string)
    }

    @objc private func closeNotebook(_ sender: NSMenuItem) {
        guard let notebookId = sender.representedObject as? UUID else { return }
        WindowController.closeNotebookWindow(id: notebookId)
    }
}

// MARK: - SidebarIconButton (Home / Feedback style)

private final class SidebarIconButton: NSButton {
    enum Style { case bordered, borderless }

    private let style: Style
    var isSelected = false { didSet { needsDisplay = true } }
    private var isHovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, style: Style = .bordered) {
        self.style = style
        super.init(frame: frame)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = .labelColor
        wantsLayer = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func setIcon(systemName: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            layer?.contentsScale = window.backingScaleFactor
        }
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let backgroundRect = CGRect(
            x: bounds.midX - 15, y: bounds.midY - 15,
            width: 30, height: 30
        )
        let backgroundPath = CGPath(roundedRect: backgroundRect, cornerWidth: 10, cornerHeight: 10, transform: nil)

        switch style {
        case .bordered where isSelected:
            ctx.addPath(backgroundPath)
            let selectedAlpha: CGFloat = effectiveAppearance.isDarkMode ? 0.1 : 0.4
            NSColor.controlColor.withAlphaComponent(selectedAlpha).setFill()
            ctx.fillPath()

            ctx.addPath(backgroundPath)
            NSColor.separatorColor.setStroke()
            ctx.setLineWidth(1)
            ctx.strokePath()

        case .borderless where isHovering:
            ctx.addPath(backgroundPath)
            let hoverColor = effectiveAppearance.isDarkMode
                ? NSColor.black.withAlphaComponent(0.3)
                : NSColor.white.withAlphaComponent(0.3)
            hoverColor.setFill()
            ctx.fillPath()

        default:
            break
        }

        super.draw(dirtyRect)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return super.rightMouseDown(with: event) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - SidebarItemButton (Connection / Notebook style)

final class SidebarItemButton: NSControl {
    var sidebarItem: SidebarItem?
    var isSelected = false { didSet { needsDisplay = true } }

    private let fillColor: NSColor
    private let label: String?
    private let icon: String?
    private var isHovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, fillColor: NSColor, label: String?, icon: String?) {
        self.fillColor = fillColor
        self.label = label
        self.icon = icon
        super.init(frame: frame)
        wantsLayer = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            layer?.contentsScale = window.backingScaleFactor
        }
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return super.rightMouseDown(with: event) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if isSelected {
            let outerRect = centeredRect(size: 32)
            let outerPath = CGPath(roundedRect: outerRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
            ctx.addPath(outerPath)
            fillColor.setStroke()
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }

        let innerRect = centeredRect(size: 26)
        let innerPath = CGPath(roundedRect: innerRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(innerPath)
        fillColor.setFill()
        ctx.fillPath()

        if let label {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let strSize = str.size()
            str.draw(at: CGPoint(
                x: bounds.midX - strSize.width / 2,
                y: bounds.midY - strSize.height / 2
            ))
        }

        if let icon, let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            let configured = image.withSymbolConfiguration(config) ?? image

            let imageSize = configured.size
            configured.draw(in: CGRect(
                x: bounds.midX - imageSize.width / 2,
                y: bounds.midY - imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            ))
        }
    }

    private func centeredRect(size: CGFloat) -> CGRect {
        CGRect(
            x: bounds.midX - size / 2,
            y: bounds.midY - size / 2,
            width: size,
            height: size
        )
    }
}
