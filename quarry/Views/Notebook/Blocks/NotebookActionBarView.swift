import AppKit

final class NotebookActionBarView: NSView {

    private let dataController: NotebookDataController
    private let insertionIndex: Int?
    private let onDidInsert: (() -> Void)?

    private let chromeView = NotebookActionBarChromeView()
    private let buttonStack = NSStackView()

    init(dataController: NotebookDataController, insertionIndex: Int? = nil, onDidInsert: (() -> Void)? = nil) {
        self.dataController = dataController
        self.insertionIndex = insertionIndex
        self.onDidInsert = onDidInsert
        super.init(frame: .zero)

        setupBar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var visibleTypes: [NotebookCellType] {
        NotebookCellType.allCases.filter { $0.isEnabled }
    }

    private func setupBar() {
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        chromeView.setContentHuggingPriority(.required, for: .horizontal)
        chromeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(chromeView)

        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 5
        buttonStack.distribution = .fill
        buttonStack.setContentHuggingPriority(.required, for: .horizontal)
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        chromeView.addSubview(buttonStack)

        for (index, type) in visibleTypes.enumerated() {
            let button = NotebookActionButtonView(type: type) { [weak self] in
                self?.handleCellType(type)
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            buttonStack.addArrangedSubview(button)

            if index < visibleTypes.count - 1 {
                let divider = NotebookActionDividerView()
                divider.translatesAutoresizingMaskIntoConstraints = false
                buttonStack.addArrangedSubview(divider)
                divider.heightAnchor.constraint(equalToConstant: 22).isActive = true
                divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
            }
        }

        let stackTopInset: CGFloat = insertionIndex == nil ? 8 : 9
        let stackBottomInset: CGFloat = insertionIndex == nil ? 8 : 7

        var constraints: [NSLayoutConstraint] = [
            chromeView.centerXAnchor.constraint(equalTo: centerXAnchor),
            chromeView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            chromeView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            buttonStack.topAnchor.constraint(equalTo: chromeView.topAnchor, constant: stackTopInset),
            buttonStack.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: 8),
            buttonStack.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -8),
            buttonStack.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor, constant: -stackBottomInset),
        ]

        if insertionIndex == nil {
            constraints.append(chromeView.topAnchor.constraint(equalTo: topAnchor, constant: -16))
            constraints.append(chromeView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -26))
        } else {
            constraints.append(chromeView.topAnchor.constraint(equalTo: topAnchor))
            constraints.append(chromeView.bottomAnchor.constraint(equalTo: bottomAnchor))
        }

        NSLayoutConstraint.activate(constraints)

        invalidateIntrinsicContentSize()
    }

    private func handleCellType(_ type: NotebookCellType) {
        switch type {
        case .chart:
            if let index = insertionIndex {
                dataController.insertChartBlock(at: index)
            } else {
                dataController.addChartBlock()
            }
        case .text:
            if let index = insertionIndex {
                dataController.insertTextBlock(at: index)
            } else {
                dataController.addTextBlock()
            }
        case .singleValue:
            if let index = insertionIndex {
                dataController.insertSingleValueBlock(at: index)
            } else {
                dataController.addSingleValueBlock()
            }
        case .query:
            if let index = insertionIndex {
                dataController.insertQueryBlock(at: index)
            } else {
                dataController.addQueryBlock()
            }
        default:
            break
        }
        onDidInsert?()
    }

    func containsInteractiveArea(windowPoint: NSPoint) -> Bool {
        let pointInChrome = chromeView.convert(windowPoint, from: nil)
        return chromeView.bounds.contains(pointInChrome)
    }
}

private final class NotebookActionBarChromeView: NSView {

    private let backgroundLayer = CALayer()
    private let gradientLayer = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(gradientLayer)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        gradientLayer.frame = bounds
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }

    private func updateAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = isDark ? 1 : 0.5

            if isDark {
                backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
                gradientLayer.colors = nil
                layer?.backgroundColor = NSColor.clear.cgColor
            } else {
                backgroundLayer.backgroundColor = NSColor.white.cgColor
                gradientLayer.colors = nil
                layer?.backgroundColor = NSColor.white.cgColor
            }
        }
    }
}

private final class NotebookActionDividerView: NSView {

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
        updateColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    @objc private func handleAppearanceChange() {
        updateColor()
    }

    private func updateColor() {
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}

// MARK: - Fade Line

final class BlockInsertionFadeLine: NSView {

    enum FadeEdge { case leading, trailing }

    private let fadeEdge: FadeEdge
    private let colorLayer = CALayer()
    private let gradientMask = CAGradientLayer()

    init(fadeEdge: FadeEdge) {
        self.fadeEdge = fadeEdge
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true

        layer?.addSublayer(colorLayer)

        gradientMask.colors = [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.cgColor,
        ]
        gradientMask.startPoint = fadeEdge == .leading ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 1, y: 0.5)
        gradientMask.endPoint = fadeEdge == .leading ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0, y: 0.5)
        layer?.mask = gradientMask

        updateColor()

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

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colorLayer.frame = bounds
        gradientMask.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    @objc private func handleAppearanceChange() {
        updateColor()
    }

    private func updateColor() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            colorLayer.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.08).cgColor
                : NSColor.black.withAlphaComponent(0.06).cgColor
        }
    }
}

// MARK: - Block Insertion Indicator (between blocks)

final class BlockInsertionIndicatorView: NSView {

    private let leftLine = BlockInsertionFadeLine(fadeEdge: .leading)
    private let rightLine = BlockInsertionFadeLine(fadeEdge: .trailing)
    private let chrome = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "Add new")
    private let contentStack = NSStackView()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    var onPlusTapped: ((NSView) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        wantsLayer = true

        for line in [leftLine, rightLine] {
            line.alphaValue = 0
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
        }

        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = 7
        chrome.layer?.masksToBounds = true
        chrome.alphaValue = 0
        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome)

        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add block")?
            .withSymbolConfiguration(config)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 3
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(label)
        chrome.addSubview(contentStack)

        NSLayoutConstraint.activate([
            leftLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            leftLine.trailingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: -6),
            leftLine.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftLine.heightAnchor.constraint(equalToConstant: 1),

            rightLine.leadingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: 6),
            rightLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rightLine.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLine.heightAnchor.constraint(equalToConstant: 1),

            chrome.centerXAnchor.constraint(equalTo: centerXAnchor),
            chrome.centerYAnchor.constraint(equalTo: centerYAnchor),
            chrome.heightAnchor.constraint(equalToConstant: 26),

            contentStack.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 5),
            contentStack.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 10),
            contentStack.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -10),
            contentStack.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -5),

            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
        ])

        updateAppearance()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
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
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    override func mouseUp(with event: NSEvent) {
        if isHovering {
            onPlusTapped?(chrome)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }

    private func refreshHoverState() {
        guard let window else {
            if isHovering { setHovered(false) }
            return
        }
        let mousePoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(mousePoint))
    }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovering else { return }
        isHovering = hovered

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = hovered ? 0.15 : 0.1
            let alpha: CGFloat = hovered ? 1 : 0
            leftLine.animator().alphaValue = alpha
            rightLine.animator().alphaValue = alpha
            chrome.animator().alphaValue = alpha
        }
    }

    // MARK: - Appearance

    private func updateAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode

            chrome.layer?.borderColor = NSColor.separatorColor.cgColor
            chrome.layer?.borderWidth = isDark ? 1 : 0.5
            chrome.layer?.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.06).cgColor
                : NSColor.white.cgColor

            iconView.contentTintColor = .secondaryLabelColor
            label.textColor = .secondaryLabelColor
        }
    }
}

private final class NotebookActionButtonView: NSView {

    private let action: () -> Void

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let contentStack = NSStackView()
    private var trackingArea: NSTrackingArea?

    private var isHovering = false
    private var isPressed = false

    init(type: NotebookCellType, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.image = NSImage(systemSymbolName: type.icon, accessibilityDescription: type.rawValue)?
            .withSymbolConfiguration(iconConfig)

        label.stringValue = type.rawValue
        label.font = .systemFont(ofSize: 12)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )

        updateAppearance()
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point), !isHidden, alphaValue > 0 else { return nil }
        return self
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
        isPressed = true
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        let mousePoint = convert(event.locationInWindow, from: nil)
        let isInside = bounds.contains(mousePoint)
        let nextPressed = isInside
        let nextHovering = isInside

        guard nextPressed != isPressed || nextHovering != isHovering else { return }
        isPressed = nextPressed
        isHovering = nextHovering
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let mousePoint = convert(event.locationInWindow, from: nil)
        let isInside = bounds.contains(mousePoint)

        isPressed = false
        isHovering = isInside
        updateAppearance()

        if isInside {
            action()
        }
    }

    @objc private func handleAppearanceChange() {
        updateAppearance()
    }

    private func refreshHoverState() {
        guard let window else {
            if isHovering {
                isHovering = false
                updateAppearance()
            }
            return
        }

        let mousePoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let isInside = bounds.contains(mousePoint)
        guard isInside != isHovering else { return }
        isHovering = isInside
        updateAppearance()
    }

    private func updateAppearance() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = NSAppearance.currentDrawing().isDarkMode
            let isHighlighted = isHovering || isPressed

            if isHighlighted {
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.08).cgColor
                    : NSColor.black.withAlphaComponent(0.06).cgColor
                iconView.contentTintColor = .labelColor
                label.textColor = .labelColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                iconView.contentTintColor = .secondaryLabelColor
                label.textColor = .secondaryLabelColor
            }

            layer?.transform = CATransform3DIdentity
        }
    }
}
