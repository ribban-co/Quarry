import AppKit
import Observation

@MainActor
final class RowDetailSidebarViewController: NSViewController {

    private let instance: ConnectionInstance

    private let contentContainer = NSView()
    private let scrollView = NSScrollView()
    private let contentStackView = NSStackView()
    private let fieldsStackView = NSStackView()
    private let actionsContainerView = NSView()
    private let emptyStateStackView = NSStackView()

    nonisolated(unsafe) private var appearanceObserver: NSObjectProtocol?
    nonisolated(unsafe) private var copiedResetTask: Task<Void, Never>?

    private var isEditing = false
    private var editedValues: [String: String] = [:]
    private var isSaving = false
    private var saveError: String?
    private var isActionsExpanded = true
    private var isCopied = false
    private var isConfirmingDelete = false
    private var isDeleting = false
    private var deleteError: String?

    init(instance: ConnectionInstance) {
        self.instance = instance
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
        copiedResetTask?.cancel()
    }

    private var hasLoadedInitialContent = false
    private var needsReloadOnAttach = false

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 10
        rootView.layer?.masksToBounds = true
        view = rootView

        setupLayout()
        scrollView.isHidden = true
        emptyStateStackView.isHidden = true
        setupObservation()
        setupAppearanceObservation()
        updateBackgroundColor()
    }

    func loadInitialContent() {
        guard !hasLoadedInitialContent else { return }
        hasLoadedInitialContent = true
        reloadContent(preserveScrollOffset: false)
    }

    private func setupLayout() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedSidebarContentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        contentStackView.orientation = .vertical
        contentStackView.alignment = .leading
        contentStackView.spacing = 0
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        fieldsStackView.orientation = .vertical
        fieldsStackView.alignment = .leading
        fieldsStackView.spacing = 0
        fieldsStackView.translatesAutoresizingMaskIntoConstraints = false

        actionsContainerView.translatesAutoresizingMaskIntoConstraints = false

        contentStackView.addArrangedSubview(fieldsStackView)
        contentStackView.addArrangedSubview(actionsContainerView)
        documentView.addSubview(contentStackView)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        emptyStateStackView.orientation = .vertical
        emptyStateStackView.alignment = .centerX
        emptyStateStackView.spacing = 12
        emptyStateStackView.translatesAutoresizingMaskIntoConstraints = false

        let emptyIcon = NSImageView()
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        emptyIcon.image = NSImage(
            systemSymbolName: "rectangle.and.text.magnifyingglass",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 28, weight: .regular))
        emptyIcon.contentTintColor = .tertiaryLabelColor
        emptyIcon.imageScaling = .scaleProportionallyUpOrDown

        let emptyLabel = NSTextField(labelWithString: "Select a row to view details")
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 12, weight: .regular)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        emptyStateStackView.addArrangedSubview(emptyIcon)
        emptyStateStackView.addArrangedSubview(emptyLabel)

        view.addSubview(contentContainer)
        contentContainer.addSubview(scrollView)
        contentContainer.addSubview(emptyStateStackView)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -16),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            emptyStateStackView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            emptyStateStackView.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            emptyStateStackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainer.leadingAnchor, constant: 16),
            emptyStateStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -16),
        ])

        fieldsStackView.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
        actionsContainerView.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
    }

    private func setupObservation() {
        observeSelectedRow()
    }

    private func observeSelectedRow() {
        withObservationTracking {
            _ = self.instance.selectedTab
            _ = self.instance.selectedTab?.selectedRowData
            _ = self.instance.selectedTab?.selectedRawRowData
            _ = self.instance.selectedTab?.selectedColumnOrder
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.resetTransientState()
                self.reloadContent(preserveScrollOffset: false)
                self.observeSelectedRow()
            }
        }
    }

    private func setupAppearanceObservation() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .appAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateBackgroundColor()
                self.reloadContent()
            }
        }
    }

    private func updateBackgroundColor() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.view.layer?.backgroundColor = NSColor.clear.cgColor
            self.view.layer?.borderColor = NSColor.clear.cgColor
            self.view.layer?.borderWidth = 0
        }
    }

    private func reloadContent(preserveScrollOffset: Bool = true) {
        // The container keeps this controller cached while the Chat panel is
        // displayed; skip full field rebuilds while detached and catch up once
        // the view is reattached.
        guard view.window != nil else {
            needsReloadOnAttach = true
            return
        }
        performReload(preserveScrollOffset: preserveScrollOffset)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if needsReloadOnAttach {
            needsReloadOnAttach = false
            performReload(preserveScrollOffset: false)
        }
    }

    private func performReload(preserveScrollOffset: Bool) {
        let scrollOrigin = scrollView.contentView.bounds.origin
        let rowData = instance.selectedTab?.selectedRowData ?? [:]
        let hasSelection = !rowData.isEmpty

        scrollView.isHidden = !hasSelection
        emptyStateStackView.isHidden = hasSelection

        guard hasSelection else { return }

        rebuildFields(using: rowData)
        rebuildActionsSection()

        view.layoutSubtreeIfNeeded()

        if preserveScrollOffset {
            scrollView.contentView.scroll(to: scrollOrigin)
        } else {
            scrollView.contentView.scroll(to: .zero)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func rebuildFields(using rowData: [String: QueryRowInfo]) {
        clearArrangedSubviews(in: fieldsStackView)

        for key in orderedKeys(for: rowData) {
            guard let info = rowData[key] else { continue }
            let displayText = editedValues[key] ?? displayValue(for: info)
            let fieldView = RowDetailFieldRowView(
                columnName: key,
                rowInfo: info,
                value: displayText,
                isEditing: isEditing
            ) { [weak self] updatedValue in
                self?.editedValues[key] = updatedValue
            }
            fieldsStackView.addArrangedSubview(fieldView)
            fieldView.widthAnchor.constraint(equalTo: fieldsStackView.widthAnchor).isActive = true
        }
    }

    private func rebuildActionsSection() {
        clearSubviews(in: actionsContainerView)

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        actionsContainerView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: actionsContainerView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: actionsContainerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: actionsContainerView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: actionsContainerView.bottomAnchor),
        ])

        let headerButton = SidebarDisclosureButton(title: "ACTIONS", isExpanded: isActionsExpanded) { [weak self] in
            guard let self else { return }
            self.isActionsExpanded.toggle()
            self.reloadContent()
        }
        stackView.addArrangedSubview(headerButton)
        headerButton.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 12).isActive = true
        headerButton.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -24).isActive = true

        guard isActionsExpanded else { return }

        let buttonsStack = NSStackView()
        buttonsStack.orientation = .vertical
        buttonsStack.alignment = .leading
        buttonsStack.spacing = 5
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(buttonsStack)
        buttonsStack.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        for button in actionButtons() {
            buttonsStack.addArrangedSubview(button)
            button.leadingAnchor.constraint(equalTo: buttonsStack.leadingAnchor, constant: 12).isActive = true
            button.widthAnchor.constraint(equalTo: buttonsStack.widthAnchor, constant: -24).isActive = true
        }

        if let errorText = saveError ?? deleteError {
            let errorLabel = NSTextField(wrappingLabelWithString: errorText)
            errorLabel.translatesAutoresizingMaskIntoConstraints = false
            errorLabel.font = .systemFont(ofSize: 11, weight: .regular)
            errorLabel.textColor = .systemRed
            stackView.addArrangedSubview(errorLabel)
            errorLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -24).isActive = true
            errorLabel.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 12).isActive = true
        }
    }

    private func actionButtons() -> [SidebarActionButton] {
        if isEditing {
            return [
                SidebarActionButton(
                    title: isSaving ? "Saving..." : "Save Changes",
                    style: .primary,
                    isEnabled: !isSaving
                ) { [weak self] in
                    self?.saveChanges()
                },
                SidebarActionButton(
                    title: "Cancel",
                    style: .normal,
                    isEnabled: !isSaving
                ) { [weak self] in
                    self?.cancelEditing()
                },
            ]
        }

        if isConfirmingDelete {
            return [
                SidebarActionButton(
                    title: isDeleting ? "Deleting..." : "Confirm Delete",
                    style: .destructivePrimary,
                    isEnabled: !isDeleting
                ) { [weak self] in
                    self?.executeDelete()
                },
                SidebarActionButton(
                    title: "Cancel",
                    style: .normal,
                    isEnabled: !isDeleting
                ) { [weak self] in
                    self?.cancelDelete()
                },
            ]
        }

        return [
            SidebarActionButton(
                title: "Edit",
                systemImageName: "pencil.line",
                style: .normal
            ) { [weak self] in
                self?.startEditing()
            },
            SidebarActionButton(
                title: isCopied ? "Copied!" : "Copy as JSON",
                systemImageName: isCopied ? "checkmark" : "doc.plaintext",
                style: .normal
            ) { [weak self] in
                self?.copyRowAsJSON()
            },
            SidebarActionButton(
                title: "Delete",
                systemImageName: "trash",
                style: .destructive
            ) { [weak self] in
                self?.confirmDelete()
            },
        ]
    }

    private func startEditing() {
        guard let rowData = instance.selectedTab?.selectedRowData else { return }

        editedValues = [:]
        for (key, info) in rowData {
            editedValues[key] = displayValue(for: info)
        }
        saveError = nil
        deleteError = nil
        isConfirmingDelete = false
        isEditing = true
        reloadContent()
    }

    private func cancelEditing() {
        editedValues = [:]
        saveError = nil
        isEditing = false
        reloadContent()
    }

    private func confirmDelete() {
        deleteError = nil
        saveError = nil
        editedValues = [:]
        isEditing = false
        isConfirmingDelete = true
        reloadContent()
    }

    private func cancelDelete() {
        deleteError = nil
        isConfirmingDelete = false
        reloadContent()
    }

    private func saveChanges() {
        guard let tab = instance.selectedTab,
              let rowData = tab.selectedRowData,
              let rawRowData = tab.selectedRawRowData,
              let columnOrder = tab.selectedColumnOrder
        else {
            return
        }

        guard let id = selectedRowRecordID(from: rawRowData, columnOrder: columnOrder) else {
            saveError = "Cannot find row identifier"
            reloadContent()
            return
        }

        var updateData: [String: Any] = [:]
        for (key, stringValue) in editedValues {
            guard let originalInfo = rowData[key] else { continue }
            let originalValue = displayValue(for: originalInfo)
            if stringValue != originalValue {
                updateData[key] = convertToOriginalType(stringValue, dataType: originalInfo.dataType)
            }
        }

        guard !updateData.isEmpty else {
            isEditing = false
            reloadContent()
            return
        }

        isSaving = true
        saveError = nil
        reloadContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.instance.databaseService.updateDocument(
                    in: tab.name,
                    databaseSchema: tab.databaseSchema,
                    id: id,
                    data: updateData
                )

                self.isSaving = false
                self.isEditing = false
                self.editedValues = [:]
                self.reloadContent()
                NotificationCenter.default.post(
                    name: .tableRefresh,
                    object: nil,
                    userInfo: ["tableName": tab.name]
                )
            } catch {
                self.isSaving = false
                self.saveError = error.localizedDescription
                self.reloadContent()
            }
        }
    }

    private func executeDelete() {
        guard let tab = instance.selectedTab,
              let rawRowData = tab.selectedRawRowData,
              let columnOrder = tab.selectedColumnOrder
        else {
            return
        }

        guard let id = selectedRowRecordID(from: rawRowData, columnOrder: columnOrder) else {
            deleteError = "Cannot find row identifier"
            reloadContent()
            return
        }

        isDeleting = true
        deleteError = nil
        reloadContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.instance.databaseService.deleteDocument(
                    in: tab.name,
                    databaseSchema: tab.databaseSchema,
                    id: id
                )

                self.isDeleting = false
                self.isConfirmingDelete = false
                self.instance.selectedTab?.selectedRowIndex = nil
                self.instance.selectedTab?.selectedRowData = nil
                self.instance.selectedTab?.selectedRawRowData = nil
                self.reloadContent(preserveScrollOffset: false)
                NotificationCenter.default.post(
                    name: .tableRefresh,
                    object: nil,
                    userInfo: ["tableName": tab.name]
                )
            } catch {
                self.isDeleting = false
                self.deleteError = error.localizedDescription
                self.reloadContent()
            }
        }
    }

    private func copyRowAsJSON() {
        guard let rowData = instance.selectedTab?.selectedRowData else { return }

        saveError = nil
        deleteError = nil

        var jsonDict: [String: Any] = [:]
        for (key, info) in rowData {
            jsonDict[key] = info.value.map(jsonCompatibleValue) ?? NSNull()
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(jsonString, forType: .string)

            copiedResetTask?.cancel()
            isCopied = true
            reloadContent()

            copiedResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled else { return }
                self.isCopied = false
                self.reloadContent()
            }
        } catch {
            saveError = error.localizedDescription
            reloadContent()
        }
    }

    private func resetTransientState() {
        copiedResetTask?.cancel()
        copiedResetTask = nil
        isEditing = false
        editedValues = [:]
        isSaving = false
        saveError = nil
        isCopied = false
        isConfirmingDelete = false
        isDeleting = false
        deleteError = nil
    }

    private func orderedKeys(for rowData: [String: QueryRowInfo]) -> [String] {
        if let columnOrder = instance.selectedTab?.selectedColumnOrder {
            return columnOrder.filter { rowData.keys.contains($0) }
        }
        return Array(rowData.keys)
    }

    private func displayValue(for info: QueryRowInfo) -> String {
        guard let value = info.value else {
            return "NULL"
        }

        switch value {
        case .null:
            return "NULL"
        case .string(let stringValue), .decimalString(let stringValue), .objectID(let stringValue):
            return stringValue.isEmpty ? "(empty)" : stringValue
        case .int(let intValue):
            return String(intValue)
        case .int64(let intValue):
            return String(intValue)
        case .double(let doubleValue):
            return doubleValue.formatted()
        case .bool(let boolValue):
            return boolValue ? "true" : "false"
        case .date(let dateValue):
            return dateValue.formatted(date: .abbreviated, time: .standard)
        case .array(let arrayValue):
            return formatJSON(arrayValue.map(jsonCompatibleValue))
        case .object(let objectValue):
            return formatJSON(objectValue.mapValues(jsonCompatibleValue))
        case .uuid(let uuidValue):
            return uuidValue.uuidString
        case .data(let dataValue):
            return dataValue.base64EncodedString()
        }
    }

    private func convertToOriginalType(_ value: String, dataType: String) -> Any {
        let normalizedType = dataType.lowercased()

        if value == "NULL" || value.isEmpty {
            return NSNull()
        }

        if normalizedType.contains("int") || normalizedType.contains("serial") {
            return Int(value) ?? value
        }

        if normalizedType.contains("double")
            || normalizedType.contains("float")
            || normalizedType.contains("decimal")
            || normalizedType.contains("numeric")
            || normalizedType.contains("real")
        {
            return Double(value) ?? value
        }

        if normalizedType.contains("bool") {
            return value.lowercased() == "true"
        }

        return value
    }

    private func selectedRowRecordID(from rawRowData: DatabaseRawRow, columnOrder: [String]) -> DatabaseRecordID? {
        if let value = rawRowData["_id"] ?? nil {
            return DatabaseRecordID(columnName: "_id", value: value)
        }
        if let value = rawRowData["id"] ?? nil {
            return DatabaseRecordID(columnName: "id", value: value)
        }
        guard let firstColumn = columnOrder.first,
              let value = rawRowData[firstColumn] ?? nil
        else {
            return nil
        }
        return DatabaseRecordID(columnName: firstColumn, value: value)
    }

    private func jsonCompatibleValue(_ value: DatabaseValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let boolValue):
            return boolValue
        case .int(let intValue):
            return intValue
        case .int64(let intValue):
            return intValue
        case .double(let doubleValue):
            return doubleValue
        case .string(let stringValue), .decimalString(let stringValue), .objectID(let stringValue):
            return stringValue
        case .date(let dateValue):
            return dateValue.ISO8601Format()
        case .data(let dataValue):
            return dataValue.base64EncodedString()
        case .uuid(let uuidValue):
            return uuidValue.uuidString
        case .array(let values):
            return values.map(jsonCompatibleValue)
        case .object(let values):
            return values.mapValues(jsonCompatibleValue)
        }
    }

    private func formatJSON(_ value: Any) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? String(describing: value)
        } catch {
            return String(describing: value)
        }
    }

    private func clearArrangedSubviews(in stackView: NSStackView) {
        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
    }

    private func clearSubviews(in view: NSView) {
        for subview in view.subviews {
            subview.removeFromSuperview()
        }
    }
}

@MainActor
private final class RowDetailFieldRowView: NSView {

    private let valueContainer = NSView()
    private let isEditing: Bool

    init(
        columnName: String,
        rowInfo: QueryRowInfo,
        value: String,
        isEditing: Bool,
        onValueChange: @escaping (String) -> Void
    ) {
        self.isEditing = isEditing
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let containerStack = NSStackView()
        containerStack.orientation = .vertical
        containerStack.alignment = .leading
        containerStack.spacing = 4
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerStack)

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: columnName)
        nameLabel.font = .systemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let typeLabel = NSTextField(labelWithString: rowInfo.dataType)
        typeLabel.font = .systemFont(ofSize: 11, weight: .regular)
        typeLabel.textColor = .tertiaryLabelColor

        titleRow.addArrangedSubview(nameLabel)
        titleRow.addArrangedSubview(spacer)
        titleRow.addArrangedSubview(typeLabel)

        valueContainer.translatesAutoresizingMaskIntoConstraints = false
        valueContainer.wantsLayer = true
        valueContainer.layer?.cornerRadius = 10
        updateAppearance()

        let valueTextView = SidebarValueTextView()
        valueTextView.translatesAutoresizingMaskIntoConstraints = false
        valueTextView.string = value
        valueTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        valueTextView.isEditable = isEditing
        valueTextView.isSelectable = true
        valueTextView.textColor = (!isEditing && rowInfo.value == nil) ? .tertiaryLabelColor : .labelColor
        valueTextView.onTextChange = onValueChange

        valueContainer.addSubview(valueTextView)
        containerStack.addArrangedSubview(titleRow)
        containerStack.addArrangedSubview(valueContainer)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            titleRow.widthAnchor.constraint(equalTo: containerStack.widthAnchor),
            valueContainer.widthAnchor.constraint(equalTo: containerStack.widthAnchor),

            valueTextView.topAnchor.constraint(equalTo: valueContainer.topAnchor),
            valueTextView.leadingAnchor.constraint(equalTo: valueContainer.leadingAnchor),
            valueTextView.trailingAnchor.constraint(equalTo: valueContainer.trailingAnchor),
            valueTextView.bottomAnchor.constraint(equalTo: valueContainer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            valueContainer.layer?.backgroundColor = (
                isEditing
                ? NSColor.sidebarEditingFieldFill
                : NSColor.sidebarReadOnlyFieldFill
            ).cgColor
            valueContainer.layer?.borderWidth = 0
            valueContainer.layer?.borderColor = nil
        }
    }
}

@MainActor
private final class SidebarValueTextView: NSTextView {

    var onTextChange: ((String) -> Void)?

    init() {
        let textContainer = NSTextContainer()
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        super.init(frame: .zero, textContainer: textContainer)

        isRichText = false
        importsGraphics = false
        drawsBackground = false
        isHorizontallyResizable = false
        isVerticallyResizable = true
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        minSize = NSSize(width: 0, height: 36)
        allowsUndo = true
        textContainerInset = NSSize(width: 10, height: 8)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byCharWrapping
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer, bounds.width > 0 else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 36)
        }

        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(36, ceil(usedHeight + textContainerInset.height * 2))
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
        onTextChange?(string)
    }
}

private final class SidebarActionButton: NSButton {

    override class var cellClass: AnyClass? {
        get { SidebarActionButtonCell.self }
        set {}
    }

    enum Style {
        case normal
        case primary
        case destructive
        case destructivePrimary
    }

    private let style: Style
    private let baseTitle: String
    private let systemImageName: String?
    private let handler: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(
        title: String,
        systemImageName: String? = nil,
        style: Style,
        isEnabled: Bool = true,
        handler: @escaping () -> Void
    ) {
        self.baseTitle = title
        self.systemImageName = systemImageName
        self.style = style
        self.handler = handler
        super.init(frame: .zero)

        self.isEnabled = isEnabled
        self.title = title
        self.target = self
        self.action = #selector(handlePress)
        self.isBordered = false
        self.imagePosition = systemImageName == nil ? .noImage : .imageLeading
        self.image = systemImageName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
        self.imageScaling = .scaleProportionallyDown
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setButtonType(.momentaryChange)
        self.wantsLayer = true
        self.layer?.cornerRadius = 10
        self.layer?.masksToBounds = true
        self.font = .systemFont(ofSize: 13, weight: .regular)
        self.alignment = .left
        self.contentTintColor = foregroundColor()
        updateAppearance()

        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    @objc private func handlePress() {
        handler()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = backgroundColor().cgColor
            contentTintColor = foregroundColor()
            attributedTitle = NSAttributedString(
                string: baseTitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: foregroundColor(),
                ]
            )
        }
    }

    private func foregroundColor() -> NSColor {
        switch style {
        case .primary:
            return isEnabled ? .textBackgroundColor : .secondaryLabelColor
        case .destructivePrimary:
            return isEnabled ? .white : .secondaryLabelColor
        case .destructive:
            return isEnabled ? .systemRed : .secondaryLabelColor
        case .normal:
            return isEnabled ? .labelColor : .secondaryLabelColor
        }
    }

    private func backgroundColor() -> NSColor {
        switch style {
        case .primary:
            let baseColor = isEnabled ? NSColor.primaryButton : NSColor.white.withAlphaComponent(0.1)
            return isHovering ? baseColor.withAlphaComponent(0.85) : baseColor
        case .destructivePrimary:
            let baseColor = isEnabled ? NSColor.systemRed : NSColor.white.withAlphaComponent(0.1)
            return isHovering ? baseColor.withAlphaComponent(0.85) : baseColor
        case .destructive:
            return isHovering
                ? NSColor.systemRed.withAlphaComponent(0.15)
                : NSColor.systemRed.withAlphaComponent(0.10)
        case .normal:
            return isHovering
                ? NSColor.labelColor.withAlphaComponent(0.08)
                : NSColor.labelColor.withAlphaComponent(0.04)
        }
    }
}

private final class SidebarActionButtonCell: NSButtonCell {
    private let leadingInset: CGFloat = 10
    private let trailingInset: CGFloat = 10

    override func imageRect(forBounds rect: NSRect) -> NSRect {
        var imageRect = super.imageRect(forBounds: rect)
        imageRect.origin.x += leadingInset
        return imageRect
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        titleRect.origin.x += leadingInset
        titleRect.size.width = max(0, titleRect.size.width - leadingInset - trailingInset)
        return titleRect
    }
}

private extension NSColor {
    static var sidebarReadOnlyFieldFill: NSColor {
        NSColor(name: nil) { appearance in
            if appearance.isDarkMode {
                return NSColor.white.withAlphaComponent(0.085)
            }
            return .quaternarySystemFill
        }
    }

    static var sidebarEditingFieldFill: NSColor {
        NSColor(name: nil) { appearance in
            if appearance.isDarkMode {
                return NSColor.white.withAlphaComponent(0.11)
            }
            return .textBackgroundColor
        }
    }
}

private final class SidebarDisclosureButton: NSButton {
    private let handler: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isExpanded: Bool

    init(title: String, isExpanded: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        self.isExpanded = isExpanded
        super.init(frame: .zero)

        self.title = title
        self.target = self
        self.action = #selector(handlePress)
        self.isBordered = false
        self.alignment = .left
        self.imagePosition = .imageTrailing
        self.translatesAutoresizingMaskIntoConstraints = false
        self.font = .systemFont(ofSize: 11, weight: .semibold)
        updateAppearance()

        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    @objc private func handlePress() {
        handler()
    }

    private func updateAppearance() {
        image = NSImage(
            systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: title
        )
        contentTintColor = .tertiaryLabelColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 0.5,
            ]
        )
    }
}

private final class FlippedSidebarContentView: NSView {
    override var isFlipped: Bool { true }
}
