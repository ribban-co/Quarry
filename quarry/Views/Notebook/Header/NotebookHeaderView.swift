import AppKit

final class NotebookHeaderViewController: NSViewController, NSTextFieldDelegate {

    private let dataController: NotebookDataController

    private var statusButton: StatusDropdownButton!
    private var titleField: NSTextField!
    private var descriptionField: DescriptionTextView!

    init(dataController: NotebookDataController) {
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view = container

        setupStatusButton()
        setupTitleField()
        setupDescriptionField()
        setupConstraints()
        observeDataController()
    }

    // MARK: - Setup

    private func setupStatusButton() {
        statusButton = StatusDropdownButton(dataController: dataController)
        statusButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusButton)
    }

    private func setupTitleField() {
        titleField = NSTextField()
        titleField.stringValue = dataController.title
        titleField.placeholderString = "Untitled Notebook"
        titleField.font = .systemFont(ofSize: 26, weight: .bold)
        titleField.textColor = .labelColor
        titleField.backgroundColor = .clear
        titleField.isBordered = false
        titleField.isBezeled = false
        titleField.focusRingType = .none
        titleField.isEditable = true
        titleField.delegate = self
        titleField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleField)
    }

    private func setupDescriptionField() {
        descriptionField = DescriptionTextView(
            text: dataController.descriptionText,
            onTextChange: { [weak self] text in
                self?.dataController.descriptionText = text
            }
        )
        descriptionField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionField)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            statusButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            statusButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusButton.heightAnchor.constraint(equalToConstant: 22),

            titleField.topAnchor.constraint(equalTo: statusButton.bottomAnchor),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            descriptionField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
            descriptionField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            descriptionField.widthAnchor.constraint(equalToConstant: 550),
            descriptionField.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === titleField {
            dataController.title = field.stringValue
        }
    }

    // MARK: - Observation

    private func observeDataController() {
        observeTitle()
        observeDescription()
        observeStatus()
        observePublishedState()
    }

    private func observeTitle() {
        withObservationTracking {
            _ = self.dataController.title
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.titleField.currentEditor() == nil {
                    self.titleField.stringValue = self.dataController.title
                }
                self.observeTitle()
            }
        }
    }

    private func observeDescription() {
        withObservationTracking {
            _ = self.dataController.descriptionText
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.descriptionField.isEditing {
                    self.descriptionField.setText(self.dataController.descriptionText)
                }
                self.observeDescription()
            }
        }
    }

    private func observeStatus() {
        withObservationTracking {
            _ = self.dataController.status
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.statusButton.updateStatus(self.dataController.status)
                self.observeStatus()
            }
        }
    }

    private func observePublishedState() {
        withObservationTracking {
            _ = self.dataController.isDashboardPublished
            _ = self.dataController.isPublishPreviewing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyPublishedState()
                self.observePublishedState()
            }
        }
    }

    private func applyPublishedState() {
        let readonly = dataController.isDashboardPublished || dataController.isPublishPreviewing
        titleField.isEditable = !readonly
        descriptionField.setEditable(!readonly)
        statusButton.isHidden = readonly
    }
}

// MARK: - Status dropdown button

final class StatusDropdownButton: NSView, NSPopoverDelegate {

    private let dataController: NotebookDataController
    private let dotView: NSView
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var popover: NSPopover?

    init(dataController: NotebookDataController) {
        self.dataController = dataController
        self.dotView = NSView()
        self.label = NSTextField(labelWithString: dataController.status.rawValue)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 5
        dotView.layer?.borderWidth = 1.5
        dotView.layer?.borderColor = dataController.status.nsColor.cgColor
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10),

            label.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func updateStatus(_ status: NotebookStatus) {
        label.stringValue = status.rawValue
        dotView.layer?.borderColor = status.nsColor.cgColor
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyHoverBackground(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(false)
    }

    override func mouseDown(with event: NSEvent) {
        focusButton()
        if popover != nil {
            popover?.performClose(nil)
            return
        }
        showStatusPopover()
    }

    // MARK: - Popover

    private func showStatusPopover() {
        let popoverVC = StatusPopoverController(
            currentStatus: dataController.status
        ) { [weak self] status in
            guard let self else { return }
            self.popover?.performClose(nil)
            self.dataController.status = status
        }

        let pop = NSPopover()
        pop.delegate = self
        pop.contentViewController = popoverVC
        pop.behavior = .transient
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        self.popover = pop
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }

    private func focusButton() {
        guard window?.firstResponder !== self else { return }
        window?.makeFirstResponder(self)
    }
}

// MARK: - Status popover controller

private final class StatusPopoverController: NSViewController {

    private let currentStatus: NotebookStatus
    private let onSelect: (NotebookStatus) -> Void

    init(currentStatus: NotebookStatus, onSelect: @escaping (NotebookStatus) -> Void) {
        self.currentStatus = currentStatus
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        for status in NotebookStatus.allCases {
            let item = StatusOptionItem(
                status: status,
                isSelected: status == currentStatus,
                action: { [weak self] in self?.onSelect(status) }
            )
            item.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(item)
            NSLayoutConstraint.activate([
                item.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6),
                item.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
            ])
        }

        stack.widthAnchor.constraint(equalToConstant: 180).isActive = true
        self.view = stack
    }
}

// MARK: - Status option item

private final class StatusOptionItem: NSView {

    private let action: () -> Void
    private let dotView: NSView
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(status: NotebookStatus, isSelected: Bool, action: @escaping () -> Void) {
        self.action = action
        self.dotView = NSView()
        self.label = NSTextField(labelWithString: status.rawValue)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 6
        dotView.layer?.borderWidth = 1.5
        dotView.layer?.borderColor = status.nsColor.cgColor
        if isSelected {
            dotView.layer?.backgroundColor = status.nsColor.cgColor
        }
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        label.font = .systemFont(ofSize: 13)
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 12),
            dotView.heightAnchor.constraint(equalToConstant: 12),

            label.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyHoverBackground(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverBackground(false)
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }
}

// MARK: - Description Text View

private final class DescriptionTextView: NSView, NSTextViewDelegate {

    private let textView: NSTextView
    private let placeholderLabel: NSTextField
    private var onTextChange: ((String) -> Void)?
    private var heightConstraint: NSLayoutConstraint!
    private(set) var isEditing = false

    init(text: String, onTextChange: @escaping (String) -> Void) {
        self.onTextChange = onTextChange
        textView = NSTextView()
        placeholderLabel = NSTextField(labelWithString: "Add a description...")
        super.init(frame: .zero)

        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .secondaryLabelColor
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        placeholderLabel.font = .systemFont(ofSize: 13)
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.isHidden = !text.isEmpty
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        heightConstraint = heightAnchor.constraint(equalToConstant: 18)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            heightConstraint,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        updateHeight()
    }

    func setText(_ text: String) {
        textView.string = text
        placeholderLabel.isHidden = !text.isEmpty
        updateHeight()
    }

    func setEditable(_ editable: Bool) {
        textView.isEditable = editable
    }

    private func updateHeight() {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let height = layoutManager.usedRect(for: container).height
        let newHeight = max(18, ceil(height))
        if heightConstraint.constant != newHeight {
            heightConstraint.constant = newHeight
        }
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        placeholderLabel.isHidden = !textView.string.isEmpty
        updateHeight()
        onTextChange?(textView.string)
    }

    func textDidBeginEditing(_ notification: Notification) {
        isEditing = true
    }

    func textDidEndEditing(_ notification: Notification) {
        isEditing = false
        onTextChange?(textView.string)
    }
}
