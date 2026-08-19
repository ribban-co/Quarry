import AppKit
import Observation

/// AppKit replacement for the SwiftUI `DatabaseList`. Renders the
/// tables + functions under the sidebar's schema picker using an
/// NSOutlineView so the functions group can collapse independently.
/// Pass 1: read-only list with click-to-open, selection, hover, and
/// search filtering. Context menu, inline rename, and delete
/// confirmation come in follow-up passes.
@MainActor
final class DatabaseListViewController: NSViewController {

    // MARK: - Row Model

    fileprivate enum Row: Hashable {
        case table(name: String, schema: String?, type: String)
        case column(tableKey: String, name: String, type: String, icon: String)
        case columnStatus(tableKey: String, title: String)
        case functionsGroup
        case function(name: String, schema: String?, type: String)

        var sortKey: String {
            switch self {
            case .table(let name, _, _), .function(let name, _, _):
                return name
            case .column(_, let name, _, _), .columnStatus(_, let name):
                return name
            case .functionsGroup:
                return ""
            }
        }

        var tableKey: String? {
            switch self {
            case .table(let name, let schema, _):
                return Self.tableKey(name: name, schema: schema)
            case .column(let tableKey, _, _, _), .columnStatus(let tableKey, _):
                return tableKey
            case .functionsGroup, .function:
                return nil
            }
        }

        static func tableKey(name: String, schema: String?) -> String {
            "\(schema ?? ""):\(name)"
        }
    }

    fileprivate enum SchemaLoadState: Equatable {
        case loading
        case loaded([DatabaseSchemaInfo])
        case failed(String)
    }

    // MARK: - Dependencies

    private let instance: ConnectionInstance
    private let viewModel: SidebarViewModel

    // MARK: - Views

    private let scrollView = NSScrollView()
    private let outlineView = HoverTrackingOutlineView()
    private let emptyStateLabel = NSTextField(labelWithString: "")

    /// Fires `true` when the list has been scrolled more than the threshold
    /// from its top edge, `false` when it's back at the top. Sidebar uses
    /// this to fade the scroll-edge separator in/out.
    var onScrolledFromTopChanged: ((Bool) -> Void)?
    private var isScrolledFromTop = false
    private weak var observedClipViewForScroll: NSClipView?

    /// Bottom inset applied to the outline view's scroll area so the last
    /// rows aren't hidden behind the pro-promo overlay card.
    func setBottomContentInset(_ inset: CGFloat) {
        guard scrollView.contentInsets.bottom != inset else { return }
        var insets = scrollView.contentInsets
        insets.bottom = inset
        scrollView.contentInsets = insets
    }

    /// Mirrors the sidebar-shell's hover state so chrome bits (the Functions
    /// group header chevron) can fade in only when the user is on the
    /// sidebar — same UX as the refresh button in the controls row.
    private var isSidebarHovered = false
    func setSidebarHovered(_ hovered: Bool) {
        guard hovered != isSidebarHovered else { return }
        isSidebarHovered = hovered
        let groupRowIndex = outlineView.row(forItem: Row.functionsGroup)
        guard groupRowIndex >= 0,
              let cell = outlineView.view(atColumn: 0, row: groupRowIndex, makeIfNecessary: false) as? SidebarRowCell
        else { return }
        cell.showDisclosure = hovered
    }

    // MARK: - State

    private var tables: [Row] = []
    private var functions: [Row] = []
    private var schemaLoadStates: [String: SchemaLoadState] = [:]
    private var functionsExpanded = false
    private var renamingRow: Row?

    // MARK: - Init

    init(instance: ConnectionInstance, viewModel: SidebarViewModel) {
        self.instance = instance
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - View Lifecycle

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // Let the outline view render at its original width while pushing the
        // overlay scroller into the 4pt margin against the sidebar's right
        // edge.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -6)

        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.indentationPerLevel = 0
        outlineView.rowHeight = 34
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.selectionHighlightStyle = .none
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.focusRingType = .none
        outlineView.autoresizesOutlineColumn = false
        outlineView.style = .plain
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.isEditable = false
        column.minWidth = 0
        column.width = 100
        column.maxWidth = .greatestFiniteMagnitude
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.contextMenuProvider = { [weak self] rowIndex in
            self?.makeContextMenu(forRowIndex: rowIndex)
        }

        scrollView.documentView = outlineView

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = NSFont.preferredFont(forTextStyle: .body)
        emptyStateLabel.textColor = .tertiaryLabelColor
        emptyStateLabel.lineBreakMode = .byTruncatingTail
        emptyStateLabel.isHidden = true

        let container = NSView()
        container.addSubview(scrollView)
        container.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            emptyStateLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            emptyStateLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        self.view = container

        rebuildRows()
        startObserving()
        installScrollObserver()
    }

    private func installScrollObserver() {
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        observedClipViewForScroll = clipView
    }

    @objc private func scrollBoundsDidChange() {
        let offset = scrollView.contentView.bounds.origin.y
        let scrolled = offset > 20
        guard scrolled != isScrolledFromTop else { return }
        isScrolledFromTop = scrolled
        onScrolledFromTopChanged?(scrolled)
    }

    deinit {
        if let clipView = observedClipViewForScroll {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }
    }

    // MARK: - Data

    private func rebuildRows() {
        let connectedDB = instance.connectedDatabase?.name
        let search = viewModel.searchText
        var newTables: [Row] = []
        var newFunctions: [Row] = []

        if let dbName = connectedDB,
           let collections = instance.collections[dbName] {
            let filtered: [any CollectionWrapper] = search.isEmpty
                ? collections
                : collections.filter { $0.name.localizedStandardContains(search) }

            for col in filtered.sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }) {
                if ["function", "procedure"].contains(col.type) {
                    newFunctions.append(.function(name: col.name, schema: col.schema, type: col.type))
                } else {
                    newTables.append(.table(name: col.name, schema: col.schema, type: col.type))
                }
            }
        }

        let oldTables = tables
        let oldFunctions = functions
        tables = newTables
        functions = newFunctions

        updateEmptyState(searchText: search)

        guard oldTables != newTables || oldFunctions != newFunctions else { return }

        outlineView.reloadData()
        if functionsExpanded, !newFunctions.isEmpty {
            outlineView.expandItem(Row.functionsGroup)
        }
        refreshSelection()
    }

    private func updateEmptyState(searchText: String) {
        let isMongo = instance.connection.databaseType == .mongodb
        let entityPlural = isMongo ? "collections" : "tables"

        if tables.isEmpty && functions.isEmpty {
            if !searchText.isEmpty {
                emptyStateLabel.stringValue = "No results"
                emptyStateLabel.isHidden = false
            } else if !instance.isReady || instance.isLoadingCollections {
                // Connection is still coming up or a load is in flight —
                // suppress "No tables" so it doesn't flash before the first
                // response lands.
                emptyStateLabel.isHidden = true
            } else {
                emptyStateLabel.stringValue = "No \(entityPlural)"
                emptyStateLabel.isHidden = false
            }
        } else {
            emptyStateLabel.isHidden = true
        }
    }

    private func refreshSelection() {
        guard let selectedTab = instance.selectedTab else {
            outlineView.deselectAll(nil)
            return
        }
        let targetRow = Row.table(
            name: selectedTab.name,
            schema: selectedTab.databaseSchema,
            type: ""
        )
        // Match by name+schema regardless of type.
        let tableIndex = tables.firstIndex { row in
            if case .table(let name, let schema, _) = row {
                return name == selectedTab.name && schema == selectedTab.databaseSchema
            }
            return false
        }

        if let tableIndex {
            let rowIndex = outlineView.row(forItem: tables[tableIndex])
            if rowIndex >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
                scrollRowToVisibleIfNeeded(rowIndex)
            }
            return
        }

        // Check function rows
        if !functions.isEmpty {
            let functionIndex = functions.firstIndex { row in
                if case .function(let name, let schema, _) = row {
                    return name == selectedTab.name && schema == selectedTab.databaseSchema
                }
                return false
            }
            if let functionIndex {
                let rowIndex = outlineView.row(forItem: functions[functionIndex])
                if rowIndex >= 0 {
                    outlineView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
                    scrollRowToVisibleIfNeeded(rowIndex)
                }
                return
            }
        }

        _ = targetRow
        outlineView.deselectAll(nil)
    }

    private func isExpandableTable(_ row: Row) -> Bool {
        guard case .table(_, _, let type) = row else { return false }
        return instance.connection.databaseType != .mongodb
            && !["function", "procedure"].contains(type)
    }

    /// Scrolls the given row into view only when it's currently outside the
    /// visible rect — avoids jerky re-anchoring during ordinary selection
    /// updates on a row the user can already see.
    private func scrollRowToVisibleIfNeeded(_ rowIndex: Int) {
        guard rowIndex >= 0, rowIndex < outlineView.numberOfRows else { return }
        let rowRect = outlineView.rect(ofRow: rowIndex)
        let visibleRect = outlineView.visibleRect
        guard !visibleRect.contains(rowRect) else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            outlineView.scrollRowToVisible(rowIndex)
        }
    }

    // MARK: - Actions

    @objc private func rowClicked() {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let item = outlineView.item(atRow: clickedRow) as? Row else { return }

        switch item {
        case .table(let name, let schema, _):
            if clickedInDisclosureArea(row: clickedRow) {
                toggleTableExpansion(item)
                return
            }
            instance.createNewTab(name: name, databaseSchema: schema)
        case .column, .columnStatus:
            return
        case .functionsGroup:
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        case .function(let name, let schema, _):
            openFunction(name: name, schema: schema)
        }
    }

    private func clickedInDisclosureArea(row: Int) -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let rowRect = outlineView.rect(ofRow: row)
        // Disclosure chevron now lives on the trailing edge.
        return point.x >= rowRect.maxX - 32
    }

    private func toggleTableExpansion(_ row: Row) {
        if outlineView.isItemExpanded(row) {
            outlineView.collapseItem(row)
        } else {
            outlineView.expandItem(row)
            loadSchemaIfNeeded(for: row)
        }
    }

    private func loadSchemaIfNeeded(for row: Row) {
        guard case .table(let name, let schema, _) = row,
              let key = row.tableKey,
              schemaLoadStates[key] == nil
        else { return }

        schemaLoadStates[key] = .loading
        outlineView.reloadItem(row, reloadChildren: true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let schemaResult = try await self.instance.databaseService.getSchema(
                    for: name,
                    databaseSchema: schema
                )
                self.schemaLoadStates[key] = .loaded(schemaResult?.columns ?? [])
                self.outlineView.reloadItem(row, reloadChildren: true)
            } catch {
                self.schemaLoadStates[key] = .failed(error.localizedDescription)
                self.outlineView.reloadItem(row, reloadChildren: true)
                self.presentSchemaLoadError(error)
            }
        }
    }

    private func presentSchemaLoadError(_ error: Error) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Column Load Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in }
    }

    private func openFunction(name: String, schema: String?) {
        guard let dbName = instance.connectedDatabase?.name,
              let collections = instance.collections[dbName] else { return }
        guard let wrapper = collections.first(where: { $0.name == name && $0.schema == schema }),
              let pgWrapper = wrapper as? PostgreSQLCollectionWrapper else { return }

        let oid = pgWrapper.oid
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let definition = try await self.instance.databaseService.getFunctionDefinition(oid: oid)
                self.instance.createFunctionEditorTab(
                    name: pgWrapper.name,
                    definition: definition,
                    oid: oid,
                    schema: pgWrapper.schema
                )
            } catch {
                debugLog("Failed to load function \(pgWrapper.name): \(error)")
            }
        }
    }

    // MARK: - Context Menu

    private func makeContextMenu(forRowIndex rowIndex: Int) -> NSMenu? {
        guard let item = outlineView.item(atRow: rowIndex) as? Row else { return nil }
        return makeContextMenu(for: item)
    }

    private func makeContextMenu(for row: Row) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false

        switch row {
        case .table(let name, let schema, _):
            addItem(
                to: menu,
                title: "Open in New Tab",
                symbol: "arrow.up.forward.square",
                action: #selector(contextOpenInNewTab(_:)),
                row: row
            ).isEnabled = instance.selectedTab?.name != name
                || instance.selectedTab?.databaseSchema != schema
            menu.addItem(.separator())
            addItem(
                to: menu,
                title: "Copy Name",
                symbol: "doc.on.clipboard",
                action: #selector(contextCopyName(_:)),
                row: row
            )
            menu.addItem(.separator())
            addItem(
                to: menu,
                title: "Rename",
                symbol: "square.and.pencil",
                action: #selector(contextRename(_:)),
                row: row
            )
            addItem(
                to: menu,
                title: "Delete",
                symbol: "trash",
                action: #selector(contextDelete(_:)),
                row: row
            )
        case .column:
            addItem(
                to: menu,
                title: "Copy Name",
                symbol: "doc.on.clipboard",
                action: #selector(contextCopyName(_:)),
                row: row
            )
            menu.addItem(.separator())
            addItem(
                to: menu,
                title: "Open Structure",
                symbol: "square.stack.3d.up",
                action: #selector(contextOpenStructure(_:)),
                row: row
            )
        case .columnStatus:
            return nil
        case .function(_, _, _):
            addItem(
                to: menu,
                title: "Open in Editor",
                symbol: "arrow.up.forward.square",
                action: #selector(contextOpenFunction(_:)),
                row: row
            )
            menu.addItem(.separator())
            addItem(
                to: menu,
                title: "Copy Name",
                symbol: "doc.on.clipboard",
                action: #selector(contextCopyName(_:)),
                row: row
            )
            menu.addItem(.separator())
            addItem(
                to: menu,
                title: "Delete",
                symbol: "trash",
                action: #selector(contextDelete(_:)),
                row: row
            )
        case .functionsGroup:
            return nil
        }
        return menu
    }

    @discardableResult
    private func addItem(
        to menu: NSMenu,
        title: String,
        symbol: String?,
        action: Selector,
        row: Row
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = RowRef(row: row)
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        menu.addItem(item)
        return item
    }

    private final class RowRef: NSObject {
        let row: Row
        init(row: Row) { self.row = row }
    }

    @objc private func contextOpenInNewTab(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef,
              case .table(let name, let schema, _) = ref.row else { return }
        instance.createNewTab(name: name, databaseSchema: schema)
    }

    @objc private func contextOpenFunction(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef,
              case .function(let name, let schema, _) = ref.row else { return }
        openFunction(name: name, schema: schema)
    }

    @objc private func contextOpenStructure(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef,
              case .column(let tableKey, _, _, _) = ref.row,
              let tableRow = tables.first(where: { $0.tableKey == tableKey }),
              case .table(let name, let schema, _) = tableRow else { return }
        instance.createNewTab(name: name, databaseSchema: schema)
        instance.selectedTab?.viewMode = .schema
    }

    @objc private func contextCopyName(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef else { return }
        let name: String
        switch ref.row {
        case .table(let n, _, _), .function(let n, _, _):
            name = n
        case .column(_, let n, _, _), .columnStatus(_, let n):
            name = n
        case .functionsGroup:
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(name, forType: .string)
    }

    @objc private func contextRename(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef,
              case .table = ref.row else { return }
        beginRename(for: ref.row)
    }

    private func beginRename(for row: Row) {
        renamingRow = row
        outlineView.reloadItem(row)
    }

    private func makeInlineRenameHost(initialText: String, row: Row, schema: String?) -> NSView {
        let renameView = InlineRenameView(
            initialText: initialText,
            onCommit: { [weak self] newValue in
                self?.commitRename(originalRow: row, currentName: initialText, schema: schema, newName: newValue)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.renamingRow = nil
                self.outlineView.reloadItem(row)
            }
        )
        let host = NSHostingView(rootView: renameView)
        host.autoresizingMask = [.width, .height]
        return host
    }

    private func commitRename(originalRow: Row, currentName: String, schema: String?, newName: String) {
        renamingRow = nil

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentName else {
            // Nothing to do — restore normal row rendering.
            reloadRow(originalRow)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.instance.databaseService.renameCollection(
                    databaseSchema: schema,
                    from: currentName,
                    to: trimmed
                )
                try await self.instance.loadCollectionsForCurrentDatabase(schema: schema)
            } catch {
                self.presentRenameError(error)
                self.reloadRow(originalRow)
            }
        }
    }

    private func reloadRow(_ row: Row) {
        let index = outlineView.row(forItem: row)
        guard index >= 0 else { return }
        outlineView.reloadItem(row)
    }

    private func presentRenameError(_ error: Error) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in }
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef,
              let window = view.window else { return }

        let alert = NSAlert()
        switch ref.row {
        case .table(let name, _, let type):
            let entity = instance.connection.databaseType == .mongodb ? "Collection" : "Table"
            alert.messageText = "Delete \(entity)"
            alert.informativeText = "Are you sure you want to delete \"\(name)\"? This action cannot be undone."
            _ = type // currently unused, reserved for view vs table messaging
        case .function(let name, _, _):
            alert.messageText = "Delete Function"
            alert.informativeText = "Are you sure you want to delete \"\(name)\"? This action cannot be undone."
        case .column, .columnStatus, .functionsGroup:
            return
        }

        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performDelete(ref.row)
        }
    }

    private func performDelete(_ row: Row) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch row {
                case .table(let name, let schema, _):
                    try await self.instance.databaseService.deleteCollection(
                        named: name,
                        databaseSchema: schema
                    )
                    try await self.instance.loadCollectionsForCurrentDatabase(schema: schema)
                case .function(let name, let schema, let type):
                    try await self.deletePostgresFunction(name: name, schema: schema, type: type)
                    try await self.instance.loadCollectionsForCurrentDatabase(
                        schema: self.instance.databaseService.currentSchema
                    )
                case .column, .columnStatus, .functionsGroup:
                    return
                }
            } catch {
                self.presentDeleteError(error)
            }
        }
    }

    private func deletePostgresFunction(name: String, schema: String?, type: String) async throws {
        let schemaName = schema ?? "public"
        let dropSQL: String
        if let parenIndex = name.firstIndex(of: "(") {
            let baseName = String(name[..<parenIndex])
            let args = String(name[parenIndex...])
            dropSQL = "DROP \(type.uppercased()) IF EXISTS \"\(schemaName)\".\"\(baseName)\"\(args)"
        } else {
            dropSQL = "DROP \(type.uppercased()) IF EXISTS \"\(schemaName)\".\"\(name)\""
        }
        _ = try await instance.databaseService.executeRawQuery(dropSQL, databaseSchema: schemaName)
    }

    private func presentDeleteError(_ error: Error) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in }
    }

    // MARK: - Observation

    private func startObserving() {
        observeCollections()
        observeSelectedTab()
        observeSearch()
        observeReadiness()
        loadCollectionsIfReady()
    }

    private func observeCollections() {
        withObservationTracking {
            _ = self.instance.collections
            _ = self.instance.connectedDatabase?.name
            _ = self.instance.isLoadingCollections
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuildRows()
                self?.observeCollections()
            }
        }
    }

    /// Mirrors the old SwiftUI `DatabaseList`'s `.task(id: instance.readiness)`:
    /// when the connection becomes `.ready`, fetch collections. Postgres/MySQL/
    /// Convex incidentally re-fetch via the schema-change cascade in
    /// `DatabaseHeader`, but MongoDB and SQLite produce an empty schema list,
    /// so nothing else triggers the load — without this they show as empty.
    private func observeReadiness() {
        withObservationTracking {
            _ = self.instance.readiness
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.loadCollectionsIfReady()
                self?.rebuildRows()
                self?.observeReadiness()
            }
        }
    }

    private var pendingCollectionLoadTask: Task<Void, Never>?

    private func loadCollectionsIfReady() {
        guard case .ready = instance.readiness else { return }
        pendingCollectionLoadTask?.cancel()
        pendingCollectionLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.instance.loadCollectionsForCurrentDatabase(
                    schema: self.instance.databaseService.currentSchema
                )
            } catch is CancellationError {
                return
            } catch let error as DatabaseError where error.code == .databaseNotSelected {
                return
            } catch {
                debugLog("Failed to load collections: \(error)")
            }
        }
    }

    private func observeSelectedTab() {
        withObservationTracking {
            _ = self.instance.selectedTab?.id
            _ = self.instance.selectedTab?.name
            _ = self.instance.selectedTab?.databaseSchema
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshSelection()
                self?.observeSelectedTab()
            }
        }
    }

    private func observeSearch() {
        withObservationTracking {
            _ = self.viewModel.searchText
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuildRows()
                self?.observeSearch()
            }
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension DatabaseListViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return tables.count + (functions.isEmpty ? 0 : 1)
        }
        if let row = item as? Row,
           case .table = row,
           let key = row.tableKey {
            switch schemaLoadStates[key] {
            case .loaded(let columns):
                return max(columns.count, 1)
            case .loading, .failed, nil:
                return 1
            }
        }
        if case .functionsGroup = item as? Row {
            return functions.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            if index < tables.count {
                return tables[index]
            }
            return Row.functionsGroup
        }
        if let row = item as? Row,
           case .table = row,
           let key = row.tableKey {
            switch schemaLoadStates[key] {
            case .loaded(let columns):
                guard !columns.isEmpty else {
                    return Row.columnStatus(tableKey: key, title: "No columns")
                }
                let column = columns[index]
                return Row.column(
                    tableKey: key,
                    name: column.columnName,
                    type: column.formatType.isEmpty ? column.dataType : column.formatType,
                    icon: columnIconName(for: column)
                )
            case .failed:
                return Row.columnStatus(tableKey: key, title: "Unable to load columns")
            case .loading, nil:
                return Row.columnStatus(tableKey: key, title: "Loading columns")
            }
        }
        if case .functionsGroup = item as? Row {
            return functions[index]
        }
        return Row.functionsGroup
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if case .functionsGroup = item as? Row { return true }
        if let row = item as? Row {
            return isExpandableTable(row)
        }
        return false
    }

    private func columnIconName(for column: DatabaseSchemaInfo) -> String {
        if column.isPrimaryKey {
            return "key.fill"
        }
        if column.hasForeignKey {
            return ColumnTypeIcon.foreignKeySymbol
        }
        let type = column.formatType.isEmpty ? column.dataType : column.formatType
        return ColumnTypeIcon.icon(forType: type).symbol
    }
}

// MARK: - NSOutlineViewDelegate

extension DatabaseListViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? Row else { return nil }
        if let renamingRow, row == renamingRow, case .table(let name, let schema, _) = row {
            return makeInlineRenameHost(initialText: name, row: row, schema: schema)
        }
        switch row {
        case .table(let name, _, let type):
            let cell = dequeueSidebarCell(isExpandableTable(row) ? .tableRow : .plain, in: outlineView)
            cell.configure(
                symbolName: type == "view" ? "eye.fill" : "table",
                title: name,
                isMuted: false
            )
            cell.isExpanded = outlineView.isItemExpanded(row)
            cell.showDisclosure = cell.isExpanded
            return cell
        case .column(_, let name, let type, let icon):
            let cell = dequeueSidebarCell(.columnRow, in: outlineView)
            cell.configure(
                symbolName: icon,
                title: name,
                detail: type,
                isMuted: true
            )
            return cell
        case .columnStatus(_, let title):
            let cell = dequeueSidebarCell(.columnRow, in: outlineView)
            cell.configure(
                symbolName: nil,
                title: title,
                isMuted: true
            )
            return cell
        case .function(let name, _, let type):
            let cell = dequeueSidebarCell(.plain, in: outlineView)
            cell.configure(
                symbolName: type == "procedure" ? "gearshape" : "f.cursive",
                title: name,
                isMuted: false
            )
            return cell
        case .functionsGroup:
            let cell = dequeueSidebarCell(.groupHeader, in: outlineView)
            cell.configure(
                symbolName: nil,
                title: "Functions",
                isMuted: true
            )
            cell.showDisclosure = isSidebarHovered
            cell.isExpanded = outlineView.isItemExpanded(row)
            return cell
        }
    }

    private func dequeueSidebarCell(_ layout: SidebarRowCell.Layout, in outlineView: NSOutlineView) -> SidebarRowCell {
        if let cell = outlineView.makeView(withIdentifier: layout.reuseIdentifier, owner: nil) as? SidebarRowCell {
            return cell
        }
        return SidebarRowCell(layout: layout)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        SidebarRowView()
    }

    /// Schema-detail rows (columns) render in a tighter row so an expanded
    /// table reads as a compact list rather than full-height entries.
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let row = item as? Row else { return 34 }
        switch row {
        case .column, .columnStatus:
            return 24
        case .table, .function, .functionsGroup:
            return 34
        }
    }

    func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard let hoverTrackingView = outlineView as? HoverTrackingOutlineView,
              let sidebarRow = rowView as? SidebarRowView else { return }
        hoverTrackingView.applyHoverStateIfNeeded(to: sidebarRow, row: row)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let row = item as? Row else { return false }
        switch row {
        case .functionsGroup, .column, .columnStatus:
            return false
        case .table, .function:
            return true
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let row = item as? Row else { return true }
        if case .table = row {
            loadSchemaIfNeeded(for: row)
        }
        return true
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? Row else { return }
        switch item {
        case .functionsGroup:
            functionsExpanded = true
            refreshFunctionsGroupDisclosure()
        case .table:
            refreshTableDisclosure(for: item)
        case .column, .columnStatus, .function:
            break
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? Row else { return }
        switch item {
        case .functionsGroup:
            functionsExpanded = false
            refreshFunctionsGroupDisclosure()
        case .table:
            refreshTableDisclosure(for: item)
        case .column, .columnStatus, .function:
            break
        }
    }

    private func refreshFunctionsGroupDisclosure() {
        let groupRow = outlineView.row(forItem: Row.functionsGroup)
        guard groupRow >= 0 else { return }
        if let cell = outlineView.view(atColumn: 0, row: groupRow, makeIfNecessary: false) as? SidebarRowCell {
            cell.isExpanded = outlineView.isItemExpanded(Row.functionsGroup)
        }
    }

    private func refreshTableDisclosure(for row: Row) {
        let tableRow = outlineView.row(forItem: row)
        guard tableRow >= 0 else { return }
        if let cell = outlineView.view(atColumn: 0, row: tableRow, makeIfNecessary: false) as? SidebarRowCell {
            cell.isExpanded = outlineView.isItemExpanded(row)
        }
    }
}

// MARK: - Row View

@MainActor
final class SidebarRowView: NSTableRowView {
    /// Hover is driven by the enclosing outline view's single tracking area
    /// rather than a per-row `NSTrackingArea`, so scroll-induced stuck hover
    /// states are impossible and we never create N tracking areas for large
    /// databases.
    var isRowHovered = false { didSet { updateHighlight() } }

    private let highlightLayer = CALayer()

    override var isSelected: Bool { didSet { updateHighlight() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        highlightLayer.cornerRadius = 10
        highlightLayer.opacity = 0
        layer?.addSublayer(highlightLayer)
        applyAppearanceColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // 2pt horizontal breathing room (matches sidebar's edge insets); 1pt
        // vertical inset creates a subtle 2pt gap between consecutive hover
        // highlights without introducing explicit inter-row spacing.
        //
        // Disable CALayer's implicit frame animation so the highlight tracks
        // sidebar-resize drags in real time instead of easing behind them.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.frame = bounds.insetBy(dx: 2, dy: 1)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColor()
    }

    private func applyAppearanceColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            highlightLayer.backgroundColor = NSColor.separatorColor.cgColor
        }
    }

    /// Row views are reused across scroll — clear the hover flag so a reused
    /// view coming back into view doesn't carry stale state. The outline view
    /// will re-set it if the mouse is actually over this row.
    override func prepareForReuse() {
        super.prepareForReuse()
        isRowHovered = false
    }

    private func updateHighlight() {
        // Multiply separatorColor's native alpha by 0.5 via layer opacity so
        // it matches SwiftUI's `Color(.separatorColor).opacity(0.5)` rather
        // than baking a full 50% alpha on top of the semi-transparent base.
        let target: Float = (isSelected || isRowHovered) ? 0.5 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.opacity = target
        CATransaction.commit()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Highlight handled by highlightLayer; suppress default blue fill.
    }
}

// MARK: - Outline View with Centralized Hover Tracking

/// Owns hover tracking for the entire list so we avoid per-row
/// `NSTrackingArea` objects (which don't re-evaluate on scroll and leave
/// hover state stuck on whatever row was last under the cursor).
///
/// Cost per mouse event / scroll tick:
/// - `row(at:)` — O(log N) and early-exits when the row index hasn't changed.
/// - Exactly two row-view mutations per transition (old + new row).
/// - No per-row objects allocated.
@MainActor
final class HoverTrackingOutlineView: NSOutlineView {
    /// Closure that supplies the context menu for the row the user
    /// right-clicked. Receives the clicked row index; return `nil` for rows
    /// that shouldn't show a menu.
    var contextMenuProvider: ((Int) -> NSMenu?)?

    private var trackingArea: NSTrackingArea?
    private var hoveredRow: Int = -1
    private weak var observedClipView: NSClipView?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let rowIndex = row(at: point)
        guard rowIndex >= 0 else { return nil }
        return contextMenuProvider?(rowIndex)
    }

    /// Hide the built-in disclosure triangle that NSOutlineView draws at the
    /// leading edge of expandable rows. We render our own chevron on the
    /// trailing edge of the Functions group header, so the default one would
    /// show up as a second chevron at the start.
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let previous = observedClipView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: previous
            )
            observedClipView = nil
        }

        guard window != nil, let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        observedClipView = clipView
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func clipViewBoundsDidChange() {
        refreshHoveredRowFromCurrentMouse()
    }

    override func mouseMoved(with event: NSEvent) {
        setHoveredRow(rowIndex(for: event.locationInWindow))
    }

    override func mouseEntered(with event: NSEvent) {
        setHoveredRow(rowIndex(for: event.locationInWindow))
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredRow(-1)
    }

    /// Called after a row is scrolled into view or reassigned to a different
    /// row index via reuse. Keeps the visible highlight consistent with the
    /// cursor position without waiting for the next mouse event.
    func applyHoverStateIfNeeded(to rowView: SidebarRowView, row: Int) {
        rowView.isRowHovered = row == hoveredRow
        updateDisclosureVisibility(row: row, hovered: row == hoveredRow)
    }

    private func refreshHoveredRowFromCurrentMouse() {
        guard let window else {
            setHoveredRow(-1)
            return
        }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        setHoveredRow(rowIndex(for: windowPoint))
    }

    private func rowIndex(for windowPoint: NSPoint) -> Int {
        let pointInSelf = convert(windowPoint, from: nil)
        // row(at:) returns -1 when the point is outside any row.
        guard visibleRect.contains(pointInSelf) else { return -1 }
        return self.row(at: pointInSelf)
    }

    private func setHoveredRow(_ row: Int) {
        guard row != hoveredRow else { return }
        let previous = hoveredRow
        hoveredRow = row
        // hoveredRow can go stale across a reload; rowView(atRow:) throws on out-of-range rows.
        if previous >= 0, previous < numberOfRows,
           let view = rowView(atRow: previous, makeIfNecessary: false) as? SidebarRowView {
            view.isRowHovered = false
            updateDisclosureVisibility(row: previous, hovered: false)
        }
        if row >= 0, row < numberOfRows,
           let view = rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView {
            view.isRowHovered = true
            updateDisclosureVisibility(row: row, hovered: true)
        }
    }

    private func updateDisclosureVisibility(row: Int, hovered: Bool) {
        guard row >= 0,
              let item = item(atRow: row) as? DatabaseListViewController.Row,
              let cell = view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarRowCell
        else { return }

        switch item {
        case .table:
            cell.showDisclosure = hovered || isItemExpanded(item)
        case .functionsGroup:
            break
        case .column, .columnStatus, .function:
            cell.showDisclosure = false
        }
    }
}

// MARK: - Row Cell

@MainActor
private final class SidebarRowCell: NSView {
    /// Structural variants: constraints differ per layout, so each gets its
    /// own reuse identifier and `configure(...)` only touches content.
    enum Layout: String {
        case groupHeader
        case tableRow
        case columnRow
        case plain

        var reuseIdentifier: NSUserInterfaceItemIdentifier {
            NSUserInterfaceItemIdentifier("SidebarRowCell.\(rawValue)")
        }
    }

    private let layout: Layout
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let disclosureView = NSImageView()

    var showDisclosure: Bool = false {
        didSet { disclosureView.isHidden = !showDisclosure }
    }

    var isExpanded: Bool = false {
        didSet { updateDisclosureRotation() }
    }

    init(layout: Layout) {
        self.layout = layout
        super.init(frame: .zero)
        identifier = layout.reuseIdentifier
        // Cell's own frame is set by NSOutlineView's layout; subviews use
        // auto-layout relative to it. Leaving `translatesAutoresizingMask..`
        // at its default (true) so frame changes from the table view apply.
        autoresizingMask = [.width, .height]

        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = layout == .groupHeader
            ? NSFont.systemFont(ofSize: 11, weight: .medium)
            : NSFont.preferredFont(forTextStyle: .body)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = NSFont.preferredFont(forTextStyle: .caption2)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        disclosureView.translatesAutoresizingMaskIntoConstraints = false
        let disclosureConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        disclosureView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(disclosureConfig)
        disclosureView.contentTintColor = .tertiaryLabelColor
        disclosureView.isHidden = true
        disclosureView.wantsLayer = true

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(disclosureView)

        switch layout {
        case .groupHeader:
            // Group-header layout: [Functions text]  ···  [chevron]
            // No leading icon; chevron pinned to the trailing edge and
            // rotates 90° when expanded.
            iconView.isHidden = true
            disclosureView.isHidden = false
            showDisclosure = true

            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: disclosureView.leadingAnchor, constant: -4),

                disclosureView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                disclosureView.centerYAnchor.constraint(equalTo: centerYAnchor),
                disclosureView.widthAnchor.constraint(equalToConstant: 12),
                disclosureView.heightAnchor.constraint(equalToConstant: 12),
            ])
        case .tableRow:
            // Table-row layout: [icon] [title]  ···  [chevron]
            // The disclosure sits on the trailing edge and rotates when the
            // table's columns are expanded.
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 18),
                iconView.heightAnchor.constraint(equalToConstant: 18),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: disclosureView.leadingAnchor, constant: -4),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

                disclosureView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                disclosureView.centerYAnchor.constraint(equalTo: centerYAnchor),
                disclosureView.widthAnchor.constraint(equalToConstant: 12),
                disclosureView.heightAnchor.constraint(equalToConstant: 12),
            ])
        case .columnRow:
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 14),
                iconView.heightAnchor.constraint(equalToConstant: 14),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -6),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

                detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        case .plain:
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 18),
                iconView.heightAnchor.constraint(equalToConstant: 18),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Resets all per-row content so a cell dequeued via
    /// `makeView(withIdentifier:)` carries no state from its previous row.
    func configure(
        symbolName: String?,
        title: String,
        detail: String? = nil,
        isMuted: Bool
    ) {
        if let symbolName {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        } else {
            iconView.image = nil
        }
        iconView.contentTintColor = isMuted ? .tertiaryLabelColor : .secondaryLabelColor

        titleLabel.stringValue = title
        titleLabel.textColor = isMuted ? .secondaryLabelColor : .labelColor

        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail == nil

        showDisclosure = layout == .groupHeader
        isExpanded = false
    }

    private func updateDisclosureRotation() {
        // Swap the SF Symbol instead of rotating the view — rotating an
        // NSImageView via frameCenterRotation visually shifts the glyph
        // because the underlying image's content alignment recomputes
        // after the transform.
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        let name = isExpanded ? "chevron.down" : "chevron.right"
        disclosureView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}

// MARK: - Inline Rename (SwiftUI)

/// Mirrors the original SwiftUI `inlineRenameView` from
/// `quarry/Views/Sidebar/ConnectionDetails/DatabaseList.swift`. Hosted via
/// `NSHostingView` for the single row being renamed so the pencil icon,
/// card background, shadow, border, and Save/Cancel button styles match the
/// pre-migration design pixel-for-pixel.
import SwiftUI

struct InlineRenameView: View {
    let initialText: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @State private var isRenaming: Bool = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var hasTextChanged: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) != initialText
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.line")
                .opacity(0.7)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            TextField("Collection name", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { submit() }

            HStack(spacing: 4) {
                if hasTextChanged {
                    Button(action: submit) {
                        Text("Save").font(.callout)
                    }
                    .buttonStyle(RenameSaveButtonStyle(backgroundColor: .primaryButton))
                    .disabled(isRenaming)
                } else {
                    Button(action: { onCancel() }) {
                        Text("Cancel").font(.callout)
                    }
                    .buttonStyle(RenameCancelButtonStyle())
                    .disabled(isRenaming)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : .white)
                .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 0.5)
        )
        .onAppear {
            text = initialText
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                isFocused = true
            }
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }

    private func submit() {
        guard hasTextChanged, !isRenaming else {
            onCancel()
            return
        }
        isRenaming = true
        onCommit(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
