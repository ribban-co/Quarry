import AppKit
import SwiftData

/// Hosts the table view's right dock as a single resizable panel with a shared
/// chat-style header toolbar. A mode-switch dropdown in the header flips the
/// content below between Row Detail and the Chat panel. Owns the resize handle
/// and the header so the child panels can stay content-only.
@MainActor
final class RightSidebarContainerViewController: NSViewController {

    private enum Layout {
        static let minWidth: CGFloat = 240
        static let maxWidth: CGFloat = 500
    }

    private enum Mode {
        case rowDetail
        case chat
    }

    private let instance: ConnectionInstance
    private let appViewModel: AppViewModel
    private let modelContainer: ModelContainer
    private let onWidthChange: ((CGFloat) -> Void)?
    private let onClose: (() -> Void)?

    private var mode: Mode = .rowDetail

    private let dividerView = RightSidebarResizeHandleView()
    private let contentRegion = NSView()
    private let headerView = AgentHeaderView()
    private let childHost = NSView()

    private var rowDetailController: RowDetailSidebarViewController?
    private var chatController: TableChatSidebarViewController?
    private var activeChild: NSViewController?

    init(
        instance: ConnectionInstance,
        appViewModel: AppViewModel,
        modelContainer: ModelContainer,
        onWidthChange: ((CGFloat) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.instance = instance
        self.appViewModel = appViewModel
        self.modelContainer = modelContainer
        self.onWidthChange = onWidthChange
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Called by `DocumentViewController` before the dock is removed so the
    /// chat can decline any pending write approval and cancel streaming —
    /// otherwise a suspended continuation would retain the whole chat stack.
    func prepareForRemoval() {
        closeChatHistoryPopover()
        chatController?.prepareForRemoval()
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        self.view = root

        setupDivider()
        setupContentRegion()
        setupHeader()
        setupChildHost()
        setupConstraints()
    }

    func loadInitialContent() {
        // Default to Row Detail when a row is selected, otherwise Chat. The user
        // can still switch modes from the header dropdown afterwards.
        let hasRowSelection = !(instance.selectedTab?.selectedRowData?.isEmpty ?? true)
        showChild(for: hasRowSelection ? .rowDetail : .chat)
    }

    // MARK: - Setup

    private func setupDivider() {
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.onDrag = { [weak self] delta in
            guard let self else { return }
            let newWidth = max(
                Layout.minWidth,
                min(Layout.maxWidth, self.appViewModel.rightSidebarWidth - delta)
            )
            guard newWidth != self.appViewModel.rightSidebarWidth else { return }
            self.appViewModel.rightSidebarWidth = newWidth
            self.onWidthChange?(newWidth)
        }
        view.addSubview(dividerView)
    }

    private func setupContentRegion() {
        contentRegion.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentRegion)
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.setModeSwitcherVisible(true)
        headerView.setComposeVisible(false)
        headerView.setCompactHeight(true)
        headerView.setTrailingInset(4)
        headerView.setControlSize(30)
        headerView.modeMenuProvider = { [weak self] in
            self?.makeModeMenu() ?? NSMenu()
        }
        headerView.onClose = { [weak self] in
            self?.onClose?()
        }
        headerView.onNewChat = { [weak self] in
            self?.showChatHistoryPopover()
        }
        contentRegion.addSubview(headerView)
    }

    private func setupChildHost() {
        childHost.translatesAutoresizingMaskIntoConstraints = false
        contentRegion.addSubview(childHost)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            dividerView.topAnchor.constraint(equalTo: view.topAnchor),
            dividerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dividerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 6),

            contentRegion.topAnchor.constraint(equalTo: view.topAnchor),
            contentRegion.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            contentRegion.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentRegion.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerView.topAnchor.constraint(equalTo: contentRegion.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentRegion.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentRegion.trailingAnchor),

            childHost.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            childHost.leadingAnchor.constraint(equalTo: contentRegion.leadingAnchor),
            childHost.trailingAnchor.constraint(equalTo: contentRegion.trailingAnchor),
            childHost.bottomAnchor.constraint(equalTo: contentRegion.bottomAnchor),
        ])
    }

    // MARK: - Mode Switching

    private func makeModeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let modes: [(title: String, mode: Mode)] = [
            ("Chat", .chat),
            ("Row Detail", .rowDetail),
        ]
        for entry in modes {
            let item = NSMenuItem(title: entry.title, action: #selector(modeMenuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.mode
            item.state = mode == entry.mode ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func modeMenuItemSelected(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? Mode else { return }
        showChild(for: mode)
    }

    private func showChild(for mode: Mode) {
        self.mode = mode
        let controller: NSViewController
        switch mode {
        case .rowDetail:
            controller = makeRowDetailController()
        case .chat:
            controller = makeChatController()
        }

        configureHeader(for: mode)

        guard activeChild !== controller else { return }

        if let activeChild {
            // A pending approval card would go offscreen with the chat view,
            // leaving the agent suspended with no way to decide.
            (activeChild as? TableChatSidebarViewController)?.declinePendingApproval()
            activeChild.view.removeFromSuperview()
            activeChild.removeFromParent()
        }

        addChild(controller)
        let childView = controller.view
        childView.translatesAutoresizingMaskIntoConstraints = false
        childHost.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.topAnchor.constraint(equalTo: childHost.topAnchor),
            childView.leadingAnchor.constraint(equalTo: childHost.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: childHost.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: childHost.bottomAnchor),
        ])
        activeChild = controller

        if let rowDetail = controller as? RowDetailSidebarViewController {
            rowDetail.loadInitialContent()
        }
    }

    private func configureHeader(for mode: Mode) {
        switch mode {
        case .chat:
            headerView.updateTitle(chatController?.currentChatTitle ?? "New Chat")
            headerView.setModeIcon("message")
        case .rowDetail:
            headerView.updateTitle("Row Detail")
            headerView.setModeIcon("list.bullet.rectangle")
        }
    }

    // MARK: - Chat History Popover

    private var chatHistoryPopover: NSPopover?

    private func showChatHistoryPopover() {
        guard mode == .chat, let chatSidebar = chatController else { return }

        if let existing = chatHistoryPopover, existing.isShown {
            existing.close()
            chatHistoryPopover = nil
            return
        }

        // The unused chat at the top of the list *is* the "New Chat" entry, so
        // the popover needs no separate create action.
        chatSidebar.ensureUnusedChat()

        let popoverVC = AgentChatHistoryPopoverController(
            chats: chatSidebar.chats,
            currentChatId: chatSidebar.currentChatId
        )
        popoverVC.onSelectChat = { [weak self] chat in
            self?.closeChatHistoryPopover()
            self?.chatController?.selectChat(chat)
        }
        popoverVC.onDeleteChat = { [weak self] chat in
            self?.closeChatHistoryPopover()
            self?.chatController?.deleteChat(chat)
        }

        let popover = NSPopover()
        popover.contentViewController = popoverVC
        popover.behavior = .transient
        popover.animates = true
        popover.show(relativeTo: headerView.dropdownButtonBounds, of: headerView, preferredEdge: .minY)
        chatHistoryPopover = popover
    }

    private func closeChatHistoryPopover() {
        chatHistoryPopover?.close()
        chatHistoryPopover = nil
    }

    private func makeRowDetailController() -> RowDetailSidebarViewController {
        if let rowDetailController { return rowDetailController }
        let controller = RowDetailSidebarViewController(instance: instance)
        rowDetailController = controller
        return controller
    }

    private func makeChatController() -> TableChatSidebarViewController {
        if let chatController { return chatController }
        let controller = TableChatSidebarViewController(instance: instance, modelContainer: modelContainer)
        controller.onTitleChange = { [weak self] title in
            guard let self, self.mode == .chat else { return }
            self.headerView.updateTitle(title)
        }
        chatController = controller
        return controller
    }
}

// MARK: - Resize Handle

private final class RightSidebarResizeHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isDragging = false
    private var isHovering = false
    private var didPushCursor = false
    private var lastX: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    // Let AppKit own the hover cursor via cursor rects — it shows the resize
    // cursor only within these bounds and reverts automatically, so it can't
    // leak across the rest of the sidebar the way enter/exit push/pop can.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        refreshHoverState()
    }

    private func refreshHoverState() {
        guard let window else {
            if isHovering {
                isHovering = false
                needsDisplay = true
            }
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        lastX = event.locationInWindow.x
        // Keep the resize cursor pinned for the duration of the drag even if the
        // pointer strays outside the 6pt bounds. Balanced 1:1 with mouseUp.
        NSCursor.resizeLeftRight.push()
        didPushCursor = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let delta = currentX - lastX
        lastX = currentX
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        if didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovering || isDragging else { return }

        let highlightRect = NSRect(
            x: (bounds.width - 2) / 2,
            y: 0,
            width: 2,
            height: bounds.height
        )
        NSColor.separatorColor.setFill()
        highlightRect.fill()
    }
}
