import AppKit

private enum FilterBuilderLayout {
    static let rowHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 8
    static let verticalPadding: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let contentSpacing: CGFloat = 14
    static let actionsSpacing: CGFloat = 10
    static let fieldWidth: CGFloat = 160
    static let operatorWidth: CGFloat = 120
    static let valueWidth: CGFloat = 200
    static let controlCornerRadius: CGFloat = 8
}

class FilterBuilderFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private func filterBuilderIsDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

@MainActor
private func filterBuilderLabel(
    _ text: String,
    size: CGFloat = 13,
    weight: NSFont.Weight = .regular,
    color: NSColor = .labelColor
) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

private class FilterBuilderInteractiveControl: NSControl {
    var onActivate: (() -> Void)?
    var isControlEnabled = true {
        didSet {
            if oldValue != isControlEnabled {
                if !isControlEnabled {
                    if isHovering {
                        NSCursor.pop()
                    }
                    isHovering = false
                    isPressed = false
                }
                updateAppearance()
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
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

    override func mouseEntered(with event: NSEvent) {
        guard isControlEnabled else { return }
        isHovering = true
        NSCursor.pointingHand.push()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        guard isControlEnabled else { return }
        if isHovering {
            NSCursor.pop()
        }
        isHovering = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isControlEnabled else { return }
        isPressed = true
        updateAppearance()

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .greatestFiniteMagnitude,
            mode: .eventTracking
        ) { [weak self] event, stop in
            guard let self, let event else {
                stop.pointee = true
                return
            }

            let location = self.convert(event.locationInWindow, from: nil)
            let isInside = self.bounds.contains(location)

            switch event.type {
            case .leftMouseDragged:
                if self.isPressed != isInside {
                    self.isPressed = isInside
                    self.updateAppearance()
                }
            case .leftMouseUp:
                self.isPressed = false
                self.updateAppearance()
                if isInside {
                    self.onActivate?()
                }
                stop.pointee = true
            default:
                break
            }
        }
    }

    func currentInteractionState() -> (isHovering: Bool, isPressed: Bool, isEnabled: Bool) {
        (isHovering, isPressed, isControlEnabled)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {}
}

private final class FilterBuilderCloseButton: FilterBuilderInteractiveControl {
    private let imageView: NSImageView = {
        let imageView = NSImageView()
        let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        imageView.image = image
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateAppearance() {
        let state = currentInteractionState()
        let isDark = filterBuilderIsDark(effectiveAppearance)

        layer?.cornerRadius = FilterBuilderLayout.controlCornerRadius
        layer?.backgroundColor = (state.isHovering
            ? (isDark ? NSColor.white.withAlphaComponent(0.3) : NSColor.secondarySystemFill)
            : .clear
        ).cgColor

        alphaValue = state.isPressed ? 0.85 : 1.0
    }
}

private final class FilterBuilderTokenView: FilterBuilderFlippedView {
    private let label = filterBuilderLabel("")

    init(width: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = FilterBuilderLayout.controlCornerRadius
        layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor

        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: FilterBuilderLayout.rowHeight),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(title: String) {
        label.stringValue = title
    }
}

private final class FilterBuilderMenuControl: FilterBuilderInteractiveControl {
    private let titleLabel = filterBuilderLabel("")
    private let chevronView: NSImageView = {
        let imageView = NSImageView()
        let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        imageView.image = image
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let width: CGFloat

    init(width: CGFloat) {
        self.width = width
        super.init(frame: .zero)

        addSubview(titleLabel)
        addSubview(chevronView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: FilterBuilderLayout.rowHeight),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(title: String) {
        titleLabel.stringValue = title
    }

    override func updateAppearance() {
        let state = currentInteractionState()
        let isDark = filterBuilderIsDark(effectiveAppearance)

        layer?.cornerRadius = FilterBuilderLayout.controlCornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        let fillColor: NSColor
        if state.isHovering {
            fillColor = isDark
                ? NSColor.controlBackgroundColor.withAlphaComponent(0.2)
                : NSColor.white.withAlphaComponent(0.2)
        } else {
            fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.2)
        }

        layer?.backgroundColor = fillColor.cgColor
        alphaValue = state.isPressed ? 0.9 : 1.0
    }
}

private final class FilterBuilderPrimaryButton: FilterBuilderInteractiveControl {
    private let label = filterBuilderLabel("", weight: .medium, color: .textBackgroundColor)

    init(title: String) {
        super.init(frame: .zero)
        label.stringValue = title
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: FilterBuilderLayout.rowHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateAppearance() {
        let state = currentInteractionState()
        layer?.cornerRadius = FilterBuilderLayout.controlCornerRadius
        layer?.backgroundColor = (state.isEnabled
            ? NSColor.primaryButton
            : NSColor.primaryButton.withAlphaComponent(0.5)
        ).cgColor
        alphaValue = state.isPressed ? 0.8 : (state.isHovering ? 0.8 : 1.0)
        label.textColor = state.isEnabled ? .textBackgroundColor : .secondaryLabelColor
    }
}

private final class FilterBuilderAddButton: FilterBuilderInteractiveControl {
    private let iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let label = filterBuilderLabel("Add Filter")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: FilterBuilderLayout.rowHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateAppearance() {
        let state = currentInteractionState()
        layer?.cornerRadius = FilterBuilderLayout.controlCornerRadius
        layer?.backgroundColor = (state.isHovering
            ? NSColor.quaternarySystemFill
            : .clear
        ).cgColor
        alphaValue = state.isEnabled ? (state.isPressed ? 0.85 : 1.0) : 0.5
        label.textColor = .labelColor
        iconView.contentTintColor = .labelColor
    }
}

private final class FilterBuilderDragDivider: NSView {
    static let hitWidth: CGFloat = 8
    private let line = CALayer()
    private var trackingArea: NSTrackingArea?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.addSublayer(line)
        line.backgroundColor = NSColor.separatorColor.cgColor

        widthAnchor.constraint(equalToConstant: Self.hitWidth).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let midX = (bounds.width - 1) / 2
        line.frame = CGRect(x: midX, y: 0, width: 1, height: bounds.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        line.backgroundColor = NSColor.separatorColor.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInActiveApp, .inVisibleRect, .cursorUpdate],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDown(with event: NSEvent) {
        var lastX = event.locationInWindow.x

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .greatestFiniteMagnitude,
            mode: .eventTracking
        ) { [weak self] event, stop in
            guard let self, let event else {
                stop.pointee = true
                return
            }

            switch event.type {
            case .leftMouseDragged:
                let currentX = event.locationInWindow.x
                let delta = currentX - lastX
                lastX = currentX
                if delta != 0 {
                    self.onDrag?(delta)
                }
            case .leftMouseUp:
                self.onDragEnd?()
                stop.pointee = true
            default:
                break
            }
        }
    }
}

private final class FilterBuilderClearButton: FilterBuilderInteractiveControl {
    private let label = filterBuilderLabel("Clear filters")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: FilterBuilderLayout.rowHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateAppearance() {
        let state = currentInteractionState()
        layer?.cornerRadius = FilterBuilderLayout.controlCornerRadius
        layer?.backgroundColor = (state.isHovering
            ? NSColor.quaternarySystemFill
            : .clear
        ).cgColor
        alphaValue = state.isEnabled ? (state.isPressed ? 0.85 : 1.0) : 0.5
        label.textColor = .labelColor
    }
}

private final class FilterBuilderTextField: NSView {
    private let textField: NSTextField = {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.placeholderString = "Enter a value"
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    var stringValue: String {
        get { textField.stringValue }
        set { textField.stringValue = newValue }
    }

    weak var delegate: NSTextFieldDelegate? {
        get { textField.delegate }
        set { textField.delegate = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = FilterBuilderLayout.controlCornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: FilterBuilderLayout.rowHeight),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textField)
        if let editor = textField.currentEditor() {
            editor.mouseDown(with: event)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    func focus() {
        window?.makeFirstResponder(textField)
    }
}

private final class FilterBuilderRowView: NSStackView, NSTextFieldDelegate {
    var onDelete: (() -> Void)?
    var onFieldSelect: ((String) -> Void)?
    var onOperatorSelect: ((FilterOperator) -> Void)?
    var onValueChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?

    private let deleteButton = FilterBuilderCloseButton()
    private let conjunctionView = FilterBuilderTokenView(width: 64)
    private let fieldButton = FilterBuilderMenuControl(width: FilterBuilderLayout.fieldWidth)
    private let operatorButton = FilterBuilderMenuControl(width: FilterBuilderLayout.operatorWidth)
    private let valueField = FilterBuilderTextField()
    private var valueWidthConstraint: NSLayoutConstraint?

    private var columns: [DatabaseSchemaInfo] = []
    private var selectedOperator: FilterOperator = .equals
    private var selectedField: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        spacing = 10

        addArrangedSubview(deleteButton)
        addArrangedSubview(conjunctionView)
        addArrangedSubview(fieldButton)
        addArrangedSubview(operatorButton)
        addArrangedSubview(valueField)

        let widthConstraint = valueField.widthAnchor.constraint(equalToConstant: FilterBuilderLayout.valueWidth)
        widthConstraint.isActive = true
        valueWidthConstraint = widthConstraint
        heightAnchor.constraint(equalToConstant: FilterBuilderLayout.rowHeight).isActive = true

        deleteButton.onActivate = { [weak self] in
            self?.onDelete?()
        }
        fieldButton.onActivate = { [weak self] in
            self?.presentFieldMenu()
        }
        operatorButton.onActivate = { [weak self] in
            self?.presentOperatorMenu()
        }
        valueField.delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(
        condition: FilterCondition,
        isFirstRow: Bool,
        columns: [DatabaseSchemaInfo]
    ) {
        self.columns = columns
        selectedOperator = condition.filterOperator
        selectedField = condition.field
        conjunctionView.update(title: isFirstRow ? "where" : condition.conjunction.rawValue)
        fieldButton.update(title: condition.field.isEmpty ? "Select field" : condition.field)
        operatorButton.update(title: condition.filterOperator.rawValue)
        if valueField.stringValue != condition.value {
            valueField.stringValue = condition.value
        }
    }

    func focusValueField() {
        valueField.focus()
    }

    func setValueFieldWidth(_ width: CGFloat) {
        valueWidthConstraint?.constant = width
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let movement = obj.userInfo?["NSTextMovement"] as? Int
        if movement == NSReturnTextMovement {
            onSubmit?()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        onValueChange?(valueField.stringValue)
    }

    private func presentFieldMenu() {
        guard !columns.isEmpty else { return }

        let menu = NSMenu()
        for column in columns {
            let item = NSMenuItem(title: column.columnName, action: #selector(selectField(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.columnName
            item.state = (column.columnName == selectedField) ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: fieldButton)
    }

    private func presentOperatorMenu() {
        let menu = NSMenu()
        for filterOperator in FilterOperator.allCases {
            let item = NSMenuItem(title: filterOperator.rawValue, action: #selector(selectOperator(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = filterOperator
            item.state = (filterOperator == selectedOperator) ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: operatorButton)
    }

    @objc private func selectField(_ sender: NSMenuItem) {
        guard let columnName = sender.representedObject as? String else { return }
        selectedField = columnName
        fieldButton.update(title: columnName)
        onFieldSelect?(columnName)
    }

    @objc private func selectOperator(_ sender: NSMenuItem) {
        guard let filterOperator = sender.representedObject as? FilterOperator else { return }
        selectedOperator = filterOperator
        operatorButton.update(title: filterOperator.rawValue)
        onOperatorSelect?(filterOperator)
    }
}

@MainActor
final class FilterBuilderAppKitView: FilterBuilderFlippedView {
    private var columns: [DatabaseSchemaInfo] = []
    private var fallbackColumns: [QueryColumnInfo] = []
    private var conditions: [FilterCondition] = []
    private var tabID: UUID?
    private var showFilterBuilder = false
    private weak var hostingWindow: NSWindow?

    private var onConditionsChange: (([FilterCondition]) -> Void)?
    private var generateFilterQuery: (([FilterCondition]) -> String)?
    private var onApplyFilter: ((String) -> Void)?
    private var onLayoutInvalidated: (() -> Void)?
    private var onHeightChanged: ((CGFloat) -> Void)?

    private var rowViews: [FilterBuilderRowView] = []
    private var lastReportedHeight: CGFloat = -1

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let documentView = FilterBuilderFlippedView()
    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = FilterBuilderLayout.contentSpacing
        return stack
    }()

    private let rowsStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = FilterBuilderLayout.rowSpacing
        return stack
    }()

    private let divider = FilterBuilderDragDivider()
    private var valueFieldWidth: CGFloat = FilterBuilderAppKitView.loadPersistedValueFieldWidth()
    private static let minValueFieldWidth: CGFloat = 120
    private static let maxValueFieldWidth: CGFloat = 640
    private static let valueFieldWidthDefaultsKey = "FilterBuilder.valueFieldWidth"

    private static func loadPersistedValueFieldWidth() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: valueFieldWidthDefaultsKey)
        guard stored > 0 else { return FilterBuilderLayout.valueWidth }
        return min(maxValueFieldWidth, max(minValueFieldWidth, CGFloat(stored)))
    }

    private let actionsStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = FilterBuilderLayout.actionsSpacing
        return stack
    }()

    private let applyButton = FilterBuilderPrimaryButton(title: "Apply")
    private let addButton = FilterBuilderAddButton()
    private let clearButton = FilterBuilderClearButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleFilterBuilder(_:)),
            name: .toggleFilterBuilder,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hostingWindow = window
    }

    override func layout() {
        super.layout()

        scrollView.frame = bounds

        guard showFilterBuilder else {
            documentView.frame = .zero
            return
        }

        let stackSize = contentStack.fittingSize
        contentStack.frame = NSRect(
            x: FilterBuilderLayout.horizontalPadding,
            y: FilterBuilderLayout.verticalPadding,
            width: stackSize.width,
            height: stackSize.height
        )

        let minimumWidth = max(bounds.width, stackSize.width + (FilterBuilderLayout.horizontalPadding * 2))
        documentView.frame = NSRect(x: 0, y: 0, width: minimumWidth, height: bounds.height)
    }

    var resolvedHeight: CGFloat {
        guard showFilterBuilder else { return 0 }

        let rowCount = max(conditions.count, 1)
        let contentHeight = CGFloat(rowCount) * FilterBuilderLayout.rowHeight
        let spacingHeight = CGFloat(max(rowCount - 1, 0)) * FilterBuilderLayout.rowSpacing
        return contentHeight + spacingHeight + (FilterBuilderLayout.verticalPadding * 2)
    }

    func update(
        columns: [DatabaseSchemaInfo],
        fallbackColumns: [QueryColumnInfo],
        tabID: UUID,
        conditions: [FilterCondition],
        onConditionsChange: @escaping ([FilterCondition]) -> Void,
        generateFilterQuery: @escaping ([FilterCondition]) -> String,
        onApplyFilter: @escaping (String) -> Void,
        onLayoutInvalidated: (() -> Void)? = nil,
        onHeightChanged: ((CGFloat) -> Void)? = nil
    ) {
        self.tabID = tabID
        self.onConditionsChange = onConditionsChange
        self.generateFilterQuery = generateFilterQuery
        self.onApplyFilter = onApplyFilter
        self.onLayoutInvalidated = onLayoutInvalidated
        self.onHeightChanged = onHeightChanged

        let columnsChanged = self.columns != columns || fallbackSignature(self.fallbackColumns) != fallbackSignature(fallbackColumns)
        if columnsChanged {
            self.columns = columns
            self.fallbackColumns = fallbackColumns
        }

        let conditionsChanged = self.conditions != conditions
        if conditionsChanged {
            self.conditions = conditions
        }

        if columnsChanged {
            syncInitialFieldIfNeeded()
        }

        let shouldAutoShow = self.conditions.contains {
            !$0.field.isEmpty && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if shouldAutoShow && !showFilterBuilder {
            showFilterBuilder = true
        }

        syncRows(forceRebuild: columnsChanged || rowViews.count != self.conditions.count)
        updateActions()
        reportHeightIfNeeded(force: columnsChanged || conditionsChanged)
        needsLayout = true
    }

    private func setupViews() {
        scrollView.documentView = documentView
        addSubview(scrollView)

        contentStack.addArrangedSubview(rowsStack)
        contentStack.addArrangedSubview(divider)
        contentStack.addArrangedSubview(actionsStack)

        divider.heightAnchor.constraint(equalTo: rowsStack.heightAnchor).isActive = true

        documentView.addSubview(contentStack)

        actionsStack.addArrangedSubview(applyButton)
        actionsStack.addArrangedSubview(addButton)
        actionsStack.addArrangedSubview(clearButton)
        actionsStack.setCustomSpacing(0, after: addButton)

        applyButton.onActivate = { [weak self] in
            self?.applyCurrentFilter()
        }
        addButton.onActivate = { [weak self] in
            self?.addFilterRow()
        }
        clearButton.onActivate = { [weak self] in
            self?.clearFilters()
        }
        divider.onDrag = { [weak self] delta in
            self?.handleDividerDrag(delta: delta)
        }
        divider.onDragEnd = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(Double(self.valueFieldWidth), forKey: Self.valueFieldWidthDefaultsKey)
        }
    }

    private func handleDividerDrag(delta: CGFloat) {
        let next = min(
            Self.maxValueFieldWidth,
            max(Self.minValueFieldWidth, valueFieldWidth + delta)
        )
        guard next != valueFieldWidth else { return }
        valueFieldWidth = next
        for row in rowViews {
            row.setValueFieldWidth(valueFieldWidth)
        }
        contentStack.layoutSubtreeIfNeeded()
        onLayoutInvalidated?()
        needsLayout = true
    }

    private func filterableColumns() -> [DatabaseSchemaInfo] {
        if !columns.isEmpty {
            return columns
        }

        return fallbackColumns.enumerated().map { index, column in
            DatabaseSchemaInfo(
                ordinalPosition: index + 1,
                columnName: column.name,
                dataType: column.dataType,
                formatType: column.format ?? column.dataType,
                typeOid: 0
            )
        }
    }

    private func defaultColumnName() -> String {
        filterableColumns().first?.columnName ?? ""
    }

    private func fallbackSignature(_ columns: [QueryColumnInfo]) -> [String] {
        columns.map { "\($0.index)|\($0.name)|\($0.dataType)|\($0.format ?? "")" }
    }

    private func syncInitialFieldIfNeeded() {
        guard !filterableColumns().isEmpty, !conditions.isEmpty, conditions[0].field.isEmpty else {
            return
        }

        conditions[0].field = defaultColumnName()
        onConditionsChange?(conditions)
    }

    private func syncRows(forceRebuild: Bool) {
        let availableColumns = filterableColumns()

        if forceRebuild {
            rowViews.forEach { row in
                rowsStack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
            rowViews.removeAll()

            for index in conditions.indices {
                let row = FilterBuilderRowView()
                row.update(condition: conditions[index], isFirstRow: index == 0, columns: availableColumns)
                row.onDelete = { [weak self] in
                    self?.deleteRow(at: index)
                }
                row.onFieldSelect = { [weak self] columnName in
                    self?.updateCondition(at: index) { $0.field = columnName }
                }
                row.onOperatorSelect = { [weak self] filterOperator in
                    self?.updateCondition(at: index) { $0.filterOperator = filterOperator }
                }
                row.onValueChange = { [weak self] value in
                    self?.updateConditionValue(at: index, value: value)
                }
                row.onSubmit = { [weak self] in
                    self?.applyCurrentFilter()
                }
                row.setValueFieldWidth(valueFieldWidth)
                rowsStack.addArrangedSubview(row)
                rowViews.append(row)
            }
        } else {
            for index in conditions.indices where index < rowViews.count {
                rowViews[index].update(
                    condition: conditions[index],
                    isFirstRow: index == 0,
                    columns: availableColumns
                )
            }
        }

        divider.isHidden = rowViews.isEmpty
        needsLayout = true
    }

    private func updateCondition(at index: Int, mutate: (inout FilterCondition) -> Void) {
        guard conditions.indices.contains(index) else { return }

        let previous = conditions[index]
        mutate(&conditions[index])
        guard previous != conditions[index] else { return }

        syncRows(forceRebuild: false)
        updateActions()
        onConditionsChange?(conditions)
    }

    private func updateConditionValue(at index: Int, value: String) {
        guard conditions.indices.contains(index), conditions[index].value != value else { return }
        conditions[index].value = value
        updateActions()
        onConditionsChange?(conditions)
    }

    private func updateActions() {
        applyButton.isControlEnabled = hasValidCondition()
        addButton.isControlEnabled = conditions.count < 8
    }

    private func hasValidCondition() -> Bool {
        conditions.contains { condition in
            !condition.field.isEmpty && !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func addFilterRow() {
        guard conditions.count < 8 else { return }

        conditions.append(
            FilterCondition(
                conjunction: .and,
                field: defaultColumnName(),
                filterOperator: .equals,
                value: ""
            )
        )
        syncRows(forceRebuild: true)
        updateActions()
        onConditionsChange?(conditions)
        onLayoutInvalidated?()
        reportHeightIfNeeded(force: true)
    }

    private func deleteRow(at index: Int) {
        guard conditions.indices.contains(index) else { return }

        if conditions.count > 1 {
            conditions.remove(at: index)
            syncRows(forceRebuild: true)
            updateActions()
            onConditionsChange?(conditions)
            onLayoutInvalidated?()
            reportHeightIfNeeded(force: true)
            return
        }

        conditions = [
            FilterCondition(
                conjunction: .whereClause,
                field: defaultColumnName(),
                filterOperator: .equals,
                value: ""
            )
        ]
        syncRows(forceRebuild: true)
        updateActions()
        onConditionsChange?(conditions)
        onApplyFilter?("")
        closeBuilder(postCloseNotification: true)
    }

    private func clearFilters() {
        conditions = [
            FilterCondition(
                conjunction: .whereClause,
                field: defaultColumnName(),
                filterOperator: .equals,
                value: ""
            )
        ]
        syncRows(forceRebuild: true)
        updateActions()
        onConditionsChange?(conditions)
        onApplyFilter?("")
        onLayoutInvalidated?()
        reportHeightIfNeeded(force: true)
    }

    private func applyCurrentFilter() {
        guard let generateFilterQuery else { return }
        onApplyFilter?(generateFilterQuery(conditions))
    }

    private func closeBuilder(postCloseNotification: Bool) {
        guard showFilterBuilder else { return }
        showFilterBuilder = false
        onLayoutInvalidated?()
        reportHeightIfNeeded(force: true)
        needsLayout = true

        if postCloseNotification, let hostingWindow, let tabID {
            NotificationCenter.default.post(
                name: .filterBuilderDidClose,
                object: hostingWindow,
                userInfo: ["tabID": tabID]
            )
        }
    }

    private func reportHeightIfNeeded(force: Bool = false) {
        let nextHeight = max(0, self.resolvedHeight.rounded(.up))
        guard force || abs(lastReportedHeight - nextHeight) >= 0.5 else { return }
        lastReportedHeight = nextHeight
        onHeightChanged?(nextHeight)
    }

    private func focusFirstRowAfterDelay() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.rowViews.first?.focusValueField()
        }
    }

    func showBuilder() {
        guard !showFilterBuilder else { return }
        showFilterBuilder = true
        syncInitialFieldIfNeeded()
        syncRows(forceRebuild: rowViews.count != conditions.count)
        updateActions()
        focusFirstRowAfterDelay()
        onLayoutInvalidated?()
        reportHeightIfNeeded(force: true)
        needsLayout = true
    }

    @objc private func handleToggleFilterBuilder(_ notification: Notification) {
        guard let sourceWindow = notification.object as? NSWindow,
              let hostingWindow,
              sourceWindow === hostingWindow,
              let tabID,
              notification.userInfo?["tabID"] as? UUID == tabID else { return }

        showFilterBuilder.toggle()
        if showFilterBuilder {
            syncInitialFieldIfNeeded()
            syncRows(forceRebuild: rowViews.count != conditions.count)
            updateActions()
            focusFirstRowAfterDelay()
        }

        onLayoutInvalidated?()
        reportHeightIfNeeded(force: true)
        needsLayout = true
    }
}
