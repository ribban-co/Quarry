import AppKit

final class NotebookDataBrowserController: NSViewController {

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        self.view = NSView()
    }
}
