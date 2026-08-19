import AppKit
import SwiftData

/// Chat content for the table view's right dock. Mirrors the notebook agent
/// panel body (`NotebookAgentController`) — message list, empty-state
/// suggestions, and the chat input — driven by an `AgentChatController` in
/// table mode: exploration-only tools with the currently open table injected
/// into the system prompt. The header toolbar and resizing are owned by
/// `RightSidebarContainerViewController`, so this controller is content-only.
@MainActor
final class TableChatSidebarViewController: NSViewController {

    private let instance: ConnectionInstance
    private let chatController: AgentChatController

    private var emptyStateView: AgentEmptyStateView!
    private var messageListController: AgentMessageListController!
    private var chatInputView: AgentChatInputView!

    /// Notifies the container header when the active chat changes so it can
    /// reflect the chat title while in chat mode.
    var onTitleChange: ((String) -> Void)?

    var currentChatTitle: String {
        chatController.currentChat?.title ?? "New Chat"
    }

    var canStartNewChat: Bool {
        !chatController.messages.isEmpty
    }

    var chats: [AgentChat] {
        chatController.chats
    }

    var currentChatId: UUID? {
        chatController.currentChat?.id
    }

    func selectChat(_ chat: AgentChat) {
        chatController.selectChat(chat)
    }

    func deleteChat(_ chat: AgentChat) {
        chatController.deleteChat(chat)
    }

    init(instance: ConnectionInstance, modelContainer: ModelContainer) {
        self.instance = instance
        // Chats are scoped per connection so every table on the connection
        // shares one history. keychainId is generated as UUID().uuidString, so
        // it round-trips back into a stable UUID.
        let scopeId = UUID(uuidString: instance.connection.keychainId) ?? UUID()
        self.chatController = AgentChatController(
            scopeId: scopeId,
            modelContainer: modelContainer,
            tableContextProvider: { [weak instance] in
                guard let instance else { return nil }
                return Self.makeTableContext(instance: instance)
            }
        )
        super.init(nibName: nil, bundle: nil)
    }

    /// Snapshots the open table plus everything the app has already loaded —
    /// the table's fetched schema, the database's table list, and the
    /// connection's database list — so the agent can skip discovery tool calls.
    private static func makeTableContext(instance: ConnectionInstance) -> TableAgentContext? {
        guard let tab = instance.selectedTab, tab.type == .browse else { return nil }

        // Interactive filters built in the filter bar live on the tab's
        // TableDataController, not on the tab itself — prefer them so the
        // agent sees what the user actually sees.
        var filterDescription: String?
        if let activeFilter = instance.tableDataControllers[tab.id]?.currentActiveFilter,
           !activeFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filterDescription = activeFilter
        } else if let column = tab.filterColumn, let value = tab.filterValue {
            filterDescription = "\(column) = \(value)"
        }

        var columnLines: [String] = []
        if let schema = instance.tableDataControllers[tab.id]?.currentSchema {
            columnLines = schema.columns.map { col in
                var line = "- \(col.columnName): \(col.formatType)"
                if col.isNullable.uppercased() == "NO" {
                    line += ", not null"
                }
                if !col.foreignKey.isEmpty {
                    line += ", FK -> \(col.foreignKey)"
                }
                if let enumValues = col.enumValues, !enumValues.isEmpty {
                    line += ", values: \(enumValues.prefix(20).joined(separator: "|"))"
                }
                return line
            }
        }

        let databaseName = instance.connectedDatabase?.name ?? instance.connection.defaultDatabase
        var knownTables: [String] = []
        let collections = databaseName.flatMap { instance.collections[$0] }
            ?? (instance.collections.count == 1 ? instance.collections.values.first : nil)
        if let collections {
            knownTables = collections.prefix(200).map { collection in
                if let schema = collection.schema, !schema.isEmpty {
                    return "\(schema).\(collection.name)"
                }
                return collection.name
            }
        }

        let knownDatabases = instance.databases.prefix(50).map(\.name)

        return TableAgentContext(
            tableName: tab.name,
            schemaName: tab.databaseSchema,
            databaseName: databaseName,
            filterDescription: filterDescription,
            columnLines: columnLines,
            knownTables: knownTables,
            knownDatabases: knownDatabases
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        setupMessageList()
        setupEmptyState()
        setupChatInput()
        setupConstraints()
    }

    private static let approvalModeDefaultsKey = "tableChatWriteApprovalMode"

    private static var storedApprovalMode: AgentWriteApprovalMode {
        UserDefaults.standard.string(forKey: approvalModeDefaultsKey)
            .flatMap(AgentWriteApprovalMode.init(rawValue:)) ?? .askApproval
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        chatController.load()
        chatController.selectedConnections = [instance.connection]
        configureWriteApproval()
        syncEmptyStateVisibility()
        notifyTitleChange()
        observeEmptyState()
        observeCurrentChat()
    }

    private func configureWriteApproval() {
        chatController.engine.writeApprovalMode = Self.storedApprovalMode
        chatController.engine.writeApprovalHandler = { [weak self] request in
            await self?.confirmWriteExecution(request: request) ?? false
        }
        chatController.engine.onWriteExecuted = { [weak self] in
            guard let self,
                  let tab = instance.selectedTab,
                  let dataController = instance.tableDataControllers[tab.id] else { return }
            Task { await dataController.refreshData() }
        }
        chatController.engine.onOpenQueryTab = { [weak instance] query, databaseName, schemaName in
            guard let instance else {
                return "Error: The table view is no longer available."
            }
            // The editor tab runs against the connection's current database —
            // refuse silently running a query meant for a different one.
            let currentDatabase = instance.connectedDatabase?.name ?? instance.connection.defaultDatabase
            if let databaseName, !databaseName.isEmpty,
               let currentDatabase, databaseName != currentDatabase {
                return "Error: The query tab runs against the current database (\(currentDatabase)), not \(databaseName). Qualify table names explicitly (e.g. database.table) if the dialect supports it, or ask the user to switch databases first."
            }
            instance.createSQLEditorTab(withQuery: query, autoRun: true, schema: schemaName)
            return nil
        }
    }

    /// Declines a pending approval without touching the stream. Used when the
    /// card would otherwise go offscreen (e.g. switching to Row Detail) and
    /// leave the agent suspended with no way to decide.
    func declinePendingApproval() {
        resolveApproval(false)
    }

    /// Declines any pending approval and stops streaming so no continuation or
    /// agent task outlives the sidebar. Called by the container before the
    /// dock is torn down.
    func prepareForRemoval() {
        resolveApproval(false)
        chatController.cancelStreaming()
        let engine = chatController.engine
        Task { await engine.cleanup() }
    }

    deinit {
        // Safety net: a leaked continuation would suspend the agent task
        // forever and retain the whole chat stack.
        MainActor.assumeIsolated {
            approvalContinuation?.resume(returning: false)
            approvalContinuation = nil
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        chatInputView.focusInput()
    }

    // MARK: - Header Actions

    func startNewChat() {
        guard canStartNewChat else { return }
        chatController.createNewChat()
    }

    /// Keeps an unused "New Chat" entry in the history list so it doubles as the
    /// create action. Called before presenting the history popover.
    func ensureUnusedChat() {
        chatController.ensureUnusedChatExists()
    }

    // MARK: - Setup

    private func setupMessageList() {
        messageListController = AgentMessageListController(chatController: chatController)
        addChild(messageListController)
        messageListController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageListController.view)
    }

    private func setupEmptyState() {
        emptyStateView = AgentEmptyStateView(suggestions: AgentEmptyStateView.tableSuggestions)
        emptyStateView.onSuggestionSelected = { [weak self] message in
            self?.chatInputView.text = message
        }
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateView)
    }

    private func setupChatInput() {
        chatInputView = AgentChatInputView()
        // Also selects the connection, so the init(connections:) argument
        // (which only stores availability) would be redundant.
        chatInputView.updateAvailableConnections([instance.connection])
        chatInputView.onConnectionsChanged = { [weak self] connections in
            self?.chatController.selectedConnections = connections
        }
        // The connection is fixed to this table's connection — no picker.
        chatInputView.setConnectionPickerHidden(true)
        chatInputView.setApprovalModePicker(visible: true, mode: Self.storedApprovalMode)
        chatInputView.onApprovalModeChanged = { [weak self] mode in
            UserDefaults.standard.set(mode.rawValue, forKey: Self.approvalModeDefaultsKey)
            self?.chatController.engine.writeApprovalMode = mode
        }
        chatInputView.onSend = { [weak self] text in
            guard let self else { return }
            let didStartStreaming = self.chatController.send(text: text)
            self.chatInputView.isStreaming = didStartStreaming
        }
        chatInputView.onStop = { [weak self] in
            guard let self else { return }
            // While an approval is pending, stop (including Return routed to
            // the input) declines just the statement instead of killing the
            // whole response.
            if approvalCard != nil {
                resolveApproval(false)
                return
            }
            chatController.cancelStreaming()
        }
        chatInputView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatInputView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            messageListController.view.topAnchor.constraint(equalTo: view.topAnchor),
            messageListController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageListController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageListController.view.bottomAnchor.constraint(equalTo: chatInputView.topAnchor),

            emptyStateView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: chatInputView.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            chatInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            // AgentChatInputView insets its card 4pt on its own edges; shift
            // right/down so the card aligns with the table view's edge, keeping
            // 1pt inside the dock's clip so the card shadow still renders.
            chatInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 3),
            chatInputView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 3),
        ])
    }

    // MARK: - Write Approval

    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var approvalCard: WriteApprovalCardView?

    /// Presents the data-modifying statement for explicit user approval before
    /// the agent may execute it. The card floats on top of the chat input like
    /// a browser permission prompt; Return/A approves, Esc/B declines.
    private func confirmWriteExecution(request: WriteApprovalRequest) async -> Bool {
        // A previous request should never still be pending; decline it if so.
        resolveApproval(false)

        var target = request.connection.name
        if !request.databaseName.isEmpty {
            target += " · \(request.databaseName)"
        }
        if let schema = request.schemaName, !schema.isEmpty {
            target += " · schema \(schema)"
        }
        let card = WriteApprovalCardView(query: request.query, target: target)
        card.onDecision = { [weak self] approved in
            self?.resolveApproval(approved)
        }
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        // Covers the input while the decision is pending — the agent loop is
        // suspended, so the composer is unusable anyway. Same 4pt margins as
        // the input container so it visually takes its place.
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -1),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -1),
        ])
        approvalCard = card
        view.window?.makeFirstResponder(card)

        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    private func resolveApproval(_ approved: Bool) {
        guard approvalContinuation != nil || approvalCard != nil else { return }
        approvalCard?.removeFromSuperview()
        approvalCard = nil
        approvalContinuation?.resume(returning: approved)
        approvalContinuation = nil
        chatInputView.focusInput()
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
                self.notifyTitleChange()
                self.observeCurrentChat()
            }
        }
    }

    private func syncEmptyStateVisibility() {
        let hasContent = !chatController.messages.isEmpty || chatController.isStreaming
        emptyStateView.isHidden = hasContent
        messageListController.view.isHidden = !hasContent
        chatInputView.isStreaming = chatController.isStreaming
        // If the user stopped the response while an approval was pending,
        // treat it as a decline so the card doesn't dangle.
        if !chatController.isStreaming {
            resolveApproval(false)
        }
    }

    private func notifyTitleChange() {
        onTitleChange?(currentChatTitle)
    }
}

// MARK: - Write Approval Card

/// Xcode-agent-style approval shown in place of the chat input when Quarry AI
/// wants to run a data-modifying statement: a small section label, the
/// question, the statement, then option rows with descriptions — the
/// recommended row outlined with the system accent. Clicking a row decides;
/// Return runs, Esc cancels. Chrome matches the chat input container.
private final class WriteApprovalCardView: NSView {

    var onDecision: ((Bool) -> Void)?

    private let query: String
    private let queryBlock = NSView()
    private let queryLabel: NSTextField
    private var optionRows: [ApprovalOptionRowView] = []
    private var selectedRowIndex = 0

    init(query: String, target: String) {
        self.query = query
        self.queryLabel = NSTextField(wrappingLabelWithString: "")
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.10)
            s.shadowBlurRadius = 1
            s.shadowOffset = .zero
            return s
        }()

        let sectionIcon = NSImageView(image: NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil) ?? NSImage())
        sectionIcon.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        sectionIcon.contentTintColor = .secondaryLabelColor
        sectionIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sectionIcon)

        let sectionLabel = NSTextField(labelWithString: "Approval")
        sectionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        sectionLabel.textColor = .secondaryLabelColor
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sectionLabel)

        let questionLabel = NSTextField(wrappingLabelWithString: "Run this statement on \(target)?")
        questionLabel.font = .preferredFont(forTextStyle: .body)
        questionLabel.textColor = .labelColor
        questionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(questionLabel)

        queryBlock.wantsLayer = true
        queryBlock.layer?.cornerRadius = 8
        queryBlock.layer?.cornerCurve = .continuous
        queryBlock.translatesAutoresizingMaskIntoConstraints = false
        addSubview(queryBlock)

        queryLabel.isSelectable = true
        // Keep the syntax colors when the field editor takes over on click.
        queryLabel.allowsEditingTextAttributes = true
        queryLabel.lineBreakMode = .byCharWrapping
        queryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        queryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        queryLabel.translatesAutoresizingMaskIntoConstraints = false
        queryBlock.addSubview(queryLabel)

        let runRow = ApprovalOptionRowView(
            title: "Run (Recommended)",
            subtitle: "Executes this statement on \(target)."
        )
        runRow.onSelect = { [weak self] in self?.onDecision?(true) }
        runRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(runRow)

        let cancelRow = ApprovalOptionRowView(
            title: "Do not run",
            subtitle: "Cancels and lets you tell Quarry AI what to do instead."
        )
        cancelRow.onSelect = { [weak self] in self?.onDecision?(false) }
        cancelRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelRow)

        optionRows = [runRow, cancelRow]
        selectRow(at: 0)

        NSLayoutConstraint.activate([
            sectionIcon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            sectionIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            sectionLabel.centerYAnchor.constraint(equalTo: sectionIcon.centerYAnchor),
            sectionLabel.leadingAnchor.constraint(equalTo: sectionIcon.trailingAnchor, constant: 5),

            questionLabel.topAnchor.constraint(equalTo: sectionIcon.bottomAnchor, constant: 8),
            questionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            questionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            queryBlock.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 8),
            queryBlock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            queryBlock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            queryLabel.topAnchor.constraint(equalTo: queryBlock.topAnchor, constant: 8),
            queryLabel.leadingAnchor.constraint(equalTo: queryBlock.leadingAnchor, constant: 10),
            queryLabel.trailingAnchor.constraint(equalTo: queryBlock.trailingAnchor, constant: -10),
            queryLabel.bottomAnchor.constraint(equalTo: queryBlock.bottomAnchor, constant: -8),

            runRow.topAnchor.constraint(equalTo: queryBlock.bottomAnchor, constant: 12),
            runRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            runRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            cancelRow.topAnchor.constraint(equalTo: runRow.bottomAnchor, constant: 4),
            cancelRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            cancelRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            cancelRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        updateColors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func updateColors() {
        // Identical to AgentChatInputView.updateContainerAppearance().
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            self.layer?.backgroundColor = isDark
                ? NSColor.black.withAlphaComponent(0.25).cgColor
                : NSColor.white.cgColor
            self.queryBlock.layer?.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.08).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
            self.queryLabel.attributedStringValue = Self.highlightedSQL(self.query, isDark: isDark)
        }
    }

    @objc private func handleAppearanceChange() {
        updateColors()
    }

    // MARK: SQL Highlighting

    private static let sqlKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "UPDATE", "SET", "INSERT", "INTO", "VALUES",
        "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "TRUNCATE", "JOIN",
        "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS", "ON", "AND", "OR",
        "NOT", "NULL", "IN", "IS", "LIKE", "ORDER", "BY", "GROUP", "HAVING",
        "LIMIT", "OFFSET", "AS", "DISTINCT", "COUNT", "SUM", "AVG", "MIN",
        "MAX", "BETWEEN", "CASE", "WHEN", "THEN", "ELSE", "END", "EXISTS",
        "UNION", "ALL", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT",
        "INDEX", "IF", "ADD", "COLUMN", "RETURNING", "CASCADE", "CONSTRAINT",
    ]

    /// Lightweight SQL highlighting using the code editor's theme colours so
    /// the statement reads like it does in the SQL editor.
    private static func highlightedSQL(_ query: String, isDark: Bool) -> NSAttributedString {
        let theme = isDark ? Theme.defaultDark : Theme.defaultLight
        let text = query as NSString
        let attributed = NSMutableAttributedString(string: query, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: theme.textColour,
        ])

        func apply(_ pattern: String, color: NSColor, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: query, range: NSRange(location: 0, length: text.length)) {
                attributed.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        // Order matters: later passes override earlier ones inside their ranges.
        let keywordPattern = "\\b(" + sqlKeywords.joined(separator: "|") + ")\\b"
        apply(keywordPattern, color: theme.keywordColour, options: [.caseInsensitive])
        apply("\\b\\d+(\\.\\d+)?\\b", color: theme.numberColour)
        apply("'(?:[^']|'')*'", color: theme.stringColour)
        apply("--[^\\n]*", color: theme.commentColour)

        return attributed
    }

    // MARK: Keyboard

    private func selectRow(at index: Int) {
        selectedRowIndex = index
        for (i, row) in optionRows.enumerated() {
            row.isSelected = i == index
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let returnKeyCode: UInt16 = 36
        let escapeKeyCode: UInt16 = 53
        let downArrowKeyCode: UInt16 = 125
        let upArrowKeyCode: UInt16 = 126
        switch event.keyCode {
        case returnKeyCode:
            // Row 0 is Run, row 1 is Do not run.
            onDecision?(selectedRowIndex == 0)
        case escapeKeyCode:
            onDecision?(false)
        case downArrowKeyCode:
            selectRow(at: min(selectedRowIndex + 1, optionRows.count - 1))
        case upArrowKeyCode:
            selectRow(at: max(selectedRowIndex - 1, 0))
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Approval Option Row

/// Xcode-style option row: title with a small description beneath. The
/// selected row wears PrimaryButtonStyle (solid copper fill, white text);
/// arrow keys or hovering moves the selection, clicking activates it.
private final class ApprovalOptionRowView: NSView {

    var onSelect: (() -> Void)?

    var isSelected = false {
        didSet { updateColors() }
    }

    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(title: String, subtitle: String) {
        titleLabel = NSTextField(labelWithString: title)
        subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        updateColors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func updateColors() {
        if isSelected {
            layer?.backgroundColor = NSColor.primaryButton
                .withAlphaComponent(isHovering ? 0.8 : 1.0)
                .cgColor
            titleLabel.textColor = .textBackgroundColor
            subtitleLabel.textColor = NSColor.textBackgroundColor.withAlphaComponent(0.75)
        } else {
            layer?.backgroundColor = isHovering
                ? NSColor.quaternarySystemFill.cgColor
                : NSColor.clear.cgColor
            titleLabel.textColor = .labelColor
            subtitleLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateColors()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        refreshHoverState()
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            updateColors()
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        updateColors()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateColors()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}
