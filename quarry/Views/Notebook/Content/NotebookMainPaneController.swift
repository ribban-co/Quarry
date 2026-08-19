import AppKit

final class NotebookMainPaneController: NSViewController {

    private let dataController: NotebookDataController

    private var mainContentView: NSView!
    private var notebookContainer: NSView!
    private var dashboardContainer: NSView!
    private var toolbarController: NotebookToolbarController?
    private var headerController: NotebookHeaderViewController?
    private var dashboardHeaderController: NotebookHeaderViewController?
    private var emptyStateController: NotebookEmptyStateController?
    private var blocksController: NotebookBlocksController?
    private var dashboardController: DashboardGridController?
    private var emptyStateTopConstraint: NSLayoutConstraint?
    private var shownIsDashboard: Bool?


    init(dataController: NotebookDataController) {
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.masksToBounds = false
        self.view = wrapper

        mainContentView = NSView()
        mainContentView.wantsLayer = true
        mainContentView.layer?.cornerRadius = 16
        mainContentView.layer?.masksToBounds = true
        mainContentView.shadow = makeShadow()
        mainContentView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(mainContentView)

        let padding: CGFloat = 4
        NSLayoutConstraint.activate([
            mainContentView.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: padding),
            mainContentView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: padding),
            mainContentView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -padding),
            mainContentView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -padding),
        ])

        updateBackgroundColor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )

        setupHeader()
        setupDashboardHeader()
        setupEmptyState()
        setupBlocksView()
        setupDashboard()
        setupTabView()
        setupToolbar()
        setupConstraints()
        updateBlocksVisibility(animated: false)
        observeBlocksState()

    }

    func updateCornerRadius(_ radius: CGFloat, animated: Bool) {
        if animated {
            let animation = CABasicAnimation(keyPath: "cornerRadius")
            animation.fromValue = mainContentView.layer?.cornerRadius ?? 16
            animation.toValue = radius
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            mainContentView.layer?.add(animation, forKey: "cornerRadius")
        }
        mainContentView.layer?.cornerRadius = radius
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateToolbarInset()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }
        window.makeFirstResponder(window)
    }

    // MARK: - Setup

    private func setupToolbar() {
        let toolbarVC = NotebookToolbarController(dataController: dataController)
        addChild(toolbarVC)
        toolbarVC.view.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.addSubview(toolbarVC.view)
        toolbarController = toolbarVC
    }

    private func setupHeader() {
        let headerVC = NotebookHeaderViewController(dataController: dataController)
        addChild(headerVC)
        headerVC.view.translatesAutoresizingMaskIntoConstraints = false
        headerController = headerVC
    }

    private func setupDashboardHeader() {
        let headerVC = NotebookHeaderViewController(dataController: dataController)
        addChild(headerVC)
        headerVC.view.translatesAutoresizingMaskIntoConstraints = false
        dashboardHeaderController = headerVC
    }

    private func setupEmptyState() {
        let emptyStateVC = NotebookEmptyStateController(dataController: dataController)
        addChild(emptyStateVC)
        emptyStateVC.view.translatesAutoresizingMaskIntoConstraints = false
        emptyStateController = emptyStateVC
    }

    private func setupBlocksView() {
        let blocksVC = NotebookBlocksController(
            dataController: dataController,
            headerView: headerController?.view
        )
        blocksVC.onScrollOffsetChanged = { [weak self] offset in
            guard let self else { return }
            self.dataController.isScrolled = offset > 0
        }
        addChild(blocksVC)
        blocksVC.view.translatesAutoresizingMaskIntoConstraints = false
        blocksController = blocksVC
    }

    private func setupDashboard() {
        let dashVC = DashboardGridController(
            dataController: dataController,
            headerView: dashboardHeaderController?.view
        )
        dashVC.onScrollOffsetChanged = { [weak self] offset in
            guard let self else { return }
            self.dataController.isScrolled = offset > 0
        }
        addChild(dashVC)
        dashVC.view.translatesAutoresizingMaskIntoConstraints = false
        dashboardController = dashVC
    }

    private func setupTabView() {
        guard let emptyState = emptyStateController?.view,
              let blocks = blocksController?.view,
              let dashboard = dashboardController?.view else { return }

        notebookContainer = NSView()
        notebookContainer.translatesAutoresizingMaskIntoConstraints = false
        notebookContainer.addSubview(blocks)
        notebookContainer.addSubview(emptyState)
        mainContentView.addSubview(notebookContainer)

        let emptyTop = emptyState.topAnchor.constraint(equalTo: notebookContainer.topAnchor)
        emptyStateTopConstraint = emptyTop

        NSLayoutConstraint.activate([
            blocks.topAnchor.constraint(equalTo: notebookContainer.topAnchor),
            blocks.leadingAnchor.constraint(equalTo: notebookContainer.leadingAnchor),
            blocks.trailingAnchor.constraint(equalTo: notebookContainer.trailingAnchor),
            blocks.bottomAnchor.constraint(equalTo: notebookContainer.bottomAnchor),

            emptyTop,
            emptyState.leadingAnchor.constraint(equalTo: notebookContainer.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: notebookContainer.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: notebookContainer.bottomAnchor),
        ])

        dashboardContainer = NSView()
        dashboardContainer.translatesAutoresizingMaskIntoConstraints = false
        dashboardContainer.addSubview(dashboard)
        mainContentView.addSubview(dashboardContainer)

        NSLayoutConstraint.activate([
            dashboard.topAnchor.constraint(equalTo: dashboardContainer.topAnchor),
            dashboard.leadingAnchor.constraint(equalTo: dashboardContainer.leadingAnchor),
            dashboard.trailingAnchor.constraint(equalTo: dashboardContainer.trailingAnchor),
            dashboard.bottomAnchor.constraint(equalTo: dashboardContainer.bottomAnchor),
        ])
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            notebookContainer.topAnchor.constraint(equalTo: mainContentView.topAnchor),
            notebookContainer.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor),
            notebookContainer.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
            notebookContainer.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor),

            dashboardContainer.topAnchor.constraint(equalTo: mainContentView.topAnchor),
            dashboardContainer.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor),
            dashboardContainer.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
            dashboardContainer.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor),
        ])

        if let toolbar = toolbarController?.view {
            NSLayoutConstraint.activate([
                toolbar.topAnchor.constraint(equalTo: mainContentView.topAnchor),
                toolbar.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
            ])
        }
    }

    // MARK: - Block State Management

    private func updateBlocksVisibility(animated: Bool) {
        let hasBlocks = dataController.hasBlocks
        let isDashboard = dataController.viewMode == .dashboard

        emptyStateController?.view.isHidden = hasBlocks
        blocksController?.view.isHidden = !hasBlocks

        guard shownIsDashboard != isDashboard else { return }
        shownIsDashboard = isDashboard

        // Let the incoming pane rebuild while it is still invisible.
        if isDashboard {
            dashboardController?.prepareForDisplay()
        }
        syncScrollState(isDashboard: isDashboard)

        let incoming = isDashboard ? dashboardContainer! : notebookContainer!
        let outgoing = isDashboard ? notebookContainer! : dashboardContainer!

        if animated {
            NotebookTransition.crossfade(show: incoming, hide: outgoing)
        } else {
            NotebookTransition.snap(show: incoming, hide: [outgoing])
        }
    }

    /// Each pane keeps its own scroll offset, so the shared scrolled flag has to
    /// be re-read from whichever pane is coming into view.
    private func syncScrollState(isDashboard: Bool) {
        let offset = isDashboard
            ? (dashboardController?.currentScrollOffset ?? 0)
            : (blocksController?.currentScrollOffset ?? 0)
        dataController.isScrolled = offset > 0
    }

    private func observeBlocksState() {
        withObservationTracking {
            _ = self.dataController.hasBlocks
            _ = self.dataController.viewMode
            _ = self.dataController.isDashboardPublished
            _ = self.dataController.isPublishPreviewing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateBlocksVisibility(animated: true)
                self.observeBlocksState()
            }
        }
    }

    // MARK: - Toolbar Inset

    private func updateToolbarInset() {
        guard let toolbar = toolbarController?.view else { return }
        let toolbarHeight = toolbar.fittingSize.height
        blocksController?.setTopContentInset(toolbarHeight)
        dashboardController?.setTopContentInset(toolbarHeight)
        emptyStateTopConstraint?.constant = toolbarHeight
    }

    // MARK: - Appearance

    @objc private func handleAppearanceChange() {
        updateBackgroundColor()
    }

    private func updateBackgroundColor() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            mainContentView.layer?.backgroundColor = isDark
                ? NSColor.black.withAlphaComponent(0.25).cgColor
                : NSColor.white.cgColor
        }
    }

    private func makeShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
        shadow.shadowBlurRadius = 1
        shadow.shadowOffset = .zero
        return shadow
    }
}
