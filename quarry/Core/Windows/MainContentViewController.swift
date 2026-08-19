import AppKit
import SwiftData
import SwiftUI

final class MainContentViewController: NSViewController {

    let tabType: TabType
    let connectionInstance: ConnectionInstance?
    let modelContainer: ModelContainer

    private let appViewModel = AppViewModel()
    private let sidebarViewModel: SidebarViewModel
    private let tabManager: TabManager

    private var splitViewController: SidebarSplitViewController?
    private var backgroundView: NSVisualEffectView!
    private var tintOverlay: NSView!
    private var backgroundPanel: BackgroundPanelView!

    private var isHome: Bool {
        switch tabType {
        case .home, .notebook: true
        case .connection: false
        }
    }

    init(tabType: TabType, connectionInstance: ConnectionInstance?, modelContainer: ModelContainer) {
        self.tabType = tabType
        self.connectionInstance = connectionInstance
        self.modelContainer = modelContainer
        self.sidebarViewModel = SidebarViewModel(windowConnectionInstance: connectionInstance)
        self.tabManager = TabManager(nativeTabType: tabType, connectionInstance: connectionInstance)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        self.view = container

        setupBackground()
        setupContent()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let window = view.window {
            WindowController.registerTabManager(tabManager, for: window)
        }
    }

    // MARK: - Background Setup

    private func setupBackground() {
        backgroundView = NSVisualEffectView()
        backgroundView.material = .sidebar
        backgroundView.blendingMode = .behindWindow
        view.addSubviewPinningEdges(backgroundView)

        tintOverlay = NSView()
        tintOverlay.wantsLayer = true
        view.addSubviewPinningEdges(tintOverlay)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTintAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )

        updateTintOverlay()
    }

    @objc private func handleTintAppearanceChange() {
        updateTintOverlay()
    }

    private func updateTintOverlay() {
        guard let layer = tintOverlay.layer else { return }

        layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode

            let baseTint = makeFullSizeLayer()
            if isDark {
                baseTint.backgroundColor = NSColor.underPageBackgroundColor.withAlphaComponent(0.80).cgColor
            } else {
                baseTint.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
                baseTint.compositingFilter = "multiplyBlendMode"
            }
            layer.addSublayer(baseTint)

            let homeDarken = makeFullSizeLayer()
            homeDarken.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer.addSublayer(homeDarken)

            if let connectionInstance, connectionInstance.connection.modelContext != nil {
                let colorLayer = makeFullSizeLayer()
                colorLayer.backgroundColor = NSColor(connectionInstance.connection.color.color)
                    .withAlphaComponent(isDark ? 0.10 : 0.08).cgColor
                colorLayer.compositingFilter = "multiplyBlendMode"
                layer.addSublayer(colorLayer)
            }
        }
    }

    private func makeFullSizeLayer() -> CALayer {
        let sublayer = CALayer()
        sublayer.frame = tintOverlay.bounds
        sublayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return sublayer
    }

    // MARK: - Background Panel

    private func setupBackgroundPanel() {
        backgroundPanel = BackgroundPanelView(isFixedSidebar: isHome)
        view.addSubviewPinningEdges(backgroundPanel, positioned: .above, relativeTo: tintOverlay)
    }

    // MARK: - Content Setup

    private func setupContent() {
        setupBackgroundPanel()

        if isHome {
            setupFixedSidebarLayout()
        } else {
            setupCollapsibleSidebarLayout()
        }
    }

    private func setupFixedSidebarLayout() {
        let sidebarController = makeSidebarController()
        let contentHost = makeContentController()

        addChild(sidebarController)
        addChild(contentHost)

        let sidebarView = sidebarController.view
        let contentView = contentHost.view

        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(sidebarView)
        view.addSubview(contentView)

        NSLayoutConstraint.activate([
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: 50),

            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupCollapsibleSidebarLayout() {
        let splitVC = SidebarSplitViewController(
            sidebarController: makeSidebarController(),
            contentController: makeContentController()
        )
        self.splitViewController = splitVC

        addChild(splitVC)
        view.addSubviewPinningEdges(splitVC.view)
    }

    // MARK: - Sidebar Controllers

    private func makeNavigationSidebar() -> NavigationSidebarViewController {
        return NavigationSidebarViewController()
    }

    private func makeSidebarController() -> NSViewController {
        let navVC = makeNavigationSidebar()
        guard !isHome else { return navVC }

        let container = SidebarContainerViewController()
        container.addChild(navVC)

        guard let connectionInstance else {
            return container
        }

        let detailsVC = ConnectionDetailsSidebarViewController(
            instance: connectionInstance,
            viewModel: sidebarViewModel,
            tabManager: tabManager,
            appViewModel: appViewModel,
            modelContainer: modelContainer
        )
        container.addChild(detailsVC)

        let navView = navVC.view
        let detailView = detailsVC.view

        navView.translatesAutoresizingMaskIntoConstraints = false
        detailView.translatesAutoresizingMaskIntoConstraints = false

        container.view.addSubview(navView)
        container.view.addSubview(detailView)

        NSLayoutConstraint.activate([
            navView.topAnchor.constraint(equalTo: container.view.topAnchor),
            navView.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            navView.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
            navView.widthAnchor.constraint(equalToConstant: 50),

            // 50pt top inset to clear the titlebar (matched the old SwiftUI
            // shell's .padding(.top, 50)).
            detailView.topAnchor.constraint(equalTo: container.view.topAnchor, constant: 50),
            detailView.leadingAnchor.constraint(equalTo: navView.trailingAnchor),
            detailView.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            detailView.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])

        return container
    }

    private func makeContentController() -> NSViewController {
        switch tabType {
        case .home:
            let homeView = HomeView()
                .padding(.top, 50)
                .environment(appViewModel)
                .environment(sidebarViewModel)
                .environment(tabManager)
                .environment(\.currentDatabaseType, connectionInstance?.connection.databaseType)
                .modelContainer(modelContainer)
            let host = NSHostingController(rootView: AnyView(homeView))
            host.safeAreaRegions = []
            return host

        case .connection:
            guard let connectionInstance else {
                let host = NSHostingController(rootView: AnyView(
                    ConnectionNotFoundView()
                        .environment(appViewModel)
                        .modelContainer(modelContainer)
                ))
                host.safeAreaRegions = []
                return host
            }

            let docVC = DocumentViewController(
                instance: connectionInstance,
                appViewModel: appViewModel,
                sidebarViewModel: sidebarViewModel,
                tabManager: tabManager,
                modelContainer: modelContainer
            )
            return docVC

        case .notebook(let notebookId):
            return NotebookViewController(
                notebookId: notebookId,
                modelContainer: modelContainer
            )
        }
    }
}

// MARK: - Sidebar Container

private final class SidebarContainerViewController: NSViewController {
    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        self.view = v
    }
}

// MARK: - Background Panel View

final class BackgroundPanelView: NSView {
    private let isFixedSidebar: Bool
    private var isSidebarVisible = true
    private let panelLayer = CALayer()
    private let shadowLayer = CALayer()

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    init(isFixedSidebar: Bool) {
        self.isFixedSidebar = isFixedSidebar
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        setupLayers()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSidebarAnimation(_:)),
            name: .sidebarAnimationWillStart,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupLayers() {
        guard let rootLayer = layer else { return }

        shadowLayer.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
        shadowLayer.shadowOpacity = 1.0
        shadowLayer.shadowRadius = 1
        shadowLayer.shadowOffset = .zero
        rootLayer.addSublayer(shadowLayer)

        panelLayer.cornerRadius = 16
        panelLayer.masksToBounds = true
        rootLayer.addSublayer(panelLayer)

        updateColors()
    }

    @objc private func handleAppearanceChange() {
        updateColors()
    }

    private func updateColors() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            panelLayer.backgroundColor = isDark
                ? NSColor.black.withAlphaComponent(0.25).cgColor
                : NSColor.controlBackgroundColor.withAlphaComponent(0.86).cgColor
            shadowLayer.backgroundColor = nil
        }
    }

    override func layout() {
        super.layout()
        updatePanelFrame(animated: false)
    }

    private var leadingPadding: CGFloat {
        if isFixedSidebar || isSidebarVisible {
            return 44
        }
        return 2
    }

    private func updatePanelFrame(animated: Bool) {
        let safeTop = if #available(macOS 26, *) {
            safeAreaInsets.top - 12
        } else {
            safeAreaInsets.top
        }
        let insets = NSEdgeInsets(top: 6 + safeTop, left: leadingPadding + 6, bottom: 6, right: 6)
        let panelRect = NSRect(
            x: insets.left,
            y: insets.bottom,
            width: bounds.width - insets.left - insets.right,
            height: bounds.height - insets.top - insets.bottom
        )

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.1)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }

        panelLayer.frame = panelRect
        shadowLayer.frame = panelRect

        let localRect = panelRect.offsetBy(dx: -panelRect.origin.x, dy: -panelRect.origin.y)
        shadowLayer.shadowPath = CGPath(
            roundedRect: localRect,
            cornerWidth: 16,
            cornerHeight: 16,
            transform: nil
        )

        CATransaction.commit()
    }

    @objc private func handleSidebarAnimation(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        let isCollapsing = notification.userInfo?["isCollapsing"] as? Bool ?? false
        isSidebarVisible = !isCollapsing
        // Instant — matches the non-animated sidebar collapse so the
        // background panel doesn't lag behind it.
        updatePanelFrame(animated: false)
    }
}
