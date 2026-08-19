import AppKit

final class NotebookQueryItem: NotebookBaseItem {

    static let identifier = NSUserInterfaceItemIdentifier("NotebookQueryItem")

    override var minimumContentHeight: CGFloat { 200 }

    private weak var hostedController: QueryBlockController?

    func configure(block: NotebookBlock, controller: QueryBlockController) {
        configureBase(block: block)
        if hostedController === controller, controller.view.superview === blockContainer {
            return
        }
        blockContainer.subviews.forEach { $0.removeFromSuperview() }
        hostedController = controller

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
        super.prepareForReuse()
    }
}
