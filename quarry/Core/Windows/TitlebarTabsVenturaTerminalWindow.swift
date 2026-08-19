import AppKit

@MainActor
class TitlebarTabsVenturaTerminalWindow: NSWindow {
    private weak var tabBarMouseTarget: NSView?

    // KVO on the tab group — the system resets the titlebar appearance on tab
    // group changes (including the implicit one that happens during fullscreen
    // exit), and that reset is what brings the white toolbar bg back. Re-running
    // our scrub from these observers is what Ghostty does in their equivalent
    // `TransparentTitlebarTerminalWindow` and is the missing piece our existing
    // fullscreen-notification cleanup doesn't cover.
    private var tabGroupWindowsObservation: NSKeyValueObservation?
    private var tabBarVisibleObservation: NSKeyValueObservation?

    @MainActor
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        titlebarAppearsTransparent = true
        acceptsMouseMovedEvents = true
        setupFullscreenNotifications()
    }
    var titlebarContainer: NSView? {
        if !styleMask.contains(.fullScreen) {
            return contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView")
        }

        for window in NSApplication.shared.windows {
            guard window.className == "NSToolbarFullScreenWindow" else { continue }
            guard window.parent == self else { continue }

            return window.contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView")
        }

        return nil
    }

    // MARK: NSWindow

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            titlebarAppearsTransparent = true
            acceptsMouseMovedEvents = true
            setupFullscreenNotifications()
            updateTitlebarVisibility()
        }
    }

    override func toggleTabBar(_ sender: Any?) {}

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleTabBar(_:)) {
            return false
        }
        return super.validateUserInterfaceItem(item)
    }

    private func setupFullscreenNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillEnterFullScreen(_:)),
            name: NSWindow.willEnterFullScreenNotification,
            object: self
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEnterFullScreen(_:)),
            name: NSWindow.didEnterFullScreenNotification,
            object: self
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillExitFullScreen(_:)),
            name: NSWindow.willExitFullScreenNotification,
            object: self
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidExitFullScreen(_:)),
            name: NSWindow.didExitFullScreenNotification,
            object: self
        )
    }

    // MARK: - Titlebar Tabs

    private func updateTitlebarVisibility() {
//        titleVisibility = .hidden
//        titlebarAppearsTransparent = true
//        titlebarSeparatorStyle = .none
//        if let contentView = contentView {
//            let windowFrame = frame
//            let newContentFrame = NSRect(
//                x: 0,
//                y: 0,
//                width: windowFrame.width,
//                height: windowFrame.height
//            )
//            contentView.frame = newContentFrame
//        }
    }

    @objc func windowWillEnterFullScreen(_ notification: Notification) {
        updateFullscreenTitlebarTransparency()
        scheduleTitlebarChromeCleanup()
    }

    @objc func windowDidEnterFullScreen(_ notification: Notification) {
        updateFullscreenTitlebarTransparency()
        scheduleTitlebarChromeCleanup()
    }

    @objc func windowWillExitFullScreen(_ notification: Notification) {
        updateTitlebarVisibility()
        scheduleTitlebarChromeCleanup()
    }

    @objc func windowDidExitFullScreen(_ notification: Notification) {
        updateTitlebarVisibility()
        scheduleTitlebarChromeCleanup()
    }

    private func updateFullscreenTitlebarTransparency() {
        if styleMask.contains(.fullScreen) {
            titlebarAppearsTransparent = true
            backgroundColor = NSColor.clear
            isOpaque = false

            self.setFullscreenTitlebarTransparent()
        }
    }

    private func setFullscreenTitlebarTransparent() {
        for window in NSApplication.shared.windows {
            guard window.className == "NSToolbarFullScreenWindow" else { continue }
            guard window.parent == self else { continue }

            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor.clear
            window.isOpaque = false

            if let titlebarContainer = window.contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView") {
                for effectView in titlebarContainer.descendants(withClassName: "NSVisualEffectView") {
                    effectView.isHidden = true
                }
            }
            break
        }
    }

    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        let isTabBar = isTabBar(childViewController)

        if isTabBar {
            childViewController.layoutAttribute = .right
            updateTitlebarVisibility()
            childViewController.identifier = Self.tabBarIdentifier
        }

        super.addTitlebarAccessoryViewController(childViewController)

//        if #available(macOS 26, *), isTabBar {
//            hideTabBarAccessoryClipViews()
//
//            Task { @MainActor [weak self] in
//                self?.hideTabBarAccessoryClipViews()
//            }
//
//            Task { @MainActor [weak self] in
//                try? await Task.sleep(for: .milliseconds(100))
//                self?.hideTabBarAccessoryClipViews()
//            }
//
//            Task { @MainActor [weak self] in
//                try? await Task.sleep(for: .milliseconds(300))
//                self?.hideTabBarAccessoryClipViews()
//            }
//        }
    }

    private func scheduleTitlebarChromeCleanup() {
        guard #available(macOS 26, *) else { return }

        hideTabBarAccessoryClipViews()

        Task { @MainActor [weak self] in
            self?.hideTabBarAccessoryClipViews()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.hideTabBarAccessoryClipViews()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.hideTabBarAccessoryClipViews()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.hideTabBarAccessoryClipViews()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            self?.hideTabBarAccessoryClipViews()
        }
    }

    @available(macOS 26, *)
    private func hideTabBarAccessoryClipViews() {
        guard let titlebarContainer = titlebarContainer else { return }

        hideTitlebarBackgroundViews(in: titlebarContainer)

        for clipView in titlebarContainer.descendants(withClassName: "NSTitlebarAccessoryClipView") {
            if clipView.firstDescendant(withClassName: "NSTabBar") != nil {
                // Don't force `clipView.frame = .zero` — the system clip view's
                // children carry autoresizing constraints that can conflict during
                // fullscreen transitions. Hidden + transparent is sufficient.
                clipView.isHidden = true
                clipView.alphaValue = 0
            }
        }

        for tabBar in titlebarContainer.descendants(withClassName: "NSTabBar") {
            tabBar.isHidden = true
            tabBar.frame = .zero
            tabBar.alphaValue = 0
        }

        for accessoryView in titlebarAccessoryViewControllers {
            if accessoryView.identifier == Self.tabBarIdentifier {
                accessoryView.view.isHidden = true
                accessoryView.view.frame = .zero
                accessoryView.view.alphaValue = 0
            }
        }
    }

    @available(macOS 26, *)
    private func hideTitlebarBackgroundViews(in titlebarContainer: NSView) {
        #if DEBUG
        logTitlebarHierarchy(titlebarContainer, phase: "before")
        #endif

        titlebarContainer.layer?.backgroundColor = NSColor.clear.cgColor

        for effectView in titlebarContainer.descendants(withClassName: "NSVisualEffectView") {
            effectView.isHidden = true
            effectView.alphaValue = 0
        }

        for backgroundView in titlebarContainer.descendants(withClassName: "NSTitlebarBackgroundView") {
            backgroundView.isHidden = true
            backgroundView.alphaValue = 0
            backgroundView.frame = .zero
        }

        for glassContainer in titlebarContainer.descendants(withClassName: "NSGlassContainerView") {
            glassContainer.isHidden = true
            glassContainer.alphaValue = 0
            glassContainer.frame = .zero
        }

        #if DEBUG
        logTitlebarHierarchy(titlebarContainer, phase: "after")
        #endif
    }

    #if DEBUG
    @available(macOS 26, *)
    private func logTitlebarHierarchy(_ titlebarContainer: NSView, phase: String) {
        let interestingClassFragments = [
            "Titlebar", "Toolbar", "Tab", "Glass", "VisualEffect", "Accessory", "Background", "Clip", "Decoration"
        ]

        func walk(_ view: NSView, depth: Int) {
            let className = NSStringFromClass(type(of: view))
            let shouldLog = interestingClassFragments.contains { className.contains($0) }

            if shouldLog {
                let indent = String(repeating: "  ", count: depth)
                print(
                    "[QuarryTitlebarDebug:\(phase)] \(indent)\(className) hidden=\(view.isHidden) alpha=\(view.alphaValue) frame=\(view.frame)"
                )
            }

            for subview in view.subviews {
                walk(subview, depth: depth + 1)
            }
        }

        walk(titlebarContainer, depth: 0)
    }
    #endif

    // MARK: Tab Bar

    static let tabBarIdentifier: NSUserInterfaceItemIdentifier = .init("_quarryTabBar")

    var hasTabBar: Bool {
        contentView?.firstViewFromRoot(withClassName: "NSTabBar") != nil
    }

    func isTabBar(_ childViewController: NSTitlebarAccessoryViewController) -> Bool {
        if childViewController.identifier == nil {
            if childViewController.view.contains(className: "NSTabBar") {
                return true
            }

            if childViewController.layoutAttribute == .bottom,
               childViewController.view.className == "NSView",
               childViewController.view.subviews.isEmpty {
                return true
            }

            return false
        }

        return childViewController.identifier == Self.tabBarIdentifier
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if shouldCloseConnectionForCommandW(event) {
                return
            }
        case .leftMouseDown:
            tabBarMouseTarget = nil
            if shouldPerformTitlebarDoubleClick(for: event) {
                performTitlebarDoubleClickAction()
                return
            }
            if let target = tabBarHitTarget(for: event) {
                tabBarMouseTarget = target
                target.mouseDown(with: event)
                return
            }
        case .leftMouseDragged:
            if let target = tabBarMouseTarget {
                target.mouseDragged(with: event)
                return
            }
        case .leftMouseUp:
            if let target = tabBarMouseTarget {
                tabBarMouseTarget = nil
                target.mouseUp(with: event)
                return
            }
        case .mouseMoved:
            refreshTabBarHoverStates()
        default:
            break
        }
        super.sendEvent(event)
    }

    private func shouldCloseConnectionForCommandW(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command,
              event.charactersIgnoringModifiers == "w",
              let controller = WindowController.getController(for: self) else {
            return false
        }

        return controller.closeConnectionIfDocumentTabsEmpty()
    }

    private func shouldPerformTitlebarDoubleClick(for event: NSEvent) -> Bool {
        guard event.clickCount == 2,
              let contentView
        else { return false }

        let locationInWindow = event.locationInWindow
        guard tabBarView(at: locationInWindow, in: contentView) != nil else { return false }

        return findTabBarTarget(at: locationInWindow, in: contentView) == nil
    }

    private func performTitlebarDoubleClickAction() {
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")?.lowercased()

        if action == "none" {
            return
        }

        let shouldMinimize = action == "minimize"
            || (action == nil && UserDefaults.standard.bool(forKey: "AppleMiniaturizeOnDoubleClick"))

        if shouldMinimize {
            miniaturize(nil)
        } else {
            performZoom(nil)
        }
    }

    private func tabBarHitTarget(for event: NSEvent) -> NSView? {
        guard let contentView = contentView else { return nil }

        let locationInWindow = event.locationInWindow

        let point: NSPoint
        if let themeFrame = contentView.superview {
            point = themeFrame.convert(locationInWindow, from: nil)
        } else {
            point = locationInWindow
        }

        let hitView = contentView.hitTest(point)

        if hitView == nil {
            return findTabBarTarget(at: locationInWindow, in: contentView)
        }

        guard let hitView else { return nil }

        if hitView is NSControl {
            var c: NSView? = hitView
            while let v = c {
                if v is TabBarView {
                    return hitView
                }
                c = v.superview
            }
            return nil
        }

        var current: NSView? = hitView
        var foundTabBar = false
        while let view = current {
            if view is DraggableTabNSView {
                return view
            }
            if view is TabBarView { foundTabBar = true }
            current = view.superview
        }

        if foundTabBar {
            return findTabBarTarget(at: locationInWindow, in: contentView)
        }
        return nil
    }

    private func findTabBarTarget(at locationInWindow: NSPoint, in view: NSView) -> NSView? {
        // Walk the view hierarchy to find DraggableTabNSViews and check close buttons
        func walk(_ v: NSView) -> NSView? {
            if let tabBar = v as? TabBarView,
               let target = tabBar.hitTarget(atWindowPoint: locationInWindow) {
                return target
            }

            if let draggable = v as? DraggableTabNSView {
                let localPoint = draggable.convert(locationInWindow, from: nil)
                if draggable.bounds.contains(localPoint) {
                    // Check if the close button is at this point
                    for sub in draggable.subviews {
                        for child in sub.subviews {
                            if let btn = child as? NSButton, !btn.isHidden {
                                let btnLocal = btn.convert(locationInWindow, from: nil)
                                if btn.bounds.contains(btnLocal) {
                                    return btn
                                }
                            }
                        }
                    }
                    return draggable
                }
                return nil
            }
            for sub in v.subviews {
                if let result = walk(sub) { return result }
            }
            return nil
        }

        return walk(view)
    }

    private func tabBarView(at locationInWindow: NSPoint, in view: NSView) -> TabBarView? {
        func walk(_ view: NSView) -> TabBarView? {
            if let tabBar = view as? TabBarView {
                let localPoint = tabBar.convert(locationInWindow, from: nil)
                if tabBar.bounds.contains(localPoint) {
                    return tabBar
                }
            }

            for subview in view.subviews {
                if let result = walk(subview) {
                    return result
                }
            }
            return nil
        }

        return walk(view)
    }

    private func refreshTabBarHoverStates() {
        guard let contentView else { return }

        func walk(_ view: NSView) {
            if let tabBar = view as? TabBarView {
                tabBar.refreshNavigationHoverStates()
            }

            for subview in view.subviews {
                walk(subview)
            }
        }

        walk(contentView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // tabGroupWindowsObservation/tabBarVisibleObservation are cleaned up
        // automatically when the window deallocates; we can't touch them from
        // a nonisolated deinit while they live on @MainActor self.
    }
}
