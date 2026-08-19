import AppKit

final class DashboardSingleValueItem: DashboardBaseItem {

    static let identifier = NSUserInterfaceItemIdentifier("DashboardSingleValueItem")

    override var minimumContentHeight: CGFloat { 120 }

    private var displayView: SingleValueDisplayView?
    private var currentBlockId: UUID?

    func configure(block: NotebookBlock, viewModel: SingleValueBlockViewModel, isPublished: Bool = false) {
        configureBase(block: block, isPublished: isPublished)

        let blockChanged = currentBlockId != block.id
        currentBlockId = block.id

        if blockChanged {
            displayView?.removeFromSuperview()
            displayView = nil
        }

        if let existing = displayView {
            existing.updateFallbackLabel(titleLabel.stringValue)
        } else {
            let display = SingleValueDisplayView(
                viewModel: viewModel,
                fallbackLabel: titleLabel.stringValue,
                isLabelEditable: false
            )
            display.translatesAutoresizingMaskIntoConstraints = false
            blockContainer.addSubview(display)
            displayView = display

            NSLayoutConstraint.activate([
                display.topAnchor.constraint(equalTo: blockContainer.topAnchor),
                display.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
                display.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
                display.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),
            ])
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        displayView?.removeFromSuperview()
        displayView = nil
        currentBlockId = nil
    }
}
