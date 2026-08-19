import AppKit
import SwiftData

final class NotebookViewController: NSViewController {

    private let dataController: NotebookDataController

    private var splitViewController: SidebarSplitViewController?
    private var keyMonitor: Any?
    private var windowActivationObserver: Any?

    init(notebookId: UUID, modelContainer: ModelContainer) {
        self.dataController = NotebookDataController(
            notebookId: notebookId,
            modelContainer: modelContainer
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        dataController.load()
        setupContent()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        dataController.refreshConnections()
        installWindowActivationObserver()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.view.window,
                  window == event.window else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                switch event.charactersIgnoringModifiers {
                case "w":
                    window.performClose(nil)
                    return nil
                case "e":
                    guard !self.dataController.isDashboardPublished, !self.dataController.isPublishPreviewing else { return event }
                    self.dataController.isRightSidebarVisible.toggle()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        removeWindowActivationObserver()
    }

    private func setupContent() {
        let sidebarVC = NotebookDataBrowserController()

        let contentVC = NotebookContentController(dataController: dataController)

        let splitVC = SidebarSplitViewController(
            sidebarController: sidebarVC,
            contentController: contentVC,
            configuration: .init(minWidth: 240, autosaveName: "NotebookSidebarSplit", startsCollapsed: true)
        )
        self.splitViewController = splitVC

        addChild(splitVC)
        let splitView = splitVC.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func installWindowActivationObserver() {
        guard windowActivationObserver == nil,
              let window = view.window else { return }

        windowActivationObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dataController.refreshConnections()
            }
        }
    }

    private func removeWindowActivationObserver() {
        guard let windowActivationObserver else { return }
        NotificationCenter.default.removeObserver(windowActivationObserver)
        self.windowActivationObserver = nil
    }
}
