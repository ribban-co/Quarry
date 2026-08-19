import AppKit

final class NotebookInnerSplitController: NSSplitViewController {

    private var contentItem: NSSplitViewItem!
    private var inspectorItem: NSSplitViewItem!
    private var isProgrammaticCollapse = false
    private var isAnimating = false
    private var lastExpandedWidth: CGFloat = 300

    var onCollapseStateChanged: ((Bool) -> Void)?

    var isInspectorCollapsed: Bool { inspectorItem.isCollapsed }

    private let dataController: NotebookDataController

    private var minInspectorWidth: CGFloat { inspectorItem.minimumThickness > 0 ? inspectorItem.minimumThickness : 350 }
    private var maxInspectorWidth: CGFloat {
        if inspectorItem.maximumThickness <= 0 || inspectorItem.maximumThickness == .greatestFiniteMagnitude {
            return .greatestFiniteMagnitude
        }
        return inspectorItem.maximumThickness
    }

    init(contentController: NSViewController, inspectorController: NSViewController, dataController: NotebookDataController) {
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)

        contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.holdingPriority = .defaultLow
        contentItem.minimumThickness = 300

        inspectorItem = NSSplitViewItem(viewController: inspectorController)
        inspectorItem.canCollapse = true
        inspectorItem.isCollapsed = true
        inspectorItem.minimumThickness = 350
        inspectorItem.maximumThickness = 600
        inspectorItem.holdingPriority = .defaultLow + 1

        splitViewItems = [contentItem, inspectorItem]
        lastExpandedWidth = inspectorItem.minimumThickness
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSplitViewDidResize),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitView
        )

        observeRightSidebar()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Toggle

    func toggle() {
        if inspectorItem.isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    private func collapse() {
        guard !isAnimating, !inspectorItem.isCollapsed else { return }
        lastExpandedWidth = clampInspectorWidth(inspectorItem.viewController.view.frame.width)
        animateInspector(collapsed: true)
    }

    private func expand() {
        guard !isAnimating, inspectorItem.isCollapsed else { return }
        animateInspector(collapsed: false)
    }

    private func animateInspector(collapsed: Bool) {
        isAnimating = true
        isProgrammaticCollapse = collapsed

        let inspectorView = inspectorItem.viewController.view

        if let hoverSplitView = splitView as? HoverDividerSplitView {
            hoverSplitView.isSidebarCollapsed = collapsed
            hoverSplitView.needsDisplay = true
        }

        if !collapsed {
            inspectorView.alphaValue = 0
        }

        onCollapseStateChanged?(collapsed)

        NotificationCenter.default.post(name: .notebookChartFreeze, object: view.window)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotebookTransition.duration
            context.timingFunction = NotebookTransition.timing
            context.allowsImplicitAnimation = true
            inspectorView.animator().alphaValue = collapsed ? 0 : 1
            inspectorItem.animator().isCollapsed = collapsed
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAnimating = false
                self.isProgrammaticCollapse = false

                if !collapsed {
                    self.setInspectorWidth(self.lastExpandedWidth)
                    inspectorView.alphaValue = 1
                }

                if let hoverSplitView = self.splitView as? HoverDividerSplitView {
                    hoverSplitView.isSidebarCollapsed = collapsed
                }

                NotificationCenter.default.post(name: .notebookChartUnfreeze, object: self.view.window)
            }
        }
    }

    // MARK: - Observation

    private func observeRightSidebar() {
        withObservationTracking {
            _ = self.dataController.isRightSidebarVisible
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncCollapseState()
                self.observeRightSidebar()
            }
        }
    }

    private func syncCollapseState() {
        if dataController.isRightSidebarVisible {
            expand()
        } else {
            collapse()
        }
    }

    // MARK: - NSSplitViewDelegate

    @objc private func handleSplitViewDidResize(_ notification: Notification) {
        guard !isAnimating else { return }

        if !inspectorItem.isCollapsed {
            lastExpandedWidth = clampInspectorWidth(inspectorItem.viewController.view.frame.width)
        }

        if let hoverSplitView = splitView as? HoverDividerSplitView {
            hoverSplitView.isSidebarCollapsed = inspectorItem.isCollapsed
        }
    }

    override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return isProgrammaticCollapse
    }

    private func clampInspectorWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minInspectorWidth), maxInspectorWidth)
    }

    private func setInspectorWidth(_ width: CGFloat) {
        guard splitView.arrangedSubviews.count >= 2 else { return }
        let clampedWidth = clampInspectorWidth(width)
        let targetPosition = splitView.bounds.width - splitView.dividerThickness - clampedWidth
        splitView.setPosition(targetPosition, ofDividerAt: 0)
    }
}
