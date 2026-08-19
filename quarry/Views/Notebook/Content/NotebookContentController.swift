import AppKit

final class NotebookContentController: NSViewController {

    private let dataController: NotebookDataController

    private var contentContainer: NSView!
    private var innerSplitController: NotebookInnerSplitController?
    private var mainPaneController: NotebookMainPaneController?

    private var containerTopConstraint: NSLayoutConstraint?
    private var containerLeadingConstraint: NSLayoutConstraint?
    private var containerTrailingConstraint: NSLayoutConstraint?
    private var containerBottomConstraint: NSLayoutConstraint?

    private var topInset: CGFloat {
        if #available(macOS 26, *) { 52 } else { 50 }
    }

    init(dataController: NotebookDataController) {
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        setupContentContainer()
        setupInnerSplit()
        setupConstraints()
    }

    // MARK: - Layout

    private func setupContentContainer() {
        contentContainer = NSView()
        contentContainer.wantsLayer = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
    }

    private func setupInnerSplit() {
        let mainPane = NotebookMainPaneController(dataController: dataController)
        let agentPane = NotebookAgentController(dataController: dataController)

        let innerSplit = NotebookInnerSplitController(
            contentController: mainPane,
            inspectorController: agentPane,
            dataController: dataController
        )

        innerSplit.onCollapseStateChanged = { [weak self] isCollapsing in
            guard let self else { return }
            updateLayoutForSidebarState(isRightSidebarOpen: !isCollapsing)
        }

        self.innerSplitController = innerSplit
        self.mainPaneController = mainPane

        addChild(innerSplit)
        let splitView = innerSplit.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func setupConstraints() {
        let top = contentContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset - 10)
        let leading = contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -4)
        let trailing = contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2)
        let bottom = contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2)
        containerTopConstraint = top
        containerLeadingConstraint = leading
        containerTrailingConstraint = trailing
        containerBottomConstraint = bottom

        NSLayoutConstraint.activate([top, leading, trailing, bottom])
    }

    // MARK: - Layout Updates

    private func updateLayoutForSidebarState(isRightSidebarOpen: Bool) {
        let radius: CGFloat = isRightSidebarOpen ? 10 : 16
        mainPaneController?.updateCornerRadius(radius, animated: true)
        animateContainerInsets(anySidebarOpen: isRightSidebarOpen)
    }

    private func animateContainerInsets(anySidebarOpen: Bool) {
        let topValue: CGFloat = anySidebarOpen ? topInset - 4 : topInset - 10
        let leadingValue: CGFloat = anySidebarOpen ? 2 : -4
        let trailingValue: CGFloat = anySidebarOpen ? -8 : -2
        let bottomValue: CGFloat = anySidebarOpen ? -8 : -2

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.containerTopConstraint?.animator().constant = topValue
            self.containerLeadingConstraint?.animator().constant = leadingValue
            self.containerTrailingConstraint?.animator().constant = trailingValue
            self.containerBottomConstraint?.animator().constant = bottomValue
            self.view.layoutSubtreeIfNeeded()
        }
    }
}
