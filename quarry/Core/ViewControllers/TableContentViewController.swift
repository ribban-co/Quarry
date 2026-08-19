import AppKit
import Observation
import SwiftData
import SwiftUI

final class TableContentViewController: NSViewController {

    // MARK: - Dependencies

    private let tab: DatabaseTab
    private let instance: ConnectionInstance
    private let appViewModel: AppViewModel
    private let sidebarViewModel: SidebarViewModel
    private let tabManager: TabManager
    private let modelContainer: ModelContainer

    let dataController: TableDataController
    private var coordinator: TableCoordinator?

    // MARK: - Views

    private var filterBarView: FilterBuilderAppKitView?
    private var contentArea: NSView!
    private var floatingBarHostingView: NSHostingView<AnyView>?
    private var currentContentView: NSView?
    private var measuredFilterBarHeight: CGFloat?
    nonisolated(unsafe) private var filterLayoutTask: Task<Void, Never>?
    private var hasAppeared = false

    // MARK: - Notification Observers

    nonisolated(unsafe) private var markRowObserver: Any?
    nonisolated(unsafe) private var pasteObserver: Any?
    nonisolated(unsafe) private var filterToggleObserver: Any?
    nonisolated(unsafe) private var viewModeShortcutMonitor: Any?

    // MARK: - Init

    init(
        tab: DatabaseTab,
        instance: ConnectionInstance,
        appViewModel: AppViewModel,
        sidebarViewModel: SidebarViewModel,
        tabManager: TabManager,
        modelContainer: ModelContainer
    ) {
        self.tab = tab
        self.instance = instance
        self.appViewModel = appViewModel
        self.sidebarViewModel = sidebarViewModel
        self.tabManager = tabManager
        self.modelContainer = modelContainer
        if let prewarmed = instance.tableDataControllers[tab.id] {
            self.dataController = prewarmed
        } else {
            let controller = TableDataController(instance: instance, tab: tab)
            instance.tableDataControllers[tab.id] = controller
            self.dataController = controller
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        MainActor.assumeIsolated {
            dataController.cancel()
        }
        filterLayoutTask?.cancel()
        for observer in [markRowObserver, pasteObserver, filterToggleObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = viewModeShortcutMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Environment Injection

    private func injectEnvironments<V: View>(_ view: V) -> some View {
        view
            .environment(instance)
            .environment(appViewModel)
            .environment(sidebarViewModel)
            .environment(tabManager)
            .environment(\.currentDatabaseType, instance.connection.databaseType)
            .modelContainer(modelContainer)
    }

    // MARK: - View Lifecycle

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.autoresizingMask = [.width, .height]
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        self.view = root

        setupContentArea()
        // Filter bar is lazy: see ensureFilterBarMounted(). It's built on first
        // user toggle (Cmd+F) or when persisted conditions need auto-show.
        setupFloatingBar()
        setupLayout()
        setupNotifications()
        startObserving()

        // Prime the UI from any data the prewarmed controller already loaded
        // before this VC mounted. observeViewState only fires onChange, so
        // already-loaded state would otherwise sit invisible until the next
        // mutation.
        updateFilterBarFromData()
        updateTableFromData()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        hasAppeared = true
        scheduleFilterBarLayout(afterAnimation: true)
        scheduleLoadWhenConnectionIsReady()
        installViewModeShortcutMonitor()
        // Defer the floating action bar mount one tick past viewDidAppear so
        // its SwiftUI body computation doesn't compete with the table's first
        // paint. The user can't see the floating bar until rows are visible
        // anyway.
        Task { @MainActor [weak self] in
            self?.mountFloatingBarIfNeeded()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        hasAppeared = false
        filterLayoutTask?.cancel()
        dataController.cancel()
        removeViewModeShortcutMonitor()
    }

    // MARK: - ⌘E view-mode toggle

    private func installViewModeShortcutMonitor() {
        guard viewModeShortcutMonitor == nil else { return }
        viewModeShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Only act when this VC's view is the on-screen tab content in the key window.
            guard self.view.window?.isKeyWindow == true,
                  !self.view.isHiddenOrHasHiddenAncestor else { return event }

            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "e" else {
                return event
            }

            self.toggleViewMode()
            return nil
        }
    }

    private func removeViewModeShortcutMonitor() {
        if let monitor = viewModeShortcutMonitor {
            NSEvent.removeMonitor(monitor)
            viewModeShortcutMonitor = nil
        }
    }

    private func toggleViewMode() {
        // Flip between content and schema. Definition mode is currently hidden
        // in the toggle UI; treat it as content for the purpose of this shortcut.
        // Mirror ViewModeToggle's button animation so the selector pill slides
        // when the shortcut fires, instead of snapping.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tab.viewMode = (tab.viewMode == .schema) ? .content : .schema
        }
    }

    // MARK: - Setup

    private func setupContentArea() {
        contentArea = NSView()
        contentArea.wantsLayer = true
    }

    private func ensureFilterBarMounted() {
        guard filterBarView == nil else { return }
        setupFilterBar()
        if let filterBarView {
            view.addSubview(filterBarView)
            layoutContentViews()
        }
    }

    private func setupFilterBar() {
        let filterBarView = FilterBuilderAppKitView()
        filterBarView.update(
            columns: dataController.cachedSchema?.columns ?? [],
            fallbackColumns: dataController.instance.connection.databaseType == .convex && dataController.cachedSchema == nil
                ? (dataController.currentQueryResult?.columns ?? [])
                : [],
            tabID: dataController.tab.id,
            conditions: dataController.filterConditions,
            onConditionsChange: { [weak self] conditions in
                self?.dataController.filterConditions = conditions
            },
            generateFilterQuery: { [weak self] conditions in
                guard let self else { return "" }
                return self.dataController.instance.databaseService.generateFilterQuery(
                    from: conditions,
                    tableName: self.dataController.tab.name,
                    databaseSchema: self.dataController.tab.databaseSchema
                )
            },
            onApplyFilter: { [weak self] filter in
                guard let self else { return }
                let effectiveFilter: String? = filter.isEmpty ? nil : filter
                self.dataController.currentActiveFilter = effectiveFilter
                self.dataController.scheduleLoadOrSubscribe(
                    forceFetch: true,
                    fetchSchema: false,
                    page: 1,
                    limit: 300,
                    filter: effectiveFilter
                )
            },
            onLayoutInvalidated: { [weak self] in
                self?.scheduleFilterBarLayout()
            },
            onHeightChanged: { [weak self] height in
                self?.updateMeasuredFilterBarHeight(height)
            }
        )
        self.filterBarView = filterBarView
    }

    private func setupFloatingBar() {
        // Deferred: do nothing here. The NSHostingView<FloatingBarContainer>
        // is heavy to instantiate + body-compute (it's a large SwiftUI tree
        // with multiple Bindable observations). Building it during loadView
        // would push the SwiftUI body pass into the addTabViewItem layout
        // cycle, delaying the table paint. We mount it after viewDidAppear
        // — the user can't even see the floating bar until rows are painted.
    }

    private func setupLayout() {
        if let filterBarView {
            view.addSubview(filterBarView)
        }
        view.addSubview(contentArea)

        // Respect the tab's current mode at mount — a tab can be created
        // already in `.schema` (e.g. "Open Structure" from the sidebar), and
        // `observeViewMode()` only reacts to later changes.
        switchToViewMode(tab.viewMode)
        layoutContentViews()
    }

    private func mountFloatingBarIfNeeded() {
        guard floatingBarHostingView == nil else { return }
        let floatingBar = FloatingBarContainer(dataController: dataController, tab: tab)
        let wrapped = injectEnvironments(floatingBar)
        let hosting = NSHostingView(rootView: AnyView(wrapped))
        floatingBarHostingView = hosting
        view.addSubview(hosting)
        layoutContentViews()

        // Subtle fade + 3pt slide-down entrance from above. CALayer-driven so
        // it runs on the GPU and doesn't compete with the table's first paint.
        // Mount already happens after viewDidAppear, so rows are visible by
        // the time this animates. Respects the system "Reduce motion"
        // accessibility setting by dropping the slide and shortening the fade.
        hosting.wantsLayer = true
        guard let layer = hosting.layer else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let translation: CGFloat = reduceMotion ? 0 : -3
        let duration = reduceMotion ? 0.12 : 0.18

        layer.opacity = 0
        layer.transform = CATransform3DMakeTranslation(0, translation, 0)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1

        let group: CAAnimationGroup = {
            let g = CAAnimationGroup()
            if reduceMotion {
                g.animations = [fade]
            } else {
                let slide = CABasicAnimation(keyPath: "transform")
                slide.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, translation, 0))
                slide.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                g.animations = [fade, slide]
            }
            g.duration = duration
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            g.fillMode = .forwards
            return g
        }()

        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        layer.add(group, forKey: "floatingBarEntrance")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutContentViews()
    }

    private func layoutContentViews() {
        let bounds = view.bounds
        let filterHeight: CGFloat
        if let filterBarView {
            var measurementFrame = filterBarView.frame
            measurementFrame.size.width = bounds.width
            filterBarView.frame = measurementFrame
            filterBarView.layoutSubtreeIfNeeded()
            let measuredHeight = max(0, filterBarView.resolvedHeight.rounded(.up))
            filterHeight = measuredFilterBarHeight ?? measuredHeight

            filterBarView.frame = NSRect(
                x: 0,
                y: bounds.height - filterHeight,
                width: bounds.width,
                height: filterHeight
            )
        } else {
            filterHeight = 0
        }

        let contentHeight = max(0, bounds.height - filterHeight)

        contentArea.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: contentHeight
        )

        floatingBarHostingView?.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: contentHeight
        )
    }

    private func setupNotifications() {
        markRowObserver = NotificationCenter.default.addObserver(
            forName: .markRowAsDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let rowIndex = userInfo["rowIndex"] as? Int,
                  let tableName = userInfo["tableName"] as? String else { return }
            Task { @MainActor in
                self.dataController.handleMarkRowAsDeleted(rowIndex: rowIndex, tableName: tableName)
            }
        }

        pasteObserver = NotificationCenter.default.addObserver(
            forName: .didRequestPaste,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dataController.handlePasteRows()
            }
        }

        // Lazy filter bar: mount on first toggle for this tab, then let the
        // bar's own observer take over for subsequent toggles. Tab IDs are
        // globally unique UUIDs, so matching on tabID alone is sufficient.
        filterToggleObserver = NotificationCenter.default.addObserver(
            forName: .toggleFilterBuilder,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let notificationTabID = notification.userInfo?["tabID"] as? UUID
            MainActor.assumeIsolated {
                guard let self,
                      self.filterBarView == nil,
                      notificationTabID == self.tab.id
                else { return }
                self.ensureFilterBarMounted()
                self.filterBarView?.showBuilder()
            }
        }
    }

    // MARK: - Content Mode Switching

    private func showContentMode() {
        currentContentView?.removeFromSuperview()

        let tableCoordinator = TableCoordinator(
            schema: dataController.cachedSchema,
            queryResult: dataController.currentQueryResult,
            tableName: tab.name,
            onSort: { [weak self] column, ascending in
                guard let self else { return }
                self.dataController.sortColumn = column.isEmpty ? nil : column
                self.dataController.sortAscending = ascending
                self.dataController.scheduleLoadOrSubscribe(
                    forceFetch: true,
                    fetchSchema: false,
                    page: 1,
                    limit: 300,
                    filter: self.dataController.currentActiveFilter
                )
            },
            modificationTracker: dataController.modificationTracker,
            onDeleteNewRow: { [weak self] index in
                self?.dataController.deleteNewlyAddedRecord(atIndex: index)
                self?.dataController.needsToSelectLastRow = false
            },
            onForeignKeyNavigation: { [weak self] tableName, columnName, value in
                guard let self else { return }
                self.instance.createNewTab(name: tableName, filterColumn: columnName, filterValue: value, databaseSchema: self.tab.databaseSchema)
            },
            highlightedFields: dataController.updatedFields,
            highlightedRows: dataController.updatedRows,
            cacheNamespace: instance.connection.persistentModelID.storeIdentifier ?? "",
            onRowSelected: { [weak self] rowData in
                self?.tab.selectedRowData = rowData
            },
            onUndoRowInsert: { [weak self] rowIndex in
                self?.dataController.undoRowInsert(atIndex: rowIndex)
            }
        )
        tableCoordinator.currentTab = tab

        self.coordinator = tableCoordinator

        let tableContainer = tableCoordinator.setupTableView()
        tableContainer.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(tableContainer)

        NSLayoutConstraint.activate([
            tableContainer.topAnchor.constraint(equalTo: contentArea.topAnchor),
            tableContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            tableContainer.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            tableContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        currentContentView = tableContainer
    }

    private func showSchemaMode() {
        // Lazy-fetch indexes the first time the user enters schema mode.
        // Skipped on table open to keep the hot path lean (TablePlus parity).
        dataController.loadIndexesIfNeeded()
        let schemaView = SchemaModeView(
            schema: dataController.cachedSchema,
            indexes: dataController.cachedIndexes,
            tableName: tab.name,
            schemaName: tab.databaseSchema,
            modificationTracker: Binding(
                get: { [weak self] in self?.dataController.schemaModificationTracker ?? SchemaModificationTracker() },
                set: { [weak self] in self?.dataController.schemaModificationTracker = $0 }
            )
        )
        showSwiftUIContent(schemaView)
    }

    private func showDefinitionMode() {
        let defView = DefinitionModeView(
            schema: dataController.cachedSchema,
            tableName: tab.name
        )
        showSwiftUIContent(defView)
    }

    private func showSwiftUIContent(_ content: some View) {
        currentContentView?.removeFromSuperview()
        coordinator = nil

        let wrapped = injectEnvironments(content)
        let hostingView = NSHostingView(rootView: AnyView(wrapped))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: contentArea.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        currentContentView = hostingView
    }

    private func switchToViewMode(_ mode: DatabaseTab.ViewMode) {
        switch mode {
        case .content:
            showContentMode()
        case .schema:
            showSchemaMode()
        case .definition:
            showDefinitionMode()
        }
    }

    // MARK: - Observation

    private func startObserving() {
        observeConnectionReadiness()
        observeViewState()
        observeViewMode()
        observeHighlighting()
        observeFilterBarState()
        observeErrors()
    }

    private func scheduleFilterBarLayout(afterAnimation: Bool = false) {
        filterLayoutTask?.cancel()
        filterLayoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.filterBarView?.needsLayout = true
            self.layoutContentViews()
            await Task.yield()
            self.filterBarView?.needsLayout = true
            self.layoutContentViews()
            if afterAnimation {
                try? await Task.sleep(for: .milliseconds(250))
                self.filterBarView?.needsLayout = true
                self.layoutContentViews()
            }
        }
    }

    private func updateMeasuredFilterBarHeight(_ height: CGFloat) {
        let resolvedHeight = max(0, height.rounded(.up))

        if resolvedHeight == 0 {
            if measuredFilterBarHeight == nil {
                return
            }

            measuredFilterBarHeight = nil
            layoutContentViews()
            return
        }

        if let measuredFilterBarHeight, abs(measuredFilterBarHeight - resolvedHeight) < 0.5 {
            return
        }

        measuredFilterBarHeight = resolvedHeight
        layoutContentViews()
    }

    private func observeViewState() {
        withObservationTracking {
            _ = self.dataController.viewState
            _ = self.dataController.cachedDocuments
            _ = self.dataController.cachedSchema
            _ = self.dataController.cachedIndexes
            _ = self.dataController.needsToSelectLastRow
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tab.viewMode == .schema {
                    self.showSchemaMode()
                } else {
                    self.updateTableFromData()
                }
                self.observeViewState()
            }
        }
    }

    private func observeConnectionReadiness() {
        withObservationTracking {
            _ = self.instance.readiness
            _ = self.instance.connectionGeneration
            _ = self.tab.name
            _ = self.tab.databaseSchema
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleLoadWhenConnectionIsReady()
                self.observeConnectionReadiness()
            }
        }
    }

    private func scheduleLoadWhenConnectionIsReady() {
        guard hasAppeared, instance.isReady else { return }

        dataController.updateFilterConditions()
        updateFilterBarFromData()
        dataController.scheduleLoadDocumentsIfNeeded()
    }

    private func observeFilterBarState() {
        withObservationTracking {
            _ = self.dataController.filterConditions
            _ = self.dataController.cachedSchema
            _ = self.dataController.currentQueryResult
            _ = self.tab.name
            _ = self.tab.databaseSchema
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateFilterBarFromData()
                self?.observeFilterBarState()
            }
        }
    }

    private func observeViewMode() {
        withObservationTracking {
            _ = self.tab.viewMode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.switchToViewMode(self.tab.viewMode)
                self.observeViewMode()
            }
        }
    }

    private func observeHighlighting() {
        withObservationTracking {
            _ = self.dataController.updatedFields
            _ = self.dataController.updatedRows
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.coordinator?.updateHighlighting(
                    fields: self.dataController.updatedFields,
                    rows: self.dataController.updatedRows
                )
                self.observeHighlighting()
            }
        }
    }

    private func observeErrors() {
        withObservationTracking {
            _ = self.dataController.showingErrorAlert
            _ = self.dataController.showingViewStateError
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.dataController.showingErrorAlert, let error = self.dataController.currentError {
                    self.showNSAlert(title: "Operation Failed", message: error.localizedDescription)
                    self.dataController.showingErrorAlert = false
                }
                if self.dataController.showingViewStateError {
                    self.showNSAlert(title: "Error", message: self.dataController.viewStateErrorMessage)
                    self.dataController.showingViewStateError = false
                }
                self.observeErrors()
            }
        }
    }

    private func showNSAlert(title: String, message: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func updateTableFromData() {
        guard let coordinator else { return }

        if dataController.needsToSelectLastRow {
            coordinator.needsToSelectLastRow = true
        }
        coordinator.currentTab = tab
        coordinator.updateRows(dataController.currentQueryResult, newSchema: dataController.cachedSchema)
        coordinator.updateHighlighting(fields: dataController.updatedFields, rows: dataController.updatedRows)

        dataController.handleViewStateChange()
    }

    private func updateFilterBarFromData() {
        if filterBarView == nil {
            let needsAutoShow = dataController.filterConditions.contains {
                !$0.field.isEmpty && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard needsAutoShow else { return }
            ensureFilterBarMounted()
        }
        filterBarView?.update(
            columns: dataController.cachedSchema?.columns ?? [],
            fallbackColumns: dataController.instance.connection.databaseType == .convex && dataController.cachedSchema == nil
                ? (dataController.currentQueryResult?.columns ?? [])
                : [],
            tabID: dataController.tab.id,
            conditions: dataController.filterConditions,
            onConditionsChange: { [weak self] conditions in
                self?.dataController.filterConditions = conditions
            },
            generateFilterQuery: { [weak self] conditions in
                guard let self else { return "" }
                return self.dataController.instance.databaseService.generateFilterQuery(
                    from: conditions,
                    tableName: self.dataController.tab.name,
                    databaseSchema: self.dataController.tab.databaseSchema
                )
            },
            onApplyFilter: { [weak self] filter in
                guard let self else { return }
                let effectiveFilter: String? = filter.isEmpty ? nil : filter
                self.dataController.currentActiveFilter = effectiveFilter
                self.dataController.scheduleLoadOrSubscribe(
                    forceFetch: true,
                    fetchSchema: false,
                    page: 1,
                    limit: 300,
                    filter: effectiveFilter
                )
            },
            onLayoutInvalidated: { [weak self] in
                self?.scheduleFilterBarLayout()
            },
            onHeightChanged: { [weak self] height in
                self?.updateMeasuredFilterBarHeight(height)
            }
        )
    }
}

// MARK: - SwiftUI Bridge Views

private struct FloatingBarContainer: View {
    @Bindable var dataController: TableDataController
    @Bindable var tab: DatabaseTab

    var body: some View {
        FloatingActionBar(
            tabID: tab.id,
            viewState: dataController.viewState,
            tableName: tab.name,
            tabViewMode: $tab.viewMode,
            modificationTracker: dataController.modificationTracker,
            isProcessingUpdates: dataController.isProcessingUpdates,
            onRefresh: { currentPage, itemsPerPage, fetchSchema in
                dataController.scheduleLoadOrSubscribe(
                    forceFetch: true,
                    fetchSchema: fetchSchema,
                    page: currentPage,
                    limit: itemsPerPage,
                    filter: dataController.currentActiveFilter
                )
            },
            onLoadDocuments: { filter in
                dataController.scheduleLoadOrSubscribe(
                    forceFetch: true,
                    fetchSchema: false,
                    page: 1,
                    limit: 300,
                    filter: filter
                )
            },
            onCommitModifications: {
                Task {
                    dataController.isProcessingUpdates = true
                    await dataController.commitModifications()
                    dataController.isProcessingUpdates = false
                }
            },
            onNewRecord: {
                dataController.handleNewRecord()
            },
            onDiscardChanges: {
                dataController.handleDiscardChanges()
            },
            databaseType: dataController.instance.databaseType,
            currentQueryResult: dataController.currentQueryResult,
            schema: dataController.cachedSchema,
            totalRowCount: dataController.totalRowCount,
            schemaModificationTracker: dataController.schemaModificationTracker,
            onCommitSchemaModifications: {
                Task {
                    dataController.isProcessingSchemaUpdates = true
                    await dataController.commitSchemaModifications()
                    dataController.isProcessingSchemaUpdates = false
                }
            },
            onNewField: {
                dataController.handleNewField()
            },
            onCancelLoad: {
                dataController.cancelActiveLoad()
            }
        )
        .padding(.bottom, 6)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
