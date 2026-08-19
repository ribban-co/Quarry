import AppKit
import SwiftUI
import LanguageSupport

final class QueryBlockController: NSViewController, NSTextFieldDelegate {

    let viewModel: QueryBlockViewModel
    private let dataController: NotebookDataController
    private let showChrome: Bool

    private(set) var titleLabel: NSTextField!
    private var blockContainer: NSView!
    private var connectionButton: SourceDropdownButton!
    private var runButton: NSButton!
    private var menuButton: NSButton!
    private var resizeHandle: NSView!
    private var blockHeightConstraint: NSLayoutConstraint!

    private var editorViewController: CodeEditorViewController?
    private var toolbarHostingView: NSView?
    private var resultsContainerView: NSView?
    private var resultsCoordinator: TableCoordinator?
    private var emptyStateHostingView: NSView?
    private var errorStateHostingView: NSView?
    private var outputNameField: NSTextField!
    private var outputFieldWrapper: NSView!
    private var splitterView: QuerySplitterView!
    private var editorHeightConstraint: NSLayoutConstraint!
    private var toolbarBottomConstraint: NSLayoutConstraint!
    private var splitterHeightConstraint: NSLayoutConstraint!

    private var queryText: String = ""
    private var saveDebounceTask: Task<Void, Never>?
    private var popover: NSPopover?
    private var isResultsCollapsed = true
    private var expandedBlockHeight: CGFloat = 0

    init(block: NotebookBlock, dataController: NotebookDataController, showChrome: Bool = true) {
        self.dataController = dataController
        self.viewModel = dataController.queryViewModel(for: block)
        self.showChrome = showChrome
        self.queryText = viewModel.config?.queryText ?? ""
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        saveDebounceTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        if showChrome {
            let wrapper = BlockHoverTrackingView { [weak self] isHovered in
                guard let self,
                      let blockIndex = self.dataController.blocks.firstIndex(where: { $0.id == self.viewModel.block.id }) else { return }
                let showButtons = isHovered || self.popover?.isShown == true
                self.runButton.isHidden = !showButtons
                self.menuButton.isHidden = !showButtons
                NotificationCenter.default.post(
                    name: .notebookBlockHoverChanged,
                    object: nil,
                    userInfo: ["blockIndex": blockIndex, "isHovered": isHovered]
                )
            }
            wrapper.wantsLayer = true
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            self.view = wrapper

            setupTitleLabel()
            setupBlockContainer()
            setupRunButton()
            setupMenuButton()
            setupResizeHandle()
            setupBlockContent()
            setupWrapperConstraints()
            applyCollapsedState()

            observeViewModel()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppearanceChange),
                name: .appAppearanceDidChange,
                object: nil
            )
        } else {
            let wrapper = NSView()
            wrapper.wantsLayer = true
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            self.view = wrapper

            setupBlockContainer()
            blockContainer.layer?.borderWidth = 0
            setupBlockContent()

            blockHeightConstraint = blockContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: max(200, viewModel.block.blockHeight))

            NSLayoutConstraint.activate([
                blockContainer.topAnchor.constraint(equalTo: view.topAnchor),
                blockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                blockContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                blockContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            applyCollapsedState()
            observeViewModel()
        }
    }

    // MARK: - Layout

    private func setupTitleLabel() {
        let text = viewModel.block.title.isEmpty ? "Untitled Query" : viewModel.block.title
        titleLabel = NSTextField(string: text)
        titleLabel.placeholderString = "Untitled Query"
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.backgroundColor = .clear
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.focusRingType = .none
        titleLabel.isEditable = true
        titleLabel.delegate = self
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
    }

    private func setupBlockContainer() {
        blockContainer = NSView()
        blockContainer.wantsLayer = true
        blockContainer.layer?.cornerRadius = 10
        blockContainer.layer?.borderWidth = 1
        blockContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blockContainer)
        updateBorderColor()
    }

    private func setupRunButton() {
        runButton = NSButton(frame: .zero)
        runButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run")
        runButton.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        runButton.bezelStyle = .accessoryBar
        runButton.isBordered = false
        runButton.imagePosition = .imageOnly
        runButton.contentTintColor = .white
        runButton.wantsLayer = true
        runButton.layer?.cornerRadius = 4
        runButton.layer?.backgroundColor = NSColor.primaryButton.cgColor
        runButton.isHidden = true
        runButton.translatesAutoresizingMaskIntoConstraints = false
        runButton.target = self
        runButton.action = #selector(handleRunTapped)
        view.addSubview(runButton)
    }

    @objc private func handleRunTapped() {
        Task { await viewModel.executeQuery() }
    }

    private func setupMenuButton() {
        menuButton = NSButton(frame: .zero)
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Block menu")
        menuButton.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        menuButton.bezelStyle = .accessoryBar
        menuButton.isBordered = false
        menuButton.imagePosition = .imageOnly
        menuButton.contentTintColor = .tertiaryLabelColor
        menuButton.isHidden = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.target = self
        menuButton.action = #selector(showBlockMenu(_:))
        view.addSubview(menuButton)
    }

    private func setupResizeHandle() {
        resizeHandle = BlockResizeHandle(onDrag: { [weak self] delta in
            self?.handleResize(delta: delta)
        })
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resizeHandle)
    }

    private func handleResize(delta: CGFloat) {
        let minHeight: CGFloat = isResultsCollapsed ? 100 : 200
        let newHeight = max(minHeight, blockHeightConstraint.constant + delta)
        blockHeightConstraint.constant = newHeight
        if !isResultsCollapsed {
            viewModel.block.blockHeight = newHeight
            dataController.updateBlock(viewModel.block)
        }
    }

    private func handleSplitterDrag(delta: CGFloat) {
        let blockHeight = blockHeightConstraint.constant
        let minEditor: CGFloat = 60
        let maxEditor = blockHeight - 100
        let newHeight = min(max(minEditor, editorHeightConstraint.constant - delta), maxEditor)
        editorHeightConstraint.constant = newHeight
    }

    private func toggleResultsCollapse() {
        isResultsCollapsed.toggle()
        applyCollapsedState()
        updateToolbarCollapsedState()
    }

    private func applyCollapsedState() {
        if isResultsCollapsed {
            expandedBlockHeight = blockHeightConstraint.constant

            splitterView.isHidden = true
            splitterHeightConstraint.constant = 0
            resultsContainerView?.isHidden = true
            emptyStateHostingView?.isHidden = true
            errorStateHostingView?.isHidden = true

            editorHeightConstraint.isActive = false
            toolbarBottomConstraint.isActive = true

            let editorHeight = editorHeightConstraint.constant
            let toolbarHeight = toolbarHostingView?.fittingSize.height ?? 40
            let connectionRowHeight: CGFloat = 38
            let collapsedHeight = connectionRowHeight + editorHeight + toolbarHeight
            blockHeightConstraint.constant = max(100, collapsedHeight)
        } else {
            toolbarBottomConstraint.isActive = false
            editorHeightConstraint.isActive = true

            blockHeightConstraint.constant = max(200, expandedBlockHeight)
            viewModel.block.blockHeight = blockHeightConstraint.constant
            dataController.updateBlock(viewModel.block)

            splitterHeightConstraint.constant = 6
            splitterView.isHidden = false
            updateResultsVisibility()
        }
    }

    private func updateToolbarCollapsedState() {
        guard let oldHosting = toolbarHostingView,
              let editorVC = editorViewController else { return }
        let editorView = editorVC.view
        let newToolbar = QueryToolbarView(
            viewModel: viewModel,
            onRun: { [weak self] in
                guard let self else { return }
                Task { await self.viewModel.executeQuery() }
            },
            isCollapsed: isResultsCollapsed,
            onToggleCollapse: { [weak self] in
                self?.toggleResultsCollapse()
            }
        )
        let newHosting = NSHostingView(rootView: newToolbar)
        newHosting.translatesAutoresizingMaskIntoConstraints = false

        let wasActive = toolbarBottomConstraint.isActive
        toolbarBottomConstraint.isActive = false

        oldHosting.removeFromSuperview()
        blockContainer.addSubview(newHosting)

        toolbarBottomConstraint = newHosting.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor)
        toolbarBottomConstraint.isActive = wasActive

        NSLayoutConstraint.activate([
            newHosting.topAnchor.constraint(equalTo: editorView.bottomAnchor),
            newHosting.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            newHosting.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            splitterView.topAnchor.constraint(equalTo: newHosting.bottomAnchor),
        ])

        self.toolbarHostingView = newHosting
    }

    private func setupBlockContent() {
        // Connection picker
        connectionButton = SourceDropdownButton(connections: dataController.connections) { [weak self] connection in
            guard let self else { return }
            Task { await self.viewModel.connectToSource(connection) }
        }
        connectionButton.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(connectionButton)

        if let cfg = viewModel.config {
            connectionButton.updateLabel(cfg.connectionName, iconName: DatabaseType(rawValue: cfg.databaseType)?.icon)
        }

        // Code editor (AppKit)
        let databaseType = viewModel.config.flatMap { DatabaseType(rawValue: $0.databaseType) }
        let editorLanguage: LanguageConfiguration = switch databaseType {
        case .convex:    .javascript()
        case .mongodb:   .mongodb()
        default:         .sqlite()
        }

        let isDark = NSApp.effectiveAppearance.isDarkMode
        var editorTheme = isDark ? Theme.defaultDark : Theme.defaultLight
        editorTheme.backgroundColour = .clear

        let editorVC = CodeEditorViewController(
            language: editorLanguage,
            theme: editorTheme,
            layout: CodeEditorTypes.LayoutConfiguration(wrapText: true)
        )
        editorVC.delegate = self
        addChild(editorVC)

        let editorView = editorVC.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(editorView)
        self.editorViewController = editorVC

        // Set initial text
        if queryText.isEmpty && databaseType == .convex {
            queryText = """
            export default query({
              handler: async (ctx) => {
                console.log("Write and test your query function here!");
                return await ctx.db.query("table_name").take(10);
              },
            })
            """
        }
        editorVC.text = queryText

        // Toolbar (SwiftUI) — matches SQL editor toolbar layout
        let toolbarView = QueryToolbarView(
            viewModel: viewModel,
            onRun: { [weak self] in
                guard let self else { return }
                Task { await self.viewModel.executeQuery() }
            },
            isCollapsed: isResultsCollapsed,
            onToggleCollapse: { [weak self] in
                self?.toggleResultsCollapse()
            }
        )
        let toolbarHosting = NSHostingView(rootView: toolbarView)
        toolbarHosting.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(toolbarHosting)
        self.toolbarHostingView = toolbarHosting

        // Draggable splitter between toolbar and results
        splitterView = QuerySplitterView { [weak self] delta in
            self?.handleSplitterDrag(delta: delta)
        }
        splitterView.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(splitterView)

        // Results table — reuse TableCoordinator's full setup for consistent design
        let coordinator = TableCoordinator(queryResult: viewModel.queryResult, showPaddingRows: false, isReadOnly: true)
        self.resultsCoordinator = coordinator

        let tableContainer = coordinator.setupTableView()
        tableContainer.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(tableContainer)
        self.resultsContainerView = tableContainer

        // Empty state (shown when no query results yet)
        let emptyState = NSHostingView(rootView: QueryEmptyStateView(databaseType: viewModel.config.flatMap { DatabaseType(rawValue: $0.databaseType) }))
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(emptyState)
        self.emptyStateHostingView = emptyState

        // Error state (shown on query failure)
        let errorState = NSHostingView(rootView: QueryErrorStateView(message: ""))
        errorState.translatesAutoresizingMaskIntoConstraints = false
        errorState.isHidden = true
        blockContainer.addSubview(errorState)
        self.errorStateHostingView = errorState

        // Output name field — sits in the connection row (right side)
        let outputLabel = NSTextField(labelWithString: "Output:")
        outputLabel.font = .systemFont(ofSize: 11)
        outputLabel.textColor = .tertiaryLabelColor
        outputLabel.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(outputLabel)

        outputNameField = NSTextField(string: viewModel.config?.outputName ?? "")
        outputNameField.placeholderString = "output_name"
        outputNameField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        outputNameField.textColor = .secondaryLabelColor
        outputNameField.backgroundColor = .clear
        outputNameField.isBordered = false
        outputNameField.isBezeled = false
        outputNameField.focusRingType = .none
        outputNameField.isEditable = true
        outputNameField.delegate = self
        outputNameField.alignment = .left
        outputNameField.translatesAutoresizingMaskIntoConstraints = false

        let outputFieldWrapper = NSView()
        outputFieldWrapper.wantsLayer = true
        outputFieldWrapper.layer?.cornerRadius = 6
        outputFieldWrapper.layer?.borderWidth = 1
        outputFieldWrapper.translatesAutoresizingMaskIntoConstraints = false
        blockContainer.addSubview(outputFieldWrapper)
        outputFieldWrapper.addSubview(outputNameField)
        self.outputFieldWrapper = outputFieldWrapper
        updateOutputFieldBorder()

        NSLayoutConstraint.activate([
            outputNameField.leadingAnchor.constraint(equalTo: outputFieldWrapper.leadingAnchor, constant: 6),
            outputNameField.trailingAnchor.constraint(equalTo: outputFieldWrapper.trailingAnchor, constant: -6),
            outputNameField.centerYAnchor.constraint(equalTo: outputFieldWrapper.centerYAnchor),
        ])

        // Editor height — resizable via splitter drag
        editorHeightConstraint = editorView.heightAnchor.constraint(equalToConstant: 100)

        // Layout within block container
        NSLayoutConstraint.activate([
            // Connection row: picker left, output right
            connectionButton.topAnchor.constraint(equalTo: blockContainer.topAnchor, constant: 8),
            connectionButton.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor, constant: 10),
            connectionButton.heightAnchor.constraint(equalToConstant: 24),

            outputFieldWrapper.centerYAnchor.constraint(equalTo: connectionButton.centerYAnchor),
            outputFieldWrapper.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor, constant: -10),
            outputFieldWrapper.widthAnchor.constraint(equalToConstant: 120),
            outputFieldWrapper.heightAnchor.constraint(equalToConstant: 22),

            outputLabel.centerYAnchor.constraint(equalTo: connectionButton.centerYAnchor),
            outputLabel.trailingAnchor.constraint(equalTo: outputFieldWrapper.leadingAnchor, constant: -4),

            // Editor
            editorView.topAnchor.constraint(equalTo: connectionButton.bottomAnchor, constant: 6),
            editorView.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            editorHeightConstraint,

            // Toolbar
            toolbarHosting.topAnchor.constraint(equalTo: editorView.bottomAnchor),
            toolbarHosting.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            toolbarHosting.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
        ])

        toolbarBottomConstraint = toolbarHosting.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor)
        toolbarBottomConstraint.isActive = false

        NSLayoutConstraint.activate([
            // Splitter
            splitterView.topAnchor.constraint(equalTo: toolbarHosting.bottomAnchor),
            splitterView.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            splitterView.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),

            // Results — fills to block bottom
            tableContainer.topAnchor.constraint(equalTo: splitterView.bottomAnchor),
            tableContainer.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            tableContainer.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            tableContainer.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: splitterView.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),

            errorState.topAnchor.constraint(equalTo: splitterView.bottomAnchor),
            errorState.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            errorState.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            errorState.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),
        ])

        splitterHeightConstraint = splitterView.heightAnchor.constraint(equalToConstant: 6)
        splitterHeightConstraint.isActive = true

        updateResultsVisibility()
    }

    private func setupWrapperConstraints() {
        let savedHeight = max(200, viewModel.block.blockHeight)
        blockHeightConstraint = blockContainer.heightAnchor.constraint(equalToConstant: savedHeight)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            runButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            runButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 18),
            runButton.heightAnchor.constraint(equalToConstant: 12),

            menuButton.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 2),
            menuButton.centerXAnchor.constraint(equalTo: runButton.centerXAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 24),
            menuButton.heightAnchor.constraint(equalToConstant: 24),

            blockContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            blockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blockContainer.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -4),
            blockHeightConstraint,

            resizeHandle.topAnchor.constraint(equalTo: blockContainer.bottomAnchor),
            resizeHandle.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: 12),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Query Text Changes

    private func handleQueryTextChanged(_ text: String) {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.viewModel.setQueryText(text)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === titleLabel {
            viewModel.block.title = field.stringValue
            dataController.updateBlock(viewModel.block)
        } else if field === outputNameField {
            viewModel.setOutputName(field.stringValue)
        }
    }

    // MARK: - Results Update

    private func updateResultsTable() {
        guard let result = viewModel.queryResult,
              let coordinator = resultsCoordinator else { return }
        coordinator.updateRows(result)
    }

    private func updateResultsVisibility() {
        let hasError = viewModel.queryError != nil
        let hasResults = viewModel.queryResult != nil

        resultsContainerView?.isHidden = hasError || !hasResults
        emptyStateHostingView?.isHidden = hasResults || hasError || viewModel.isExecutingQuery
        errorStateHostingView?.isHidden = !hasError

        if hasError, let error = viewModel.queryError {
            if let hostingView = errorStateHostingView as? NSHostingView<QueryErrorStateView> {
                hostingView.rootView = QueryErrorStateView(message: error)
            }
        }
    }

    private func updateConnectionButton() {
        guard let cfg = viewModel.config else { return }
        connectionButton.updateLabel(cfg.connectionName, iconName: DatabaseType(rawValue: cfg.databaseType)?.icon)
    }

    // MARK: - Observation

    private func observeViewModel() {
        withObservationTracking {
            _ = self.viewModel.queryResult
            _ = self.viewModel.isExecutingQuery
            _ = self.viewModel.queryError
            _ = self.viewModel.executionTime
            _ = self.viewModel.config
            _ = self.viewModel.isConnecting
            _ = self.viewModel.connectionError
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateResultsTable()
                self.updateResultsVisibility()
                self.updateConnectionButton()
                self.observeViewModel()
            }
        }
    }

    // MARK: - Block Menu

    @objc private func showBlockMenu(_ sender: NSButton) {
        let block = viewModel.block
        let dc = dataController
        let dismiss = { [weak self] in self?.popover?.performClose(nil) }

        let blockIndex = dc.blocks.firstIndex(where: { $0.id == block.id }) ?? 0
        let isFirst = blockIndex == 0
        let isLast = blockIndex == dc.blocks.count - 1

        let popoverVC = BlockMenuPopoverController(
            canMoveUp: !isFirst,
            canMoveDown: !isLast,
            onAddAbove: { dismiss(); dc.insertQueryBlock(at: blockIndex) },
            onAddBelow: { dismiss(); dc.insertQueryBlock(at: blockIndex + 1) },
            onMoveUp: { dismiss(); dc.moveBlockUp(block) },
            onMoveDown: { dismiss(); dc.moveBlockDown(block) },
            onDuplicate: { dismiss(); dc.duplicateBlock(block) },
            onCopy: { [weak self] in dismiss(); self?.copyBlockConfig() },
            isHiddenInDashboard: block.isHiddenInDashboard,
            onToggleDashboardVisibility: { dismiss(); dc.toggleBlockDashboardVisibility(block) },
            onDelete: { dismiss(); dc.deleteBlock(block) }
        )

        let pop = NSPopover()
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        self.popover = pop
    }

    private func copyBlockConfig() {
        let json = viewModel.block.configJSON
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    // MARK: - Appearance

    private func updateBorderColor() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            blockContainer.layer?.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.1).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
        }
    }

    private func updateOutputFieldBorder() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            outputFieldWrapper.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateBorderColor()
        updateOutputFieldBorder()
    }

    // MARK: - Cleanup

    func cleanupSession() {
        Task { await viewModel.cleanup() }
    }
}

// MARK: - CodeEditorViewControllerDelegate

extension QueryBlockController: CodeEditorViewControllerDelegate {
    func codeEditorDidChangeText(_ controller: CodeEditorViewController, text: String) {
        queryText = text
        handleQueryTextChanged(text)
    }
}

// MARK: - Query Toolbar (SwiftUI)

private struct QueryToolbarView: View {
    let viewModel: QueryBlockViewModel
    let onRun: () -> Void
    var isCollapsed: Bool
    let onToggleCollapse: () -> Void

    @State private var isCollapseHovered = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Button(action: onToggleCollapse) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isCollapseHovered ? .primary : .secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                    Text(executionSummary)
                        .font(.callout)
                        .foregroundColor(isCollapseHovered ? .primary : .secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(isCollapseHovered ? Color(.separatorColor).opacity(0.3) : .clear, in: .rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .onHover { isCollapseHovered = $0 }

            Spacer()

            Button(action: onRun) {
                HStack(spacing: 4) {
                    if viewModel.isExecutingQuery {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.horizontal, 2)
                    }
                    Text(viewModel.isExecutingQuery ? "Running" : "Run")
                    if !viewModel.isExecutingQuery {
                        Text("⌘⏎")
                            .font(.system(size: 11))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(Color(.textBackgroundColor))
                .background(Color.primaryButton)
                .cornerRadius(8)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExecutingQuery || (viewModel.config?.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, isCollapsed ? 8 : 6)
    }

    private var executionSummary: String {
        if viewModel.isConnecting {
            return "Connecting..."
        }
        if let error = viewModel.connectionError {
            return error
        }
        guard let time = viewModel.executionTime, time > 0 else { return "" }

        let timeInMs = time * 1000
        let formattedTime = timeInMs.formatted(.number.precision(.fractionLength(0)))

        if let result = viewModel.queryResult {
            let rowCount = result.rows.count
            let formattedCount = rowCount.formatted(.number)
            return "\(formattedCount) rows returned in \(formattedTime)ms"
        } else {
            return "Executed in \(formattedTime)ms"
        }
    }
}

// MARK: - Query Empty State (SwiftUI)

private struct QueryEmptyStateView: View {
    var databaseType: DatabaseType?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(databaseType == .convex ? "Write a query and press" : "Write a SQL query and press")
                    .font(.body)
                    .foregroundColor(.secondary.opacity(0.7))

                Text("⌘⏎")
                    .font(.callout)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                    .cornerRadius(4)

                Text("to execute")
                    .font(.body)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Query Error State (SwiftUI)

private struct QueryErrorStateView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Error:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)

                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Draggable Splitter

private final class QuerySplitterView: NSView {

    private let onDrag: (CGFloat) -> Void
    private var lastY: CGFloat = 0
    private let line = NSView()
    private var isDragging = false
    private var eventMonitor: Any?

    init(onDrag: @escaping (CGFloat) -> Void) {
        self.onDrag = onDrag
        super.init(frame: .zero)

        wantsLayer = true

        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    isolated deinit {
        removeEventMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, isDragging {
            cancelDrag()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        lastY = event.locationInWindow.y
        isDragging = true
        installEventMonitor()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentY = event.locationInWindow.y
        let delta = currentY - lastY
        lastY = currentY
        onDrag(delta)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        finishDrag()
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .scrollWheel, .gesture, .swipe, .magnify, .rotate]
        ) { [weak self] event in
            guard let self, self.isDragging else { return event }

            switch event.type {
            case .leftMouseUp:
                self.finishDrag()
            case .scrollWheel, .gesture, .swipe, .magnify, .rotate:
                self.cancelDrag()
            default:
                break
            }

            return event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func finishDrag() {
        isDragging = false
        removeEventMonitor()
    }

    private func cancelDrag() {
        isDragging = false
        removeEventMonitor()
    }

}
