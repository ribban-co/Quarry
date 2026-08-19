import AppKit

final class NotebookEmptyStateController: NSViewController {

    private let dataController: NotebookDataController
    private var inputTextView: EmptyStateInputTextView!
    private var inputPlaceholderLabel: NSTextField!
    private var sendButton: EmptyStateSendButton!
    private var inputContainer: NSView!

    private var selectedConnections: [Connection] = []
    private var pendingAtDetection = false
    private var suppressNextReturnSend = false
    private var isConnectionMenuOpen = false
    private var inputRowView: NSView!
    private var actionBarView: NSView!
    private var connectionButton: EmptyStateConnectionButton!

    init(dataController: NotebookDataController) {
        self.dataController = dataController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        let containerStack = NSStackView()
        containerStack.orientation = .vertical
        containerStack.alignment = .centerX
        containerStack.spacing = 32
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(containerStack)

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .lastBaseline
        titleRow.spacing = 8

        let title = NSTextField(labelWithString: "What would you like to build?")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .labelColor

        let betaPill = NSView()
        betaPill.wantsLayer = true
        betaPill.layer?.cornerRadius = 4
        betaPill.layer?.cornerCurve = .continuous
        betaPill.layer?.borderWidth = 1
        betaPill.translatesAutoresizingMaskIntoConstraints = false
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            betaPill.layer?.backgroundColor = isDark
                ? NSColor.primaryButton.withAlphaComponent(0.12).cgColor
                : NSColor.primaryButton.withAlphaComponent(0.08).cgColor
            betaPill.layer?.borderColor = isDark
                ? NSColor.primaryButton.withAlphaComponent(0.25).cgColor
                : NSColor.primaryButton.withAlphaComponent(0.2).cgColor
        }

        let betaLabel = NSTextField(labelWithString: "BETA")
        betaLabel.font = .systemFont(ofSize: 9, weight: .bold)
        betaLabel.textColor = .primaryButton
        betaLabel.alignment = .center
        betaLabel.translatesAutoresizingMaskIntoConstraints = false
        betaPill.addSubview(betaLabel)

        NSLayoutConstraint.activate([
            betaLabel.leadingAnchor.constraint(equalTo: betaPill.leadingAnchor, constant: 4),
            betaLabel.trailingAnchor.constraint(equalTo: betaPill.trailingAnchor, constant: -4),
            betaLabel.topAnchor.constraint(equalTo: betaPill.topAnchor, constant: 4),
            betaLabel.bottomAnchor.constraint(equalTo: betaPill.bottomAnchor, constant: -4),
        ])

        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(betaPill)
        containerStack.addArrangedSubview(titleRow)

        let inputRow = makeInputRow()
        inputRowView = inputRow
        containerStack.addArrangedSubview(inputRow)

        let actionBar = NotebookActionBarView(dataController: dataController)
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBarView = actionBar
        containerStack.addArrangedSubview(actionBar)

        let fillWidth = containerStack.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48)
        fillWidth.priority = .defaultLow

        NSLayoutConstraint.activate([
            containerStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            containerStack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -40),
            containerStack.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            containerStack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
            containerStack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            fillWidth,
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(inputTextView.textView)
        syncSelectedConnections()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        syncSelectedConnections()
        observeConnections()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Input Row

    private func makeInputRow() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.cornerCurve = .continuous
        container.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.08)
            s.shadowBlurRadius = 8
            s.shadowOffset = NSSize(width: 0, height: -2)
            return s
        }()
        container.translatesAutoresizingMaskIntoConstraints = false
        inputContainer = container
        updateContainerAppearance()

        inputTextView = EmptyStateInputTextView()
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        inputTextView.onTextChanged = { [weak self] in
            guard let self else { return }
            self.inputPlaceholderLabel.isHidden = !self.inputMessage.isEmpty
            self.refreshSendButton()
            self.handleAtDetection()
        }
        inputTextView.onReturn = { [weak self] in
            guard let self else { return }
            if self.isConnectionMenuOpen || self.pendingAtDetection {
                return
            }
            if self.suppressNextReturnSend {
                self.suppressNextReturnSend = false
                return
            }
            self.handleSend()
        }
        container.addSubview(inputTextView)

        let placeholder = NSTextField(labelWithString: "Ask a data question...")
        placeholder.font = .systemFont(ofSize: 15)
        placeholder.textColor = .placeholderTextColor
        placeholder.backgroundColor = .clear
        placeholder.isBordered = false
        placeholder.isBezeled = false
        placeholder.isEditable = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(placeholder)
        inputPlaceholderLabel = placeholder

        let connButton = EmptyStateConnectionButton()
        connButton.translatesAutoresizingMaskIntoConstraints = false
        connButton.target = self
        connButton.action = #selector(connectionButtonTapped)
        container.addSubview(connButton)
        connectionButton = connButton

        let button = EmptyStateSendButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(handleSend)
        container.addSubview(button)
        sendButton = button

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            inputTextView.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            inputTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            inputTextView.trailingAnchor.constraint(equalTo: connButton.leadingAnchor, constant: -8),
            inputTextView.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18),

            placeholder.centerYAnchor.constraint(equalTo: inputTextView.centerYAnchor),
            placeholder.leadingAnchor.constraint(equalTo: inputTextView.leadingAnchor),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: inputTextView.trailingAnchor),

            connButton.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -4),
            connButton.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            connButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -15),
            connButton.heightAnchor.constraint(equalToConstant: 26),

            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32),

            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])

        return container
    }

    private func refreshSendButton() {
        let hasText = !inputMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isActive = hasText || !selectedConnections.isEmpty
    }

    private var inputMessage: String {
        inputTextView.textView.string
    }

    // MARK: - @ Connection Menu

    private func handleAtDetection() {
        guard !dataController.connections.isEmpty else { return }
        let text = inputMessage
        let selectedRange = inputTextView.textView.selectedRange()
        guard selectedRange.length == 0, selectedRange.location > 0 else { return }

        let nsText = text as NSString
        let charBeforeCursor = nsText.substring(with: NSRange(location: selectedRange.location - 1, length: 1))
        guard charBeforeCursor == "@" else { return }
        guard !pendingAtDetection else { return }
        pendingAtDetection = true
        showConnectionMenu(atRange: NSRange(location: selectedRange.location - 1, length: 1))
    }

    private func showConnectionMenu(atRange: NSRange) {
        let textView = inputTextView.textView
        let text = textView.string as NSString
        if NSMaxRange(atRange) <= text.length,
           text.substring(with: atRange) == "@" {
            textView.textStorage?.replaceCharacters(in: atRange, with: "")
            textView.setSelectedRange(NSRange(location: atRange.location, length: 0))
            inputTextView.recalculateHeight()
            inputPlaceholderLabel.isHidden = !inputMessage.isEmpty
        }
        pendingAtDetection = false

        showConnectionPicker(relativeTo: connectionButton)
    }

    @objc private func connectionButtonTapped() {
        guard !dataController.connections.isEmpty else { return }
        showConnectionPicker(relativeTo: connectionButton)
    }

    private func showConnectionPicker(relativeTo positioningView: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.font = .systemFont(ofSize: 13)

        for connection in dataController.connections {
            let isSelected = selectedConnections.contains(where: { $0.keychainId == connection.keychainId })
            let item = NSMenuItem()
            item.title = connection.name
            item.target = self
            item.action = #selector(connectionPickerItemClicked(_:))
            item.representedObject = connection.keychainId
            item.state = isSelected ? .on : .off
            if let icon = NSImage(named: connection.databaseType.icon)?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }

        inputContainer.layoutSubtreeIfNeeded()
        menu.update()

        let gap: CGFloat = 6
        let menuHeight = menu.size.height
        let menuPoint = NSPoint(
            x: positioningView.frame.minX,
            y: positioningView.frame.maxY + gap + menuHeight
        )

        isConnectionMenuOpen = true
        suppressNextReturnSend = true
        _ = menu.popUp(positioning: nil, at: menuPoint, in: inputContainer)
        pendingAtDetection = false
        isConnectionMenuOpen = false
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.suppressNextReturnSend = false
        }
        view.window?.makeFirstResponder(inputTextView.textView)
    }

    @objc private func connectionPickerItemClicked(_ sender: NSMenuItem) {
        guard let keychainId = sender.representedObject as? String,
              let connection = dataController.connections.first(where: { $0.keychainId == keychainId }) else { return }

        if selectedConnections.first?.keychainId == keychainId {
            selectedConnections.removeAll()
        } else {
            selectedConnections = [connection]
        }

        updateConnectionButton()
        refreshSendButton()
    }

    @objc private func handleSend() {
        let text = inputMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if !selectedConnections.isEmpty {
            dataController.pendingAgentConnections = selectedConnections
        }
        dataController.pendingAgentMessage = text
        dataController.isRightSidebarVisible = true

        inputRowView.isHidden = true

        inputTextView.textView.string = ""
        inputTextView.recalculateHeight()
        inputPlaceholderLabel.isHidden = false
        selectedConnections.removeAll()
        updateConnectionButton()
        sendButton.isActive = false
    }

    private func updateConnectionButton() {
        connectionButton.update(with: selectedConnections)
    }

    private func observeConnections() {
        withObservationTracking {
            _ = self.dataController.connections.map(\.keychainId)
            _ = self.dataController.connections.map(\.name)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncSelectedConnections()
                self.observeConnections()
            }
        }
    }

    private func syncSelectedConnections() {
        let availableKeychainIds = Set(dataController.connections.map(\.keychainId))
        selectedConnections.removeAll { !availableKeychainIds.contains($0.keychainId) }

        if selectedConnections.isEmpty, let first = dataController.connections.first {
            selectedConnections = [first]
        }

        updateConnectionButton()
    }

    // MARK: - Appearance

    private func updateContainerAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            inputContainer.layer?.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.06).cgColor
                : NSColor.white.cgColor
            inputContainer.layer?.borderWidth = 1
            inputContainer.layer?.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.12).cgColor
                : NSColor.white.cgColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateContainerAppearance()
    }
}

private final class EmptyStatePlainPasteTextView: NSTextView {
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}

private final class EmptyStateInputTextView: NSView, NSTextViewDelegate {

    let textView: NSTextView
    var onTextChanged: (() -> Void)?
    var onReturn: (() -> Void)?

    private static let fontSize: CGFloat = 15
    private static let inputFont: NSFont = .systemFont(ofSize: fontSize)

    private var heightConstraint: NSLayoutConstraint!
    private var lastKnownHeight: CGFloat = 0
    private let singleLineHeight: CGFloat = inputFont.lineHeight

    override init(frame: NSRect) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)

        textView = EmptyStatePlainPasteTextView(frame: .zero, textContainer: textContainer)
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = Self.inputFont
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.typingAttributes = [
            .font: Self.inputFont,
            .foregroundColor: NSColor.labelColor,
        ]

        super.init(frame: frame)

        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        heightConstraint = heightAnchor.constraint(equalToConstant: singleLineHeight)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func layout() {
        super.layout()

        if let textContainer = textView.textContainer {
            let containerWidth = max(0, bounds.width)
            if abs(textContainer.containerSize.width - containerWidth) > 1 {
                textContainer.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
            }
        }

        recalculateHeight()
    }

    func recalculateHeight() {
        guard bounds.width > 0,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = max(singleLineHeight, min(280, ceil(usedRect.height)))

        guard abs(newHeight - lastKnownHeight) > 0.5 else { return }
        lastKnownHeight = newHeight
        heightConstraint.constant = newHeight
        textView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: newHeight)
    }

    func textDidChange(_ notification: Notification) {
        recalculateHeight()
        onTextChanged?()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            if shiftPressed {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            onReturn?()
            return true
        }
        return false
    }
}

// MARK: - Send Button

private final class EmptyStateSendButton: NSControl {

    var isActive = false {
        didSet { updateAppearance() }
    }

    private let iconView: NSImageView
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    override init(frame: NSRect) {
        let image = NSImage(
            systemSymbolName: "arrow.up",
            accessibilityDescription: "Send"
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .bold))
        iconView = NSImageView(image: image ?? NSImage())

        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16

        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()

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
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            updateAppearance()
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        updateAppearance()
    }

    private func updateAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            if isActive {
                layer?.backgroundColor = NSColor.primaryButton.cgColor
                layer?.opacity = isHovering ? 0.8 : 1.0
                iconView.contentTintColor = .white
            } else {
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(isHovering ? 0.15 : 0.10).cgColor
                    : NSColor.black.withAlphaComponent(isHovering ? 0.10 : 0.06).cgColor
                layer?.opacity = 1.0
                iconView.contentTintColor = isDark
                    ? .white.withAlphaComponent(0.5)
                    : .black.withAlphaComponent(0.3)
            }
        }
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }
}

// MARK: - Connection Button

private final class EmptyStateConnectionButton: NSControl {

    private static let iconSize: CGFloat = 26
    private static let overlap: CGFloat = 8

    private let emptyLabel: NSTextField
    private let singleIconView: NSImageView
    private let singleNameLabel: NSTextField
    private let iconContainer: NSView
    private var widthConstraint: NSLayoutConstraint!
    private var emptyLabelWidth: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var hasConnections = false

    override init(frame: NSRect) {
        emptyLabel = NSTextField(labelWithString: "Connection")
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        singleIconView = NSImageView()
        singleIconView.imageAlignment = .alignCenter
        singleIconView.imageScaling = .scaleProportionallyDown
        singleIconView.translatesAutoresizingMaskIntoConstraints = false
        singleIconView.isHidden = true

        singleNameLabel = NSTextField(labelWithString: "")
        singleNameLabel.font = .systemFont(ofSize: 13)
        singleNameLabel.lineBreakMode = .byTruncatingTail
        singleNameLabel.maximumNumberOfLines = 1
        singleNameLabel.translatesAutoresizingMaskIntoConstraints = false
        singleNameLabel.isHidden = true

        iconContainer = NSView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.isHidden = true

        super.init(frame: frame)

        wantsLayer = true

        addSubview(emptyLabel)
        addSubview(singleIconView)
        addSubview(singleNameLabel)
        addSubview(iconContainer)

        emptyLabelWidth = emptyLabel.fittingSize.width
        widthConstraint = widthAnchor.constraint(equalToConstant: 6 + emptyLabelWidth)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            widthConstraint,

            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            singleIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            singleIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            singleIconView.widthAnchor.constraint(equalToConstant: 14),
            singleIconView.heightAnchor.constraint(equalToConstant: 14),

            singleNameLabel.leadingAnchor.constraint(equalTo: singleIconView.trailingAnchor, constant: 4),
            singleNameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            singleNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),

            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.heightAnchor.constraint(equalToConstant: Self.iconSize),
        ])

        updateAppearance()

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

    private var iconContainerWidthConstraint: NSLayoutConstraint?

    func update(with connections: [Connection]) {
        hasConnections = !connections.isEmpty
        iconContainer.subviews.forEach { $0.removeFromSuperview() }
        iconContainerWidthConstraint?.isActive = false
        iconContainerWidthConstraint = nil

        // Empty state
        guard !connections.isEmpty else {
            emptyLabel.isHidden = false
            singleIconView.isHidden = true
            singleNameLabel.isHidden = true
            iconContainer.isHidden = true
            widthConstraint.constant = 6 + emptyLabelWidth
            updateAppearance()
            return
        }

        emptyLabel.isHidden = true

        // Single connection — show icon + name
        if connections.count == 1, let conn = connections.first {
            singleIconView.isHidden = false
            singleNameLabel.isHidden = false
            iconContainer.isHidden = true

            singleIconView.image = NSImage(named: conn.databaseType.icon)
            singleNameLabel.stringValue = conn.name
            singleNameLabel.textColor = .labelColor

            let nameWidth = min(singleNameLabel.fittingSize.width, 120)
            widthConstraint.constant = 4 + 14 + 4 + nameWidth + 4
            updateAppearance()
            return
        }

        // Multiple connections — overlapping icon circles
        singleIconView.isHidden = true
        singleNameLabel.isHidden = true
        iconContainer.isHidden = false

        let iconSize = Self.iconSize
        let step = iconSize - Self.overlap

        for (index, conn) in connections.enumerated() {
            let circle = NSView()
            circle.wantsLayer = true
            circle.layer?.cornerRadius = iconSize / 2
            circle.layer?.masksToBounds = true
            circle.layer?.borderWidth = 1.5
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                let isDark = NSAppearance.currentDrawing().isDarkMode
                circle.layer?.borderColor = isDark
                    ? NSColor(white: 0.15, alpha: 1).cgColor
                    : NSColor.white.cgColor
                circle.layer?.backgroundColor = isDark
                    ? NSColor(white: 0.2, alpha: 1).cgColor
                    : NSColor(white: 0.95, alpha: 1).cgColor
            }
            circle.translatesAutoresizingMaskIntoConstraints = false

            let imgView = NSImageView()
            imgView.image = NSImage(named: conn.databaseType.icon)
            imgView.imageAlignment = .alignCenter
            imgView.imageScaling = .scaleProportionallyDown
            imgView.translatesAutoresizingMaskIntoConstraints = false
            circle.addSubview(imgView)

            iconContainer.addSubview(circle)

            NSLayoutConstraint.activate([
                circle.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor, constant: CGFloat(index) * step),
                circle.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
                circle.widthAnchor.constraint(equalToConstant: iconSize),
                circle.heightAnchor.constraint(equalToConstant: iconSize),

                imgView.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
                imgView.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            ])
        }

        let iconsWidth = iconSize + CGFloat(connections.count - 1) * step
        let wc = iconContainer.widthAnchor.constraint(equalToConstant: iconsWidth)
        wc.isActive = true
        iconContainerWidthConstraint = wc

        widthConstraint.constant = 3 + iconsWidth + 3

        updateAppearance()
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
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    private func refreshHoverState() {
        guard let window else {
            isHovering = false
            updateAppearance()
            return
        }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let should = bounds.contains(mouse)
        guard should != isHovering else { return }
        isHovering = should
        updateAppearance()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovering {
            let isDark = NSApp.effectiveAppearance.isDarkMode
            let color: NSColor = isDark
                ? .white.withAlphaComponent(0.08)
                : .black.withAlphaComponent(0.05)
            color.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
    }

    private func updateAppearance() {
        needsDisplay = true
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }
}
