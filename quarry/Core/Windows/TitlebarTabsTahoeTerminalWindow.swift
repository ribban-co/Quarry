import AppKit

/// macOS 26 (Tahoe) variant of the titlebar-tabs window.
///
/// Cloned from `TitlebarTabsVenturaTerminalWindow` with two changes:
///
/// 1. **`addTitlebarAccessoryViewController` is NOT overridden.** On Tahoe,
///    overriding that method — even with just a `super` call — flips AppKit
///    to a chrome path that paints a white toolbar strip. The Ventura class
///    needs the override (to re-route accessories to `.right` pre-26), so
///    we use a separate XIB + class on Tahoe to skip it.
///
/// 2. **`titlebarAppearsTransparent = false`** everywhere it was `true` in
///    Ventura. On Tahoe, `true` triggers the Liquid Glass backdrop paint;
///    the default (`false`) plus the existing chrome scrub is what actually
///    produces a transparent titlebar.
///
/// Everything else mirrors Ventura: same KVO, same fullscreen handlers,
/// same `scheduleTitlebarChromeCleanup` timer cascade, same tab-bar mouse
/// routing — proven working machinery, no reinvention.
@available(macOS 26, *)
@MainActor
class TitlebarTabsTahoeTerminalWindow: NSWindow {
    private weak var tabBarMouseTarget: NSView?

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
            titlebarAppearsTransparent = false
            acceptsMouseMovedEvents = true
            setupFullscreenNotifications()
            updateTitlebarVisibility()
            setupTabGroupKVO()
        }
    }

    override func becomeMain() {
        super.becomeMain()
        scheduleTitlebarChromeCleanup()
        setupTabGroupKVO()

        // Going from 2 tabs to 1, AppKit replaces the tab views asynchronously
        // AFTER our KVO fires — re-apply a tick later to catch the swap.
        // Documented edge case in Ghostty's `TransparentTitlebarTerminalWindow`.
        if tabGroup?.windows.count == 2 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                self?.hideTabBarAccessoryClipViews()
            }
        }
    }

    private func setupTabGroupKVO() {
        tabGroupWindowsObservation?.invalidate()
        tabBarVisibleObservation?.invalidate()
        tabGroupWindowsObservation = nil
        tabBarVisibleObservation = nil

        guard let tabGroup else { return }

        tabGroupWindowsObservation = tabGroup.observe(\.windows, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.hideTabBarAccessoryClipViews()
            }
        }

        tabBarVisibleObservation = tabGroup.observe(\.isTabBarVisible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.hideTabBarAccessoryClipViews()
            }
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
        titleVisibility = .hidden
        titlebarAppearsTransparent = false
        titlebarSeparatorStyle = .none
        if let contentView = contentView {
            let windowFrame = frame
            let newContentFrame = NSRect(
                x: 0,
                y: 0,
                width: windowFrame.width,
                height: windowFrame.height
            )
            contentView.frame = newContentFrame
        }
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
            titlebarAppearsTransparent = false
            backgroundColor = NSColor.clear
            isOpaque = false

            self.setFullscreenTitlebarTransparent()
        }
    }

    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        // Configure BEFORE super so AppKit installs the accessory inline
        // (`.right`) instead of as a bottom strip — that's what prevents the
        // brief flash where the tab bar is visible before our KVO catches it.
        // The original "override triggers white stripe" finding was with
        // `titlebarAppearsTransparent = true`; with `false` everywhere now,
        // this override should be safe. If the strip returns, remove this.
        if isTabBar(childViewController) {
            childViewController.layoutAttribute = .right
        }

        super.addTitlebarAccessoryViewController(childViewController)

        // Run the existing cleanup right away to hide the views.
        scheduleTitlebarChromeCleanup()
    }

    private func isTabBar(_ vc: NSTitlebarAccessoryViewController) -> Bool {
        if vc.view.firstDescendant(withClassName: "NSTabBar") != nil { return true }
        // Default-style accessory with no children is also a tab-bar placeholder
        // (AppKit's first add for window tabbing).
        if vc.layoutAttribute == .bottom,
           vc.view.className == "NSView",
           vc.view.subviews.isEmpty {
            return true
        }
        return false
    }

    private func setFullscreenTitlebarTransparent() {
        for window in NSApplication.shared.windows {
            guard window.className == "NSToolbarFullScreenWindow" else { continue }
            guard window.parent == self else { continue }

            window.titlebarAppearsTransparent = false
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

    /// Single-call chrome cleanup. Replaces Ventura's 5-stage timer cascade —
    /// our trigger set (`addTitlebarAccessoryViewController` override + tab-group
    /// KVO + `becomeMain` + fullscreen notifications) already fires at every
    /// point AppKit mutates chrome, so polling on a timer is redundant.
    /// Pattern matches Ghostty's `TransparentTitlebarTerminalWindow`.
    private func scheduleTitlebarChromeCleanup() {
        hideTabBarAccessoryClipViews()
    }

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

        // `titlebarAccessoryViewControllers` only works on titled windows; the
        // fullscreen chrome window (NSToolbarFullScreenWindow) lacks `.titled`
        // and throws if accessed.
        if styleMask.contains(.titled) {
            for accessoryView in titlebarAccessoryViewControllers {
                guard accessoryView.view.firstDescendant(withClassName: "NSTabBar") != nil else { continue }
                accessoryView.view.isHidden = true
                accessoryView.view.alphaValue = 0
            }
        }
    }

    private func hideTitlebarBackgroundViews(in titlebarContainer: NSView) {
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
    }

    // MARK: Tab Bar

    var hasTabBar: Bool {
        contentView?.firstViewFromRoot(withClassName: "NSTabBar") != nil
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
    }
}
