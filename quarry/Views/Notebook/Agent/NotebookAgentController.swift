import AppKit

final class NotebookAgentController: NSViewController, NSPopoverDelegate {

    private let dataController: NotebookDataController
    private let chatController: AgentChatController

    private var headerView: AgentHeaderView!
    private var emptyStateView: AgentEmptyStateView!
    private var messageListController: AgentMessageListController!
    private var chatInputView: AgentChatInputView!
    private var windowCloseObserver: NSObjectProtocol?

    init(dataController: NotebookDataController) {
        self.dataController = dataController
        self.chatController = AgentChatController(
            scopeId: dataController.notebookId,
            modelContainer: dataController.modelContainer,
            notebookDataController: dataController
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

        setupHeader()
        setupMessageList()
        setupEmptyState()
        setupChatInput()
        setupConstraints()
        wireCallbacks()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        chatController.load()
        syncEmptyStateVisibility()
        syncHeaderTitle()
        syncHeaderActions()
        syncAvailableConnections()
        observeEmptyState()
        observeCurrentChat()
        observePendingMessage()
        observeConnections()
        handlePendingMessage()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        chatInputView.focusInput()
        installWindowCloseObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            if let windowCloseObserver {
                NotificationCenter.default.removeObserver(windowCloseObserver)
            }
        }
    }

    // MARK: - Teardown

    /// Each notebook lives in its own window, so window close means the
    /// notebook is going away — unlike `viewDidDisappear`, which also fires
    /// on mere tab switches. Kept installed across disappearance since a
    /// background tab's window can be closed while another tab is selected.
    private func installWindowCloseObserver() {
        guard windowCloseObserver == nil, let window = view.window else { return }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Runs synchronously during close — a Task hop could land after
            // the controller is torn down.
            MainActor.assumeIsolated {
                self?.prepareForRemoval()
            }
        }
    }

    /// Stops any running agent loop and disconnects the engine's database
    /// session so a closed notebook can't keep streaming, running queries,
    /// or holding connections. Mirrors `TableChatSidebarViewController.prepareForRemoval()`.
    func prepareForRemoval() {
        chatController.cancelStreaming()
        let engine = chatController.engine
        Task { await engine.cleanup() }
    }

    // MARK: - Setup

    private func setupHeader() {
        headerView = AgentHeaderView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
    }

    private func setupMessageList() {
        messageListController = AgentMessageListController(chatController: chatController)
        addChild(messageListController)
        messageListController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageListController.view)
    }

    private func setupEmptyState() {
        emptyStateView = AgentEmptyStateView()
        emptyStateView.onSuggestionSelected = { [weak self] message in
            self?.chatInputView.text = message
        }
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateView)
    }

    private func setupChatInput() {
        chatInputView = AgentChatInputView(connections: dataController.connections)
        chatInputView.onConnectionsChanged = { [weak self] connections in
            self?.chatController.selectedConnections = connections
        }
        chatInputView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatInputView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            messageListController.view.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            messageListController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageListController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageListController.view.bottomAnchor.constraint(equalTo: chatInputView.topAnchor),

            emptyStateView.topAnchor.constraint(greaterThanOrEqualTo: headerView.bottomAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: chatInputView.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            chatInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatInputView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func wireCallbacks() {
        headerView.onClose = { [weak self] in
            self?.dataController.isRightSidebarVisible = false
        }
        headerView.onCompose = { [weak self] in
            guard let self, !self.chatController.messages.isEmpty else { return }
            self.chatController.createNewChat()
        }
        headerView.onNewChat = { [weak self] in
            self?.showChatHistoryPopover()
        }
        chatInputView.onSend = { [weak self] text in
            guard let self else { return }
            let didStartStreaming = self.chatController.send(text: text)
            self.chatInputView.isStreaming = didStartStreaming
        }
        chatInputView.onStop = { [weak self] in
            self?.chatController.cancelStreaming()
        }
    }

    // MARK: - Observation

    private func observeEmptyState() {
        withObservationTracking {
            _ = self.chatController.messages.count
            _ = self.chatController.isStreaming
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncEmptyStateVisibility()
                self.observeEmptyState()
            }
        }
    }

    private func observeCurrentChat() {
        withObservationTracking {
            _ = self.chatController.currentChat?.id
            _ = self.chatController.currentChat?.title
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncHeaderTitle()
                self.syncHeaderActions()
                self.observeCurrentChat()
            }
        }
    }

    private func syncEmptyStateVisibility() {
        let hasContent = !chatController.messages.isEmpty || chatController.isStreaming
        emptyStateView.isHidden = hasContent
        messageListController.view.isHidden = !hasContent
        chatInputView.isStreaming = chatController.isStreaming
        syncHeaderActions()
    }

    private func syncHeaderTitle() {
        headerView.updateTitle(chatController.currentChat?.title ?? "New Chat")
    }

    private func syncHeaderActions() {
        let canCreateNewChat = !chatController.messages.isEmpty
        headerView.setNewChatEnabled(canCreateNewChat)
    }

    private func observePendingMessage() {
        withObservationTracking {
            _ = self.dataController.pendingAgentMessage
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePendingMessage()
                self.observePendingMessage()
            }
        }
    }

    private func handlePendingMessage() {
        guard let text = dataController.pendingAgentMessage else { return }
        dataController.pendingAgentMessage = nil
        let pendingConnections = dataController.pendingAgentConnections
        dataController.pendingAgentConnections = nil

        if let connections = pendingConnections {
            chatController.selectedConnections = connections
            chatInputView.setSelectedConnections(connections)
        }

        _ = chatController.send(text: text)
    }

    private func observeConnections() {
        withObservationTracking {
            _ = self.dataController.connections.map(\.keychainId)
            _ = self.dataController.connections.map(\.name)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncAvailableConnections()
                self.observeConnections()
            }
        }
    }

    private func syncAvailableConnections() {
        chatInputView.updateAvailableConnections(dataController.connections)
    }

    // MARK: - Chat History Popover

    private var chatHistoryPopover: NSPopover?

    private func showChatHistoryPopover() {
        if let existing = chatHistoryPopover, existing.isShown {
            existing.close()
            chatHistoryPopover = nil
            return
        }

        let popoverVC = AgentChatHistoryPopoverController(
            chats: chatController.chats,
            currentChatId: chatController.currentChat?.id
        )
        popoverVC.onSelectChat = { [weak self] chat in
            self?.chatHistoryPopover?.close()
            self?.chatHistoryPopover = nil
            self?.chatController.selectChat(chat)
            self?.syncHeaderTitle()
            self?.syncHeaderActions()
        }
        popoverVC.onDeleteChat = { [weak self] chat in
            self?.chatController.deleteChat(chat)
            self?.chatHistoryPopover?.close()
            self?.chatHistoryPopover = nil
            self?.syncHeaderTitle()
            self?.syncHeaderActions()
        }

        let popover = NSPopover()
        popover.contentViewController = popoverVC
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.show(relativeTo: headerView.dropdownButtonBounds, of: headerView, preferredEdge: .minY)
        chatHistoryPopover = popover
    }
}
