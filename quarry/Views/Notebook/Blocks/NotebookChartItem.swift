import AppKit

final class NotebookChartItem: NotebookBaseItem {

    static let identifier = NSUserInterfaceItemIdentifier("NotebookChartItem")

    override var minimumContentHeight: CGFloat { 280 }

    private weak var hostedController: ChartBlockController?
    private var needsHosting = false

    func configure(block: NotebookBlock, controller: ChartBlockController) {
        configureBase(block: block)
        if hostedController === controller, controller.view.superview === blockContainer {
            return
        }
        blockContainer.subviews.forEach { $0.removeFromSuperview() }
        hostedController = controller

        if blockContainer.bounds.width > 0, blockContainer.bounds.height > 0 {
            hostControllerView(controller)
        } else {
            needsHosting = true
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if needsHosting, let controller = hostedController,
           blockContainer.bounds.width > 0, blockContainer.bounds.height > 0 {
            needsHosting = false
            hostControllerView(controller)
        }
    }

    private func hostControllerView(_ controller: ChartBlockController) {
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: blockContainer.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),
        ])
    }

    override func prepareForReuse() {
        hostedController?.view.removeFromSuperview()
        hostedController = nil
        needsHosting = false
        super.prepareForReuse()
    }
}
