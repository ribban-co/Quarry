import AppKit

final class DashboardQueryItem: DashboardBaseItem {

    static let identifier = NSUserInterfaceItemIdentifier("DashboardQueryItem")

    override var minimumContentHeight: CGFloat { 200 }

    private var resultsContainer: NSView?
    private var resultsCoordinator: TableCoordinator?
    private var emptyLabel: NSTextField?
    private var currentBlockId: UUID?
    private var observationTask: Task<Void, Never>?

    func configure(block: NotebookBlock, viewModel: QueryBlockViewModel, isPublished: Bool = false) {
        configureBase(block: block, isPublished: isPublished)

        let blockChanged = currentBlockId != block.id
        currentBlockId = block.id

        if blockChanged {
            resultsCoordinator = nil
            resultsContainer?.subviews.forEach { $0.removeFromSuperview() }
        }

        updateContent(viewModel: viewModel)
        observeViewModel(viewModel)
    }

    override func setupContent() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(container)
        resultsContainer = container

        let label = NSTextField(labelWithString: "No results yet")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(label)
        emptyLabel = label

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: blockContainer.topAnchor),
            container.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),

            label.centerXAnchor.constraint(equalTo: blockContainer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: blockContainer.centerYAnchor),
        ])
    }

    private func updateContent(viewModel: QueryBlockViewModel) {
        guard let container = resultsContainer else { return }

        if let result = viewModel.queryResult, !result.columns.isEmpty {
            emptyLabel?.isHidden = true
            container.isHidden = false

            if let coordinator = resultsCoordinator {
                coordinator.updateRows(result)
            } else {
                container.subviews.forEach { $0.removeFromSuperview() }

                let coordinator = TableCoordinator(queryResult: result, showPaddingRows: false, isReadOnly: true)
                self.resultsCoordinator = coordinator

                let tableView = coordinator.setupTableView()
                tableView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(tableView)

                NSLayoutConstraint.activate([
                    tableView.topAnchor.constraint(equalTo: container.topAnchor),
                    tableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    tableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    tableView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }
        } else if let error = viewModel.queryError {
            emptyLabel?.isHidden = false
            emptyLabel?.stringValue = error
            emptyLabel?.textColor = .systemRed
            container.isHidden = true
        } else if viewModel.isExecutingQuery {
            emptyLabel?.isHidden = false
            emptyLabel?.stringValue = "Running query..."
            emptyLabel?.textColor = .secondaryLabelColor
            container.isHidden = true
        } else {
            emptyLabel?.isHidden = false
            emptyLabel?.stringValue = "No results yet"
            emptyLabel?.textColor = .secondaryLabelColor
            container.isHidden = true
        }
    }

    private func observeViewModel(_ viewModel: QueryBlockViewModel) {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let vm = viewModel
                // AsyncStream instead of a checked continuation: cancelling the
                // task ends iteration immediately, so the suspended task (and the
                // captured view model) don't outlive the reused cell.
                let changes = AsyncStream<Void> { continuation in
                    withObservationTracking {
                        _ = vm.queryResult
                        _ = vm.isExecutingQuery
                        _ = vm.queryError
                    } onChange: {
                        continuation.yield()
                        continuation.finish()
                    }
                }
                for await _ in changes { break }
                guard !Task.isCancelled else { return }
                self?.updateContent(viewModel: viewModel)
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        observationTask?.cancel()
        observationTask = nil
        resultsCoordinator = nil
        resultsContainer?.subviews.forEach { $0.removeFromSuperview() }
        emptyLabel?.stringValue = "No results yet"
        emptyLabel?.textColor = .secondaryLabelColor
        emptyLabel?.isHidden = false
        currentBlockId = nil
    }
}
