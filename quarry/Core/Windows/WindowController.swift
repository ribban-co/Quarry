import AppKit
import SwiftData
import SwiftUI

class WindowController: NSWindowController, NSToolbarDelegate, NSToolbarItemValidation, NSUserInterfaceValidations {
    private static let windowFrameAutosaveName: NSWindow.FrameAutosaveName = "QuarryMainWindow"
    private static let legacyWindowFrameDefaultsKey = "PlukWindowFrame"
    private static let minimumWindowSize = NSSize(width: 800, height: 600)
    private static let defaultWindowSize = NSSize(width: 1440, height: 900)
    /// Share of the screen a first-run window takes, so the default scales
    /// with the display instead of opening small on large ones.
    private static let defaultWindowScreenFraction: CGFloat = 0.85
    private static var isSynchronizingTabbedWindowFrames = false

    override var windowNibName: NSNib.Name? {
        if #available(macOS 26, *) {
            return "TerminalTabsTitlebarTahoe"
        }
        return "TerminalTabsTitlebarVentura"
    }
    
    // MARK: - Static Registry
    
    private static var windowControllers: [NSWindow: WindowController] = [:]
    private static var windowTabManagers: [NSWindow: TabManager] = [:]
    
    private static func register(_ controller: WindowController, for window: NSWindow) {
        windowControllers[window] = controller
    }
    
    static func registerTabManager(_ tabManager: TabManager, for window: NSWindow) {
        guard windowTabManagers[window] == nil else { return }
        windowTabManagers[window] = tabManager
    }
    
    private static func unregister(_ window: NSWindow) {
        windowControllers.removeValue(forKey: window)
        windowTabManagers.removeValue(forKey: window)
    }
    
    static func getController(for window: NSWindow) -> WindowController? {
        windowControllers[window]
    }

    /// Whether any main Quarry window is on screen. Auxiliary windows (settings,
    /// logs, about) are not registered here, so they don't count.
    static var hasVisibleManagedWindow: Bool {
        windowControllers.keys.contains { $0.isVisible }
    }

    private static func getTabManager(for window: NSWindow) -> TabManager? {
        windowTabManagers[window]
    }

    @MainActor
    @discardableResult
    static func activateWindow(at index: Int) -> Bool {
        let windows = orderedManagedWindows()
        guard windows.indices.contains(index) else { return false }
        focus(windows[index])
        return true
    }

    @MainActor
    private static func orderedManagedWindows() -> [NSWindow] {
        let managedWindows = Array(windowControllers.keys)
        let orderedWindows = NSApp.orderedWindows.filter { windowControllers[$0] != nil }
        let remainingWindows = managedWindows
            .filter { candidate in
                !orderedWindows.contains(where: { $0 == candidate })
            }
            .sorted { lhs, rhs in
                if lhs.windowNumber == rhs.windowNumber {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.windowNumber < rhs.windowNumber
            }

        return orderedWindows + remainingWindows
    }
    @MainActor
    private static func focus(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    static func getCurrentActiveTabType() -> TabType? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return getController(for: keyWindow)?.tabType
    }
    
    // MARK: - Static Methods

    @discardableResult
    static func newTab(
        tabType: TabType,
        connectionInstance: ConnectionInstance? = nil
    ) -> WindowController {
        let parentWindow = NSApp.windows.first(where: { $0.isVisible && $0.isMainWindow })
            ?? NSApp.windows.first(where: { $0.isVisible })

        guard let parentWindow else {
            return newWindow(tabType: tabType, connectionInstance: connectionInstance)
        }

        let controller = WindowController(tabType: tabType, connectionInstance: connectionInstance)

        if let newWindow = controller.window {
            newWindow.tabbingMode = .preferred
            parentWindow.addTabbedWindow(newWindow, ordered: .above)
            newWindow.setFrame(parentWindow.frame, display: false)
            synchronizeTabbedWindowFrames(from: newWindow)
            controller.persistWindowFrame(newWindow)
            newWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        return controller
    }

    @discardableResult
    static func newWindow(
        tabType: TabType,
        connectionInstance: ConnectionInstance? = nil
    ) -> WindowController {
        let controller = WindowController(tabType: tabType, connectionInstance: connectionInstance)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    @discardableResult
    static func showHome() -> WindowController {
        for window in NSApp.windows {
            guard let windowController = getController(for: window),
                  case .home = windowController.tabType else { continue }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return windowController
        }

        return newWindow(tabType: .home)
    }

    static func switchToTab(_ tabType: TabType) {
        for window in NSApp.windows {
            guard let windowController = getController(for: window) else { continue }

            let matches = switch (windowController.tabType, tabType) {
            case (.home, .home):
                true
            case (.connection(let existingId), .connection(let targetId)):
                existingId == targetId
            case (.notebook(let existingId), .notebook(let targetId)):
                existingId == targetId
            default:
                false
            }

            if matches {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        switch tabType {
        case .home:
            _ = showHome()
        case .connection(let instanceId):
            if let connectionInstance = ConnectionService.shared.getInstance(instanceId) {
                newTab(tabType: tabType, connectionInstance: connectionInstance)
            }
        case .notebook:
            newTab(tabType: tabType)
        }
    }
    
    @MainActor
    static func closeNotebookWindow(id: UUID) {
        for window in NSApp.windows {
            guard let controller = getController(for: window),
                  case .notebook(let windowNotebookId) = controller.tabType,
                  windowNotebookId == id else { continue }
            window.close()
            return
        }
    }

    // MARK: - Instance Properties

    let tabType: TabType
    private weak var connectionInstance: ConnectionInstance?
    var shouldTeardownConnectionOnClose = true
    private var environmentToolbarItem: NSToolbarItem?
    private var isRefreshingDeployments = false
    private var switchDatabaseShortcutMonitor: Any?

    // MARK: - Initialization

    init(tabType: TabType, connectionInstance: ConnectionInstance? = nil) {
        self.tabType = tabType
        self.connectionInstance = connectionInstance

        super.init(window: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        configureWindow()
    }

    convenience init(adopting window: NSWindow, tabType: TabType = .home, connectionInstance: ConnectionInstance? = nil) {
        self.init(tabType: tabType, connectionInstance: connectionInstance)
        self.window = window
        configureWindow()
    }

    private func configureWindow() {
        guard let window = self.window else { return }

        // The xib wires the delegate outlet at nib load; detach it so the
        // resizes below don't persist an interim frame over the saved one.
        window.delegate = nil

        window.tabbingIdentifier = "_QuarryWindow"
        window.title = windowTitle
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none

        if let windowMenu = NSApp.windowsMenu {
            windowMenu.items.first(where: { $0.action == #selector(NSWindow.toggleTabBar(_:)) })?.isHidden = true
        }

        if #available(macOS 26, *) {
            window.toolbarStyle = .unified
        } else {
            window.toolbarStyle = .unifiedCompact
        }
        window.isMovableByWindowBackground = true
        // AppKit state restoration rebuilds window content outside
        // configureWindow, so restored SwiftUI trees miss their injected
        // environment objects. Frame persistence is handled manually below.
        window.isRestorable = false
        window.minSize = Self.minimumWindowSize

        let mainVC = MainContentViewController(
            tabType: tabType,
            connectionInstance: connectionInstance,
            modelContainer: (NSApp.delegate as! AppDelegate).sharedModelContainer
        )
        window.contentViewController = mainVC

        let toolbar = NSToolbar(identifier: "_QuarryToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window.toolbar = toolbar
        toolbar.validateVisibleItems()

        // Assigning contentViewController resizes the window to the view's
        // fitting size, so the frame must be restored after it — and the
        // delegate attached after that, so setup resizes are never persisted.
        restoreWindowFrame(window)
        window.delegate = self

        WindowController.register(self, for: window)
        setupConnectionObservation()
        setupSwitchDatabaseShortcutMonitor(for: window)

        hideTabBarViews(in: window)
        Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, let window else { return }
            self.hideTabBarViews(in: window)
        }
    }

    private func restoreWindowFrame(_ window: NSWindow) {
        let restoredFrame = window.setFrameUsingName(Self.windowFrameAutosaveName)

        if restoredFrame {
            let normalizedFrame = normalizedWindowFrame(window.frame)
            if normalizedFrame != window.frame {
                window.setFrame(normalizedFrame, display: true)
            }
            persistWindowFrame(window)
            return
        }

        if let legacyFrame = legacyWindowFrame() {
            window.setFrame(normalizedWindowFrame(legacyFrame), display: true)
            UserDefaults.standard.removeObject(forKey: Self.legacyWindowFrameDefaultsKey)
            persistWindowFrame(window)
            return
        }

        window.setFrame(defaultWindowFrame(), display: true)
        persistWindowFrame(window)
    }

    private func legacyWindowFrame() -> NSRect? {
        guard let savedFrameString = UserDefaults.standard.string(forKey: Self.legacyWindowFrameDefaultsKey) else {
            return nil
        }

        let frame = NSRectFromString(savedFrameString)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    private func normalizedWindowFrame(_ frame: NSRect) -> NSRect {
        let targetScreen = bestScreen(for: frame) ?? NSScreen.main
        guard let visibleFrame = targetScreen?.visibleFrame else {
            return NSRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: max(frame.width, Self.minimumWindowSize.width),
                height: max(frame.height, Self.minimumWindowSize.height)
            )
        }

        let width = min(max(frame.width, Self.minimumWindowSize.width), visibleFrame.width)
        let height = min(max(frame.height, Self.minimumWindowSize.height), visibleFrame.height)
        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - height

        return NSRect(
            x: min(max(frame.origin.x, minX), maxX),
            y: min(max(frame.origin.y, minY), maxY),
            width: width,
            height: height
        )
    }

    private func defaultWindowFrame() -> NSRect {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSRect(origin: .zero, size: Self.defaultWindowSize)
        }

        let fraction = Self.defaultWindowScreenFraction
        let width = min(
            max(Self.defaultWindowSize.width, visibleFrame.width * fraction),
            visibleFrame.width
        )
        let height = min(
            max(Self.defaultWindowSize.height, visibleFrame.height * fraction),
            visibleFrame.height
        )

        return NSRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2),
            width: width,
            height: height
        )
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        let screen = NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
        guard let screen, screen.visibleFrame.intersection(frame).area > 0 else { return nil }
        return screen
    }

    private func persistWindowFrame(_ window: NSWindow) {
        window.saveFrame(usingName: Self.windowFrameAutosaveName)
    }

    private static func synchronizeTabbedWindowFrames(from sourceWindow: NSWindow) {
        guard !isSynchronizingTabbedWindowFrames,
              let tabbedWindows = sourceWindow.tabbedWindows,
              tabbedWindows.count > 1 else {
            return
        }

        isSynchronizingTabbedWindowFrames = true
        defer { isSynchronizingTabbedWindowFrames = false }

        for tabbedWindow in tabbedWindows
        where tabbedWindow !== sourceWindow
            && tabbedWindow.frame != sourceWindow.frame {
            tabbedWindow.setFrame(sourceWindow.frame, display: false)
        }
    }

    // MARK: - Toolbar

    private var toolbarIdentifiers: [NSToolbarItem.Identifier] {
        switch tabType {
        case .connection:
            if connectionInstance?.connection.databaseType == .convex {
                return [.collapseSidebarItem, .environmentMenuItem]
            }
            return [.collapseSidebarItem]
        case .notebook:
            return []
        case .home:
            return []
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarIdentifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarIdentifiers
    }

    private var toolbarItemTopPadding: CGFloat {
        if #available(macOS 26, *) { 0 } else { 8 }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .collapseSidebarItem:
            return makeSidebarToggleItem(identifier: itemIdentifier)
        case .environmentMenuItem:
            return makeEnvironmentItem(identifier: itemIdentifier)
        default:
            return nil
        }
    }

    private func makeSidebarToggleItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)

        let buttonView = SidebarToggleButtonView {
            self.toggleSidebarNatively(nil)
        }

        let hostingView = NSHostingView(rootView: sidebarToggleContent(buttonView))
        hostingView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        item.view = hostingView
        item.label = "Sidebar"
        item.paletteLabel = "Sidebar"
        item.toolTip = nil

        return item
    }

    private func sidebarToggleContent(_ buttonView: SidebarToggleButtonView) -> some View {
        buttonView.padding(.top, toolbarItemTopPadding)
    }

    private func makeEnvironmentItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard let instance = connectionInstance else { return nil }

        let item = NSToolbarItem(itemIdentifier: identifier)

        let environmentMenu = createEnvironmentMenu(for: instance)
            .padding(.top, toolbarItemTopPadding)
        let hostingView = NSHostingView(rootView: environmentMenu)
        hostingView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        item.view = hostingView
        item.label = "Environment"
        item.paletteLabel = "Environment"
        item.toolTip = "Switch Environment"

        if #available(macOS 26.0, *) {
            item.isBordered = false
        }

        environmentToolbarItem = item
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        true
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        true
    }

    // MARK: - Navigation Shortcuts

    private func setupSwitchDatabaseShortcutMonitor(for window: NSWindow) {
        if let switchDatabaseShortcutMonitor {
            NSEvent.removeMonitor(switchDatabaseShortcutMonitor)
        }

        switchDatabaseShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self,
                  let window,
                  event.window === window,
                  window.isKeyWindow,
                  self.handleSwitchDatabaseShortcut(event)
            else {
                return event
            }

            return nil
        }
    }

    private func handleSwitchDatabaseShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.charactersIgnoringModifiers?.lowercased() == "k" else {
            return false
        }

        if flags == [.command, .shift] {
            WindowController.switchToTab(.home)
            return true
        }

        guard flags == .command,
              case .connection = tabType,
              connectionInstance?.selectedTab?.type != .sqlEditor,
              !isTextInputFirstResponder,
              let window
        else {
            return false
        }

        NotificationCenter.default.post(name: .switchDatabaseShortcut, object: window)
        return true
    }

    private var isTextInputFirstResponder: Bool {
        guard let firstResponder = window?.firstResponder else { return false }
        if firstResponder is NSTextView || firstResponder is NSTextField {
            return true
        }

        let className = NSStringFromClass(type(of: firstResponder))
        return className.contains("TextView") || className.contains("TextField")
    }

    @discardableResult
    func closeConnectionIfDocumentTabsEmpty() -> Bool {
        guard case .connection(let instanceId) = tabType,
              connectionInstance?.tabs.isEmpty == true else {
            return false
        }

        Task { @MainActor in
            await ConnectionService.shared.removeConnectionInstance(instanceId)
        }
        return true
    }

    // MARK: - Native Sidebar Toggle

    @objc func toggleSidebarNatively(_ sender: Any?) {
        guard let window = self.window else { return }
        if case .notebook = tabType { return }

        NotificationCenter.default.post(name: .toggleLeftSidebar, object: window)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            if let controller = self?.findSidebarController(in: window.contentView) {
                self?.environmentToolbarItem?.view?.isHidden = controller.isCollapsed
            }
        }
    }

    private func findSidebarController(in view: NSView?) -> SidebarSplitViewController? {
        guard let view else { return nil }

        if let controller = view.nextResponder as? SidebarSplitViewController {
            return controller
        }

        for subview in view.subviews {
            if let found = findSidebarController(in: subview) {
                return found
            }
        }

        return nil
    }
    
    private var windowTitle: String {
        switch tabType {
        case .home:
            "Home"
        case .connection:
            connectionInstance?.connection.name ?? "Connection"
        case .notebook(let notebookId):
            notebookTitle(for: notebookId)
        }
    }

    private func notebookTitle(for notebookId: UUID) -> String {
        let container = (NSApp.delegate as? AppDelegate)?.sharedModelContainer
        if let context = container?.mainContext,
           let notebook = try? context.fetch(
               FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == notebookId })
           ).first {
            return notebook.title
        }
        return "Notebook"
    }

    // MARK: - Connection Observation

    private func setupConnectionObservation() {
        guard let instance = connectionInstance else { return }

        for name in [Notification.Name.databasesUpdated, .connectedDatabaseChanged] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleEnvironmentChange(_:)),
                name: name,
                object: instance
            )
        }
    }

    @objc private func handleEnvironmentChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.refreshEnvironmentMenu()
        }
    }

    func refreshEnvironmentMenu() {
        guard let instance = connectionInstance,
              let item = environmentToolbarItem else { return }

        let updatedMenu = createEnvironmentMenu(for: instance)
            .padding(.top, toolbarItemTopPadding)
        let newHostingView = NSHostingView(rootView: updatedMenu)
        newHostingView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        newHostingView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        item.view = newHostingView
    }

    // MARK: - Environment Menu

    private func createEnvironmentMenu(for instance: ConnectionInstance) -> some View {
        let menuView = Menu {
            Section {
                if !instance.databases.isEmpty {
                    ForEach(instance.databases.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.name) { database in
                        Toggle(isOn: Binding<Bool>(
                            get: { instance.connectedDatabase?.name == database.name },
                            set: { isOn in
                                if isOn {
                                    self.openEnvironmentInNewTab(instance: instance, database: database)
                                }
                            }
                        )) {
                            Text(database.name)
                        }
                    }
                } else {
                    Text("No environments available")
                }
            } header: {
                Text("Switch Environment")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Section {
                Button {
                    Task {
                        await self.refreshDeployments(for: instance)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            EnvironmentMenuLabel(title: currentEnvironmentTitle(instance), isLoading: isRefreshingDeployments)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)

        return menuView
    }

    private func refreshDeployments(for instance: ConnectionInstance) async {
        await MainActor.run {
            isRefreshingDeployments = true
            refreshEnvironmentMenu()
        }

        do {
            let fresh = try await instance.databaseService.refreshConvexDeployments()
            await MainActor.run {
                instance.databases = fresh
                isRefreshingDeployments = false
                refreshEnvironmentMenu()

                Task { @MainActor in
                    if let updatedToken = await instance.databaseService.buildUpdatedConvexEmbeddedToken() {
                        instance.connection.password = updatedToken
                    }
                }
            }
        } catch {
            debugLog("Failed to refresh deployments: \(error)")
            await MainActor.run {
                isRefreshingDeployments = false
                refreshEnvironmentMenu()
            }
        }
    }

    private func currentEnvironmentTitle(_ instance: ConnectionInstance) -> String {
        instance.connectedDatabase?.name ?? "Select Environment"
    }

    private func openEnvironmentInNewTab(instance: ConnectionInstance, database: any DatabaseWrapper) {
        Task {
            guard let instanceId = await ConnectionService.shared.openEnvironmentInNewTab(from: instance, databaseName: database.name) else { return }

            let tabTitle = "\(instance.connection.name) – \(database.name)"
            let appliedImmediately = await MainActor.run {
                WindowController.switchToTab(.connection(instanceId))
                return ConnectionService.shared.updateTabTitle(for: instanceId, title: tabTitle)
            }

            guard !appliedImmediately else { return }

            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                _ = ConnectionService.shared.updateTabTitle(for: instanceId, title: tabTitle)
            }
        }
    }

    // MARK: - Full Screen

    @objc internal func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        hideTabBarViews(in: window)
    }

    @objc internal func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        hideTabBarViews(in: window)
    }

    // MARK: - Tab Bar Hiding

    private static let tabBarClassNamePatterns = [
        "TabBar", "NSTabViewController", "_NSTabBarView",
        "NSTitlebarTabView", "NSToolbarTabView",
        "NSTitlebarBackgroundView", "NSGlassContainerView",
    ]

    private func hideTabBarViews(in window: NSWindow) {
        if let titlebarView = window.standardWindowButton(.closeButton)?.superview?.superview {
            hideTabBarInView(titlebarView)
        }

        if let contentView = window.contentView {
            hideTabBarInView(contentView)
        }

        for view in window.contentView?.superview?.subviews ?? [] {
            if NSStringFromClass(type(of: view)).contains("Tab") {
                hideTabBarInView(view)
            }
        }
    }

    private func hideTabBarInView(_ view: NSView) {
        for subview in view.subviews {
            let className = NSStringFromClass(type(of: subview))

            let isTabBar = Self.tabBarClassNamePatterns.contains(where: { className.contains($0) })
                || className.hasSuffix("TabBarView")
            let isOurs = subview is TabBarView
            guard !isOurs else { continue }

            if isTabBar {
                if let superview = subview.superview {
                    let related = superview.constraints.filter {
                        ($0.firstItem as? NSView) == subview || ($0.secondItem as? NSView) == subview
                    }
                    superview.removeConstraints(related)
                }
                subview.removeConstraints(subview.constraints)
                subview.frame = .zero
                subview.isHidden = true
            }

            hideTabBarInView(subview)
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

// MARK: - NSWindowDelegate

extension WindowController: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, Self.minimumWindowSize.width),
            height: max(frameSize.height, Self.minimumWindowSize.height)
        )
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Self.synchronizeTabbedWindowFrames(from: window)
        persistWindowFrame(window)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Self.synchronizeTabbedWindowFrames(from: window)
        persistWindowFrame(window)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        if let window {
            hideTabBarViews(in: window)
        }
        NotificationCenter.default.post(name: .tabDidChange, object: nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        let closingConnectionInstance = connectionInstance

        if case .connection = tabType,
           let tabManager = WindowController.getTabManager(for: window) {
            let tabsToClose = tabManager.tabs.filter { $0.type != .home }
            for tab in tabsToClose {
                tabManager.closeTab(tab.id)
            }
        }

        if case .connection(let instanceId) = tabType,
           shouldTeardownConnectionOnClose {
            Task { @MainActor in
                await ConnectionService.shared.removeConnectionInstance(instanceId, closeWindow: false)
            }
        }

        if case .notebook(let notebookId) = tabType {
            let hasOtherNotebookWindow = NSApp.windows.contains { candidate in
                guard candidate != window,
                      let controller = WindowController.getController(for: candidate),
                      case .notebook(let candidateNotebookId) = controller.tabType else { return false }
                return candidateNotebookId == notebookId
            }

            if !hasOtherNotebookWindow {
                SidebarItemRegistry.shared.removeNotebook(notebookId)
            }
        }

        WindowController.unregister(window)

        window.contentView?.subviews
            .first { $0 is TabBarView }?
            .removeFromSuperview()

        NotificationCenter.default.removeObserver(self, name: NSWindow.didEnterFullScreenNotification, object: window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: window)

        if let instance = closingConnectionInstance {
            NotificationCenter.default.removeObserver(self, name: .databasesUpdated, object: instance)
            NotificationCenter.default.removeObserver(self, name: .connectedDatabaseChanged, object: instance)
        }

        if let switchDatabaseShortcutMonitor {
            NSEvent.removeMonitor(switchDatabaseShortcutMonitor)
            self.switchDatabaseShortcutMonitor = nil
        }

        activateNextTab(closing: window)
        window.delegate = nil
        window.toolbar = nil
        environmentToolbarItem = nil
        window.contentViewController = nil
        self.window = nil
    }

    private func activateNextTab(closing window: NSWindow) {
        let tabbedWindows = window.tabbedWindows ?? [window]
        guard tabbedWindows.count > 1,
              let nextWindow = tabbedWindows.first(where: { $0 != window }) else { return }
        let closingFrame = window.frame

        Task { @MainActor in
            nextWindow.setFrame(closingFrame, display: false)
            Self.synchronizeTabbedWindowFrames(from: nextWindow)
            Self.getController(for: nextWindow)?.persistWindowFrame(nextWindow)
            nextWindow.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Sidebar Toggle Button

private struct SidebarToggleButtonView: View {
    var action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var buttonSize: CGFloat {
        if #available(macOS 26, *) { 32 } else { 28 }
    }

    private var symbolSize: CGFloat {
        if #available(macOS 26, *) { 17 } else { 16 }
    }

    private var cornerRadius: CGFloat {
        12
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: symbolSize))
                .foregroundStyle(.primary)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering ? hoverColor : .clear)
                )
        }
        .buttonStyle(.borderless)
        .customHelp("Toggle Sidebar", shortcut: .init(modifiers: [.command], key: "["))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var hoverColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color(nsColor: .controlColor).opacity(0.8)
    }
}

// MARK: - Connection Not Found View

struct ConnectionNotFoundView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Connection Not Found")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This connection tab could not be loaded.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
