import AppKit

// MARK: - Hover Divider Split View

final class HoverDividerSplitView: NSSplitView {
    private var isDividerVisible = false
    private var trackingArea: NSTrackingArea?
    private var showDividerTask: Task<Void, Never>?
    var isSidebarCollapsed = false

    override var dividerThickness: CGFloat { isSidebarCollapsed ? 0 : 2 }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupDividerTracking()
        }
    }

    private func setupDividerTracking() {
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupDividerTracking()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateDividerVisibility(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateDividerVisibility(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideDivider()
    }

    private func updateDividerVisibility(for event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let dividerRect = getDividerRect()
        let hoverZone = dividerRect.insetBy(dx: -10, dy: 0)
        let shouldShow = hoverZone.contains(location)

        if shouldShow == isDividerVisible && showDividerTask == nil { return }

        if shouldShow {
            guard showDividerTask == nil else { return }
            showDividerTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                showDividerTask = nil
                isDividerVisible = true
                needsDisplay = true
            }
        } else {
            hideDivider()
        }
    }

    private func hideDivider() {
        showDividerTask?.cancel()
        showDividerTask = nil
        guard isDividerVisible else { return }
        isDividerVisible = false
        needsDisplay = true
    }

    private func getDividerRect() -> NSRect {
        guard arrangedSubviews.count >= 2 else { return .zero }

        let leftView = arrangedSubviews[0]
        return NSRect(
            x: leftView.frame.maxX,
            y: 0,
            width: dividerThickness,
            height: frame.height
        )
    }

    override func drawDivider(in rect: NSRect) {
        guard !isSidebarCollapsed, isDividerVisible else { return }
        NSColor.separatorColor.setFill()
        rect.fill()
    }
}

// MARK: - Sidebar Split View Controller

final class SidebarSplitViewController: NSSplitViewController {

    struct Configuration {
        var minWidth: CGFloat = 330
        var autosaveName: String? = nil
        var startsCollapsed: Bool = false
        var widthPersistenceKey: String? = "QuarrySidebarWidth"
    }

    private var sidebarItem: NSSplitViewItem!
    private var contentItem: NSSplitViewItem!
    private var isProgrammaticCollapse = false
    private var isManuallyCollapsed = false
    private var hasAppliedInitialSidebarWidth = false
    private var lastExpandedSidebarWidth: CGFloat?

    var isCollapsed: Bool {
        usesManualCollapse ? isManuallyCollapsed : sidebarItem.isCollapsed
    }

    private let configuration: Configuration
    private var usesManualCollapse: Bool { configuration.autosaveName == nil }
    private var isSidebarItemInstalled: Bool {
        splitViewItems.contains { $0 === sidebarItem }
    }

    init(
        sidebarController: NSViewController,
        contentController: NSViewController,
        configuration: Configuration = Configuration()
    ) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        setupSplitViewItems(sidebarController: sidebarController, contentController: contentController)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupSplitViewItems(sidebarController: NSViewController, contentController: NSViewController) {
        sidebarItem = NSSplitViewItem(viewController: sidebarController)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = configuration.minWidth
        sidebarItem.maximumThickness = .greatestFiniteMagnitude
        sidebarItem.automaticMaximumThickness = .greatestFiniteMagnitude
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)

        contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.minimumThickness = 400
        contentItem.holdingPriority = NSLayoutConstraint.Priority(250)

        splitViewItems = [sidebarItem, contentItem]
    }

    override func loadView() {
        let customSplitView = HoverDividerSplitView()
        customSplitView.isVertical = true
        customSplitView.dividerStyle = .thin
        self.splitView = customSplitView
        super.loadView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let autosaveName = configuration.autosaveName {
            splitView.autosaveName = autosaveName
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggle(_:)),
            name: .toggleLeftSidebar,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSplitViewDidResize(_:)),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitView
        )

        if usesManualCollapse, configuration.startsCollapsed {
            isManuallyCollapsed = true
            applyManualCollapsedLayout()
        } else if configuration.startsCollapsed {
            sidebarItem.isCollapsed = true
        } else if sidebarItem.isCollapsed {
            sidebarItem.isCollapsed = false
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Post initial visibility state so UI can sync
        let isVisible = !isCollapsed
        postVisibilityChange(isVisible: isVisible)
        applyInitialManualLayoutIfNeeded()

        updateHoverDividerState(collapsed: !isVisible)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyInitialManualLayoutIfNeeded()
    }

    private func persistedSidebarWidth() -> CGFloat? {
        guard usesManualCollapse else { return nil }
        guard let key = configuration.widthPersistenceKey else { return nil }
        let saved = UserDefaults.standard.double(forKey: key)
        guard saved >= configuration.minWidth else { return nil }
        return CGFloat(saved)
    }

    private func rememberExpandedSidebarWidth() {
        guard usesManualCollapse, !isManuallyCollapsed else { return }
        guard isSidebarItemInstalled else { return }
        guard isExpandedLayoutSettled else { return }

        let width = sidebarItem.viewController.view.frame.width
        guard width >= configuration.minWidth else { return }
        lastExpandedSidebarWidth = width

        guard let key = configuration.widthPersistenceKey else { return }
        UserDefaults.standard.set(Double(width), forKey: key)
    }

    private var isExpandedLayoutSettled: Bool {
        guard isSidebarItemInstalled else { return false }
        guard splitView.bounds.width > 0 else { return false }
        let sidebarWidth = sidebarItem.viewController.view.frame.width
        let contentWidth = contentItem.viewController.view.frame.width
        let totalWidth = sidebarWidth + contentWidth + splitView.dividerThickness
        return abs(totalWidth - splitView.bounds.width) <= 1 && contentWidth >= contentItem.minimumThickness
    }

    private func applyInitialManualLayoutIfNeeded() {
        guard usesManualCollapse, !hasAppliedInitialSidebarWidth, splitView.bounds.width > 0 else { return }
        hasAppliedInitialSidebarWidth = true

        if isManuallyCollapsed {
            applyManualCollapsedLayout()
        } else {
            restoreManualExpandedWidth()
        }
    }

    private func restoreManualExpandedWidth() {
        guard usesManualCollapse, !isManuallyCollapsed, splitView.bounds.width > 0 else { return }
        if !isSidebarItemInstalled {
            insertSplitViewItem(sidebarItem, at: 0)
        }
        sidebarItem.viewController.view.isHidden = false
        sidebarItem.minimumThickness = configuration.minWidth
        updateHoverDividerState(collapsed: false)

        let width = lastExpandedSidebarWidth ?? persistedSidebarWidth() ?? configuration.minWidth
        splitView.setPosition(clampedSidebarWidth(width), ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()
    }

    private func applyManualCollapsedLayout() {
        guard usesManualCollapse else { return }
        sidebarItem.viewController.view.isHidden = true
        if isSidebarItemInstalled {
            removeSplitViewItem(sidebarItem)
        }
        updateHoverDividerState(collapsed: true)
        splitView.layoutSubtreeIfNeeded()
    }

    private func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        let maxWidth = max(
            configuration.minWidth,
            splitView.bounds.width - contentItem.minimumThickness - splitView.dividerThickness
        )
        return min(max(width, configuration.minWidth), maxWidth)
    }

    private func updateHoverDividerState(collapsed: Bool) {
        guard let hoverSplitView = splitView as? HoverDividerSplitView else { return }
        hoverSplitView.isSidebarCollapsed = collapsed
        hoverSplitView.needsDisplay = true
    }

    @objc private func handleToggle(_ notification: Notification) {
        guard let sourceWindow = notification.object as? NSWindow,
              sourceWindow == view.window else { return }
        toggle()
    }

    @objc private func handleSplitViewDidResize(_ notification: Notification) {
        let isVisible = !isCollapsed
        postVisibilityChange(isVisible: isVisible)
        rememberExpandedSidebarWidth()

        updateHoverDividerState(collapsed: !isVisible)
    }

    func toggle() {
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    func collapse() {
        guard !isCollapsed else { return }
        setSidebar(collapsed: true)
    }

    func expand() {
        guard isCollapsed else { return }
        setSidebar(collapsed: false)
    }

    private func setSidebar(collapsed: Bool) {
        if usesManualCollapse {
            setSidebarManually(collapsed: collapsed)
            return
        }

        isProgrammaticCollapse = collapsed

        updateHoverDividerState(collapsed: collapsed)

        NotificationCenter.default.post(
            name: .sidebarAnimationWillStart,
            object: view.window,
            userInfo: ["isCollapsing": collapsed]
        )

        sidebarItem.isCollapsed = collapsed
        isProgrammaticCollapse = false

        postVisibilityChange(isVisible: !collapsed)
        NotificationCenter.default.post(name: .sidebarAnimationDidEnd, object: view.window)
    }

    private func setSidebarManually(collapsed: Bool) {
        if collapsed {
            rememberExpandedSidebarWidth()
        }

        NotificationCenter.default.post(
            name: .sidebarAnimationWillStart,
            object: view.window,
            userInfo: ["isCollapsing": collapsed]
        )

        isManuallyCollapsed = collapsed
        if collapsed {
            applyManualCollapsedLayout()
        } else {
            restoreManualExpandedWidth()
        }

        postVisibilityChange(isVisible: !collapsed)
        NotificationCenter.default.post(name: .sidebarAnimationDidEnd, object: view.window)
    }

    private func postVisibilityChange(isVisible: Bool) {
        NotificationCenter.default.post(
            name: .sidebarVisibilityChanged,
            object: view.window,
            userInfo: ["isVisible": isVisible]
        )
    }

    // MARK: - NSSplitViewDelegate

    override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        // Only allow collapse via programmatic toggle, not by dragging
        return isProgrammaticCollapse
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
