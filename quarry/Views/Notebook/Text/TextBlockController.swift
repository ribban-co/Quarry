import AppKit

@MainActor
final class TextBlockController: NSViewController {

    let block: NotebookBlock
    private let dataController: NotebookDataController
    private var saveDebounceTask: Task<Void, Never>?

    init(block: NotebookBlock, dataController: NotebookDataController) {
        self.block = block
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        saveDebounceTask?.cancel()
    }

    override func loadView() {
        view = NSView()
    }

    func setNeedsTextLayoutRefresh() {}

    func handleTextChange(_ newText: String) {
        block.textContent = newText
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.dataController.updateBlock(self.block)
        }
    }
}
